# KeePassX XML export converter
#
# Copyright 2014 Mike Cappella (mike@cappella.us)

package Converters::Keepassx 1.01;

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
use XML::XPath;
use XML::XPath::XMLParser;
use Time::Local qw(timelocal);
use Time::Piece;

my %card_field_specs = (
    login =>			{ textname => undef, fields => [
	[ 'url',		1, qr/^url$/, ],
	[ 'username',		1, qr/^username$/, ],
	[ 'password',		1, qr/^password$/, ],
    ]},
    note =>                     { textname => undef, fields => [
    ]},
);

$DB::single = 1;					# triggers breakpoint when debugging

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

    {
	local $/ = undef;
	open my $fh, '<', $file or bail "Unable to open file: $file\n$!";
	$_ = <$fh>;
	s!<br/>!\n!g;
	close $fh;
    }

    my %Cards;
    my $n = 1;
    my ($npre_explode, $npost_explode);

    my $xp = XML::XPath->new(xml => $_);
    my $groupnodes = $xp->find('//group');
    foreach my $groupnode ($groupnodes->get_nodelist) {
	my (@groups, $card_tags);
	for (my $node = $groupnode; my $parent = $node->getParentNode(); $node = $parent) {
	    my $v = $xp->findvalue('title', $node)->value();
	    unshift @groups, $v   unless $v eq '';
	}
	$card_tags = join '::', @groups;
	debug 'Group: ', $card_tags;
	my $entrynodes = $xp->find('entry', $groupnode);
	foreach my $entrynode ($entrynodes->get_nodelist) {
	    debug "\tEntry:";
	    my @fields;

	    my $card_title = $xp->findvalue('title',   $entrynode)->value();
	    my $card_notes = $xp->findvalue('comment', $entrynode)->value();
	    my $card_modified;

	    for (qw/username password url lastaccess lastmod creation expire/) {
		my $val = $xp->findvalue($_, $entrynode)->value();
		next if $val eq '';
		if ($main::opts{'modified'} and $_ eq 'lastmod') {
		    $card_modified = date2epoch($val);
		}
		else  {
		    push @fields, [ $_ => $val ];		# retain field order
		}
		debug "\t\t$_: ", $val;
	    }

	    my $itype = find_card_type(\@fields);

	    # skip all types not specifically included in a supplied import types list
	    next if defined $imptypes and (! exists $imptypes->{$itype});

	    # From the card input, place it in the converter-normal format.
	    # The card input will have matched fields removed, leaving only unmatched input to be processed later.
	    my $normalized = normalize_card_data($itype, \@fields,
		{ title		=> $card_title,
		  tags		=> $card_tags,
		  notes		=> $card_notes // '',
		  folder	=> \@groups,
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
    my $type = grep($_->[0] =~ /^url|username|password$/, @{$_[0]}) ? 'login' : 'note';
    debug "type detected as '$type'";
    return $type;
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
		splice @$fieldlist, $i, 1;	# delete matched so undetected are pushed to notes below
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

# Date converters
# lastmod field:	 yyyy-mm-ddThh:mm:ss
sub parse_date_string {
    local $_ = $_[0];
    my $when = $_[1] || 0;					# -1 = past only, 0 = assume this century, 1 = future only, 2 = 50-yr moving window

    if (my $t = Time::Piece->strptime($_, "%Y-%m-%dT%H:%M:%S")) {	# KeePassX dates are in standard UTC string format, no TZ
	return $t;
    }

    return undef;
}

sub date2epoch {
    my $t = parse_date_string @_;
    return defined $t->year ? 0 + timelocal($t->sec, $t->minute, $t->hour, $t->mday, $t->mon - 1, $t->year): $_[0];
}
1;
