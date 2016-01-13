# LicenseKeeper XML export converter
#
# Copyright 2015 Mike Cappella (mike@cappella.us)

package Converters::Licensekeeper 1.04;

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
use Utils::Utils;
use Utils::Normalize;

use Encode;
use File::Basename;
use File::Spec;
use XML::XPath;
use XML::XPath::XMLParser;
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

    $_ = slurp_file($file);

    $attachmentdir = File::Spec->catfile( dirname($file), 'Attachments' );

    my $n = 1;

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

	my (%cmeta, @fieldlist);

	$cmeta{'title'} = $inCards{$cid}{'title'} // '';
	$cmeta{'notes'} = decode_base64($inCards{$cid}{'comments'})	if exists $inCards{$cid}{'comments'};
	Encode::_utf8_on($cmeta{'notes'});	# byte sequence is in utf8
	delete $inCards{$cid}{$_}		for qw/title comments/;

	# handle renaming of attachments
	do_rename($_, $cmeta{'title'})	for @{$inCards{$cid}{'ATTACHMENTS'}};
	delete $inCards{$cid}{'ATTACHMENTS'};

	for (keys %{$inCards{$cid}}) {
	    debug "\t    Field: ", ucfirst $_, ' = ', $inCards{$cid}{$_};
	    push @fieldlist, [ $_ => $inCards{$cid}{$_} ];
	}

	my $normalized = normalize_card_data(\%card_field_specs, $itype, \@fieldlist, \%cmeta);
	my $cardlist   = explode_normalized($itype, $normalized);

	for (keys %$cardlist) {
	    print_record($cardlist->{$_});
	    push @{$Cards{$_}}, $cardlist->{$_};
	}
	$n++;
    }

    summarize_import('item', $n - 1);
    return \%Cards;
}

sub do_export {
    add_custom_fields(\%card_field_specs);
    create_pif_file(@_);
}

# Converts a Password Depot number of days since 12/31/1899 value into a 1Password epoch value
sub secs2epoch {
    my $secs = shift;

    my ($year,$month,$day, $hour,$min,$sec) =
	  Add_Delta_DHMS(2000,12,31,0,0,0, 0,0,0,$secs);

    return timelocal(0, 0, 0, $day, $month - 1, $year);
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
