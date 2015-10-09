# LicenseKeeper XML export converter
#
# Copyright 2015 Mike Cappella (mike@cappella.us)

package Converters::Licensekeeper 1.03;

our @ISA 	= qw(Exporter);
our @EXPORT     = qw(do_init do_import do_export);
our @EXPORT_OK  = qw();

use v5.14;
use utf8;
use strict;
use warnings;
#use diagnostics;

binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

use Utils::PIF;
use Utils::Utils qw(verbose debug bail pluralize myjoin print_record);
use File::Basename;
use File::Spec;
use XML::XPath;
use XML::XPath::XMLParser;
use Encode;
use MIME::Base64;
use Time::Local qw(timelocal);
use Date::Calc qw(Add_Delta_DHMS);

my %card_field_specs = (
    software =>       { textname => undef, type_out => 'software', fields => [
	[ 'reg_code',		0, qr/^serialnumber$/, ],
	[ 'reg_name',		0, qr/^registeredname$/, ],
	[ 'reg_email',		0, qr/^registeredemail$/, ],
	[ 'company',		0, qr/^registeredcompany$/, ],
	[ 'retail_price',	0, qr/^purchaseprice$/, ],
	[ 'order_number',	0, qr/^purchaseordernumber$/, ],
	[ 'publisher_name',	0, qr/^publisher$/, ],
	[ 'publisher_website',	0, qr/^productwebsite$/, ],
	[ 'product_version',	0, qr/^productversion$/, ],
	[ 'support_email',	0, qr/^productemail$/, ],
	[ 'order_date',		0, qr/^purchasedate$/,		{ func => sub { return secs2epoch($_[0]) } } ],
    ]},
);

$DB::single = 1;					# triggers breakpoint when debugging

sub do_init {
    return {
	'specs'		=> \%card_field_specs,
	'imptypes'  	=> undef,
	'opts'		=> [ ],
    };
}

my (%attachedfile, %attachedcontent, $attachmentdir);

sub do_import {
    my ($file, $imptypes) = @_;
    my %inCards;

    {
	local $/ = undef;
	open my $fh, '<', $file or bail "Unable to open file: $file\n$!";
	$_ = <$fh>;
	close $fh;
    }

    $attachmentdir = File::Spec->catfile( dirname($file), 'Attachments' );

    my $n = 1;
    my ($npre_explode, $npost_explode);


    my $xp = XML::XPath->new(xml => $_);

    my $nodeset = $xp->find('/database/object');
    foreach my $node ($nodeset->get_nodelist()) {

	my ($nodetype, $nodeid) = ($node->getAttribute('type'), $node->getAttribute('id'));
	debug "$nodetype: $nodeid";
	foreach my $childnode ($node->getChildNodes) {
	    my $elname = $childnode->getName;
	    next if not defined $elname;

	    my $attr_name = $childnode->getAttribute('name');
	    debug "    $elname, $attr_name";

	    if ($nodetype eq 'PRODUCT') {
		debug "   CHILD $elname, $attr_name, ", $childnode->string_value;
		next if $attr_name =~ /^uuid|appicon$/;
		if ($elname eq 'attribute') {
		    $inCards{$nodeid}{$attr_name} = clean_unicode($childnode->string_value);
		}
		elsif ($elname eq 'relationship' and $attr_name eq 'attachedfiles') {
		    @{$inCards{$nodeid}{'ATTACHMENTS'}} = split /\s+/, $childnode->getAttribute('idrefs');
		}
	    }
	    elsif ($nodetype eq 'ATTACHEDFILE') {
		if ($attr_name eq 'name' and $childnode->getAttribute('type') eq 'string') {
		    $attachedfile{$nodeid}{'filename'} = $childnode->string_value;
		}
		elsif ($attr_name eq 'content') {
		    $attachedfile{$nodeid}{'contentid'} = $childnode->getAttribute('idrefs');
		}
	    }
	    elsif ($nodetype eq 'EMAILRECEIPT') {
		if ($attr_name eq 'name') {
		    # force the file suffix to .eml, so it is opened with the mail program
		    # when double-clicked
		    $attachedfile{$nodeid}{'filename'} = join '.', $childnode->string_value, 'eml';
		}
		elsif ($attr_name eq 'content') {
		    $attachedfile{$nodeid}{'contentid'} = $childnode->getAttribute('idrefs');
		}
	    }
	    elsif ($nodetype eq 'ATTACHMENTCONTENT') {
		if ($childnode->getAttribute('name') eq 'uuid') {
		    $attachedcontent{$nodeid}{'uuid'} = $childnode->string_value;
		}
	    }
	}
    }

    my %Cards;
    my $itype = 'software';

    for my $cid (keys %inCards) {
	# skip all types not specifically included in a supplied import types list
	next if defined $imptypes and (! exists $imptypes->{$itype});

	my %kvpairs = ();

	my $card_title = $inCards{$cid}{'title'} // '';
	my $card_notes = decode_base64($inCards{$cid}{'comments'})	if exists $inCards{$cid}{'comments'};
	Encode::_utf8_on($card_notes);	# byte sequence is in utf8
	delete $inCards{$cid}{$_}		for qw/title comments/;

	# handle renaming of attachments
	do_rename($_, $card_title)	for @{$inCards{$cid}{'ATTACHMENTS'}};
	delete $inCards{$cid}{'ATTACHMENTS'};

	# set the field / value pairs
	for (keys $inCards{$cid}) {
	    $kvpairs{$_} = $inCards{$cid}{$_};
	    debug "\t    Field: ", ucfirst $_, ' = ', $kvpairs{$_};
	}

	my @fieldlist;
	for (keys %kvpairs) {
	    push @fieldlist, [ $_ => $kvpairs{$_} ];			# done for confority with other converters - no inherent field order
	}

	# From the card input, place it in the converter-normal format.
	# The card input will have matched fields removed, leaving only unmatched input to be processed later.
	my $normalized = normalize_card_data($itype, \@fieldlist,
	    { title	=> $card_title,
	      notes	=> $card_notes });

	# Returns list of 1 or more card/type hashes; one input card may explode into multiple output cards
	my $cardlist = explode_normalized($itype, $normalized);

	my @k = keys %$cardlist;
	if (@k > 1) {
	    $npre_explode++; $npost_explode += @k;
	    debug "\tcard type $itype expanded into ", scalar @k, " cards of type @k"
	}
	for (@k) {
	    print_record($cardlist->{$_});
	    push @{$Cards{$_}}, $cardlist->{$_};
	}
	$n++;
    }

    $n--;
    verbose "Imported $n card", pluralize($n) ,
	$npre_explode ? " ($npre_explode card" . pluralize($npre_explode) .  " expanded to $npost_explode cards)" : "";
    return \%Cards;
}

