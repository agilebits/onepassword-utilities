# Norton Identity Safe CSV export converter
#
# Copyright 2015 Mike Cappella (mike@cappella.us)

package Converters::Nortonis 1.00;

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
use Text::CSV;

my %card_field_specs = (
    login =>			{ textname => '', fields => [
	[ 'url',		0, qr/^url$/, ],
	[ 'username',		0, qr/^username$/, ],
	[ 'password',		0, qr/^password$/, ],
	[ 'title',		0, qr/^title$/, ],
	[ '_grouping',		0, qr/^grouping$/, ],
	[ '_extra',		0, qr/^extra$/, ],
    ]},
    note =>			{ textname => '', fields => [
    ]},
);

$DB::single = 1;					# triggers breakpoint when debugging

sub do_init {
    return {
	'specs'		=> \%card_field_specs,
	'imptypes'  	=> undef,
        'opts'          => [],
    }
}

sub do_import {
    my ($file, $imptypes) = @_;

    my $csv = Text::CSV->new ({
	    binary => 1,
	    allow_loose_quotes => 0,
	    sep_char => ",",
	    eol => $^O eq 'MSWin32' ? "\x0d\x0a" : "\n",
    });

    open my $io, $^O eq 'MSWin32' ? "<:encoding(utf16LE)" : "<:encoding(utf8)", $file
	or bail "Unable to open CSV file: $file\n$!";

    if ($^O eq 'MSWin32') {
	# remove BOM
	my $bom;
	(my $nb = read($io, $bom, 1) == 1 and $bom eq "\x{FEFF}") or
	    bail "Failed to read BOM from CSV file: $file\n$!";
    }

    my %Cards;
    my ($n, $rownum) = (1, 1);
    my ($npre_explode, $npost_explode);

    my @colnames = $csv->getline($io) or
	bail "Failed to get CSV column names from first row";
    $csv->column_names(@colnames);

    while (my $row = $csv->getline_hr($io)) {
	debug 'ROW: ', $rownum++;

	my $itype = find_card_type($row);

	next if defined $imptypes and (! exists $imptypes->{$itype});

	# Grab the special fields and delete them from the row
	my ($card_title, $card_notes, $card_tags) = @$row{qw/name extra grouping/};
	delete @$row{qw/name extra grouping/};

	my @fieldlist;
	# Everything that remains in the row is the the field data
	for (keys %$row) {
	    debug "\tcust field: $_ => $row->{$_}";
	    if ($itype eq 'note' and $row->{'url'} eq 'http://sn') {
		$row->{'url'} = '';
	    }
	    push @fieldlist, [ $_ => $row->{$_} ];
	}

	my $normalized = normalize_card_data($itype, \@fieldlist, 
	    { title	=> $card_title,
	      notes	=> $card_notes,
	      tags	=> $card_tags });

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
    if (! $csv->eof()) {
	warn "Unexpected failure parsing CSV: row $n";
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

sub find_card_type {
    my $hr = shift;
    my $type = 'note';
    if ($hr->{'url'} ne 'http://sn') {
	for (qw /username password/) {
	    if (defined $hr->{$_} and $hr->{$_} ne '') {
		$type = 'login';
		last;
	    }
	}
    }

    debug "type detected as '$type'";
    return $type;
}

1;
