# KeePass 2 XML export converter
#
# Copyright 2014 Mike Cappella (mike@cappella.us)

package Converters::Keepass2 1.03;

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
use File::Path qw(make_path);
use XML::XPath;
use XML::XPath::XMLParser;
use HTML::Entities;
use Time::Local qw(timegm);
use Time::Piece;
use Compress::Raw::Zlib;
use MIME::Base64;

my %card_field_specs = (
    login =>			{ textname => undef, fields => [
	[ 'url',		1, qr/^URL$/, ],
	[ 'username',		1, qr/^UserName$/, ],
	[ 'password',		1, qr/^Password$/, ],
    ]},
    note =>                     { textname => undef, fields => [
    ]},
);

$DB::single = 1;					# triggers breakpoint when debugging

my %fields = ();
my @gCards;
my $attachdir;

sub do_init {
    return {
	'specs'		=> \%card_field_specs,
	'imptypes'  	=> undef,
	'opts'		=> [ [ q{-m or --modified           # set item's last modified date },
			       'modified|m' ],
			   ],
    };
}

sub do_import {
    my ($file, $imptypes) = @_;

    $attachdir = File::Spec->catfile(dirname($main::opts{'outfile'}), '1P4_Attachments');
    my $xp = XML::XPath->new(filename => $file);

    my %attachments;
    foreach my $binnode ($xp->findnodes('/KeePassFile/Meta/Binaries/Binary')) {
	my $id = $binnode->getAttribute('ID');
	$attachments{$id}{'iscompressed'} = ($binnode->getAttribute('Compressed') eq 'True');
	$attachments{$id}{'data'} = $binnode->string_value;
    }

    my $groupnodes = $xp->find('/KeePassFile/Root//Group');
    foreach my $groupnode ($groupnodes->get_nodelist) {
	my @group = get_group_path($xp, $groupnode);
	my $entrynodes = $xp->find('./Entry', $groupnode);
	    foreach my $entrynode ($entrynodes->get_nodelist) {
		debug "ENTRY:";
		%fields = ();
		debug "Node: ", $entrynode->getName;
		foreach my $element ($entrynode->getChildNodes) {
		    next unless scalar $element->getName;
		    debug "Element: ", $element->getName;
		    if ($element->getName eq 'String') {
			my ($key, $value);
			$key = ($xp->findnodes('./Key', $element))[0]->string_value;
			$value = ($xp->findnodes('./Value', $element))[0]->string_value;
			$fields{$key} = $value;
			debug "\tkey: $key: '$value'";

		    }
		    if ($element->getName eq 'Binary') {
			my %a = (
			    filename => ($xp->findnodes('./Key',   $element))[0]->string_value,
			    id       => ($xp->findnodes('./Value', $element))[0]->getAttribute('Ref'),
			);
			debug "\tAttachment $a{'id'}: '$a{'filename'}";
			push @{$fields{"__ATTACHMENTS__"}}, \%a;
		    }
		    elsif ($main::opts{'modified'} and $element->getName eq 'Times') {
			my $mtime = ($xp->findnodes('./LastModificationTime', $element))[0]->string_value;
			debug " **** Field: LastModificationTime: ==> '$mtime'";
			$fields{'LastModificationTime'} = date2epoch($mtime);
		    }
		}
		$fields{'Tags'} = join '::', @group;
		$fields{'Folder'} = [ @group ];
		push @gCards, { %fields };
	    }
    }

    @gCards or
	bail "No entries detected in the export file\n";

    my %Cards;
    my $n = 1;
    my ($npre_explode, $npost_explode);
    for my $c (@gCards) {
	my ($card_title, $card_tags, $card_notes, $card_folder, $card_modified) =
	    ($c->{'Title'}, $c->{'Tags'}, $c->{'Notes'}, $c->{'Folder'}, $c->{'LastModificationTime'});
	delete @{$c}{qw/Title Tags Notes Folder LastModificationTime/};

	my $itype = find_card_type($c);

	# skip all types not specifically included in a supplied import types list
	next if defined $imptypes and (! exists $imptypes->{$itype});

	# handle creation of attachment files from encoded / compressed string
	my $dir;
	for (@{$c->{'__ATTACHMENTS__'}}) {
	    $dir = create_attachment($attachments{$_->{'id'}}, $dir, $_->{'filename'}, $card_title);
	}
	delete $c->{'__ATTACHMENTS__'};

	# From the card input, place it in the converter-normal format.
	# The card input will have matched fields removed, leaving only unmatched input to be processed later.
	my $normalized = normalize_card_data($itype, $c, 
	    { title	=> $card_title,
	      tags	=> $card_tags,
	      notes	=> $card_notes // '',
	      folder	=> $card_folder,
	      modified	=> $card_modified });

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

sub find_card_type {
    my $c = shift;
    my $type;

    for $type (sort by_test_order keys %card_field_specs) {
	for my $def (@{$card_field_specs{$type}{'fields'}}) {
	    for my $key (keys %$c) {
		# type hint
		if ($def->[1] and $key =~ $def->[2]) {
		    debug "type detected as '$type' (key='$key')";
		    return $type;
		}
	    }
	}
    }

    return 'note';
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
    my ($type, $carddata, $norm_cards) = @_;

    for my $def (@{$card_field_specs{$type}{'fields'}}) {
	my $h = {};
	for (keys %$carddata) {
	    my ($inkey, $value) = ($_, $carddata->{$_});
	    next if not defined $value or $value eq '';

	    if ($inkey =~ $def->[2]) {
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
		delete $carddata->{$_};		# delete matched so undetected are pushed to notes below
	    }
	}
    }

    # map remaining keys to notes
    $norm_cards->{'notes'} .= "\n"	if length $norm_cards->{'notes'} > 0 and keys %$carddata;
    for (keys %$carddata) {
	next if $carddata->{$_} eq '';
	$norm_cards->{'notes'} .= "\n"	if length $norm_cards->{'notes'} > 0;
	$norm_cards->{'notes'} .= join ': ', $_, $carddata->{$_};
    }

    return $norm_cards;
}

# sort logins as the last to check
sub by_test_order {
    return  1 if $a eq 'login';
    return -1 if $b eq 'login';
    $a cmp $b;
}

sub get_group_path {
    my ($xp, $node) = @_;

    my @names;
    while ($node->getName ne 'Root') {
	unshift @names, ($xp->findnodes('./Name', $node))[0]->string_value;
	$node = $node->getParentNode;
    }

    shift @names;
    debug "\tGROUP: ", join '::', @names;
    return @names;
}

# Date converters
# LastModificationTime field:	 yyyy-mm-ddThh:mm:ssZ
sub parse_date_string {
    local $_ = $_[0];
    my $when = $_[1] || 0;					# -1 = past only, 0 = assume this century, 1 = future only, 2 = 50-yr moving window

    if (my $t = Time::Piece->strptime($_, "%Y-%m-%dT%H:%M:%SZ")) {	# KeePass 2 dates are in standard UTC string format
	return $t;
    }

    return undef;
}

sub date2epoch {
    my $t = parse_date_string @_;
    return defined $t->year ? 0 + timegm($t->sec, $t->minute, $t->hour, $t->mday, $t->mon - 1, $t->year): $_[0];
}

sub create_attachment {
    my ($a, $dir, $filename, $title) = @_;

    my $data;
    if ($a->{'iscompressed'}) {
	my $inf = new Compress::Raw::Zlib::Inflate('-WindowBits' => WANT_GZIP_OR_ZLIB) ;
	my $status = $inf->inflate(decode_base64($a->{'data'}), $data);
	if ($status ne 'stream end') {
	    warn "Failed to inflate compressed data: $filename\n$!";
	    return;
	}
    }
    else {
	$data = decode_base64 $a->{'data'};
    }

    if (!$dir) {
	$dir = File::Spec->catfile($attachdir, fs_safe($title));
	if (-e $dir) {
	    my $i;
	    for ($i = 1; $i <= 1000; $i++) {
		my $uniqdir = sprintf "%s (%d)", $dir, $i;
		next if -e $uniqdir;
		$dir = $uniqdir;
		last;
	    }
	    if ($i > 1000) {
		warn "Failed to create unique attachment directory: $dir\n$!";
		return;
	    }
	}
    }
    if (! -e $dir and ! make_path($dir)) {
	warn "Failed to create attachment directory: $dir\n$!";
	return;
    }
    $filename = File::Spec->catfile($dir, fs_safe($filename));
    if (! open FD, ">", $filename) {
	warn "Failed to create new file for attachment: $filename\n$!";
	return;;
    }
    print FD $data;
    close FD;
    verbose "Attachment created: $filename";

    return $dir;
}

sub fs_safe {
    local $_ = shift;
    s/[:\/\\*?"<>|]//g;         # remove FS-unsafe chars
    return $_;
}

1;