sub do_export {
    create_pif_file(@_);
}

# Places card data into a normalized internal form.
#
# Basic card data passed as $norm_cards hash ref:
#    title
#    notes
#    tags
#    folder
#    modified
# Per-field data hash {
#    inkey	=> imported field name
#    value	=> field value after callback processing
#    valueorig	=> original field value
#    outkey	=> exported field name
#    outtype	=> field's output type (may be different than card's output type)
#    keep	=> keep inkey:valueorig pair can be placed in notes
#    to_title	=> append title with a value from the narmalized card
# }
sub normalize_card_data {
    my ($type, $fieldlist, $norm_cards) = @_;

    for my $def (@{$card_field_specs{$type}{'fields'}}) {
	my $h = {};
	for (my $i = 0; $i < @$fieldlist; $i++) {
	    my ($inkey, $value) = @{$fieldlist->[$i]};
	    next if not defined $value or $value eq '';

	    if (!defined $def->[2] or $inkey =~ $def->[2]) {
		my $origvalue = $value;

		if (exists $def->[3] and exists $def->[3]{'func'}) {
		    #         callback(value, outkey)
		    my $ret = ($def->[3]{'func'})->($value, $def->[0]);
		    $value = $ret	if defined $ret;
		}
		$h->{'inkey'}		= $inkey;
		$h->{'value'}		= $value;
		$h->{'valueorig'}	= $origvalue;
		$h->{'outkey'}		= $def->[0];
		$h->{'outtype'}		= $def->[3]{'type_out'} || $card_field_specs{$type}{'type_out'} || $type; 
		$h->{'keep'}		= $def->[3]{'keep'} // 0;
		$h->{'to_title'}	= ' - ' . $h->{$def->[3]{'to_title'}}	if $def->[3]{'to_title'};
		push @{$norm_cards->{'fields'}}, $h;
		splice @$fieldlist, $i, 1;	# delete matched so undetected are pushed to notes below
		last;
	    }
	}
    }

    # map remaining keys to notes
    $norm_cards->{'notes'} .= "\n"	if defined $norm_cards->{'notes'} and length $norm_cards->{'notes'} > 0 and @$fieldlist;
    for (@$fieldlist) {
	next if $_->[1] eq '';
	$norm_cards->{'notes'} .= "\n"	if defined $norm_cards->{'notes'} and length $norm_cards->{'notes'} > 0;
	$norm_cards->{'notes'} .= join ': ', @$_;
    }

    return $norm_cards;
}

# Converts a Password Depot number of days since 12/31/1899 value into a 1Password epoch value
sub secs2epoch {
    my $secs = shift;

    my ($year,$month,$day, $hour,$min,$sec) =
	  Add_Delta_DHMS(2000,12,31,0,0,0, 0,0,0,$secs);

    return timelocal(0, 0, 0, $day, $month - 1, $year);
}

sub fs_safe {
    local $_ = shift;
    s/[:\/\\*?"<>|]/_/g;		# replace FS-unsafe chars
    return $_;
}

# LicenseKeeper is not correct encoding XML-unsafe characters within the XML.
sub clean_unicode {
    local $_ = shift;
    s/\\u3c00/</g;
    s/\\u3e00/>/g;
    s/\\u2600/&/g;
    return $_;
}

sub do_rename {
    my ($id, $title) = @_;

    my $oldname = $attachedcontent{$attachedfile{$_}{'contentid'}}{'uuid'};
    my $oldpath = File::Spec->catfile($attachmentdir, $oldname);
    return if ! -e $oldpath;

    my $newname = $attachedfile{$_}{'filename'};
    my $newpath = File::Spec->catfile($attachmentdir, fs_safe(sprintf "%s - %s", $title, $newname));

    verbose "Attachment: $id: renamed $oldname --> $newname";
    rename($oldpath, $newpath) or
	warn "Failed to rename attachment: $oldpath to $newpath: $!";
}

1;
