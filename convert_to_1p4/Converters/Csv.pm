# Generic CSV converter
#
# Copyright 2015 Mike Cappella (mike@cappella.us)

package Converters::Csv 1.02;

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

use Text::CSV;

my %card_field_specs = (
    login =>			{ textname => '', fields => [
	[ 'title',		0, qr/^title$/i, ],
	[ 'url',		1, qr/^website|url$/i, ],
	[ 'username',		1, qr/^username$/i, ],
	[ 'password',		1, qr/^password$/i, ],
	[ 'notes',		0, qr/^notes$/i, ],
	[ 'tags',		0, qr/^tags$/i, ],
    ]},
    note =>			{ textname => '', fields => [
    ]},
);

$DB::single = 1;					# triggers breakpoint when debugging

my $custom_field_num = 1;

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
	    sep_char => ',',
	    #eol => "\x{0d}\x{0a}",
    });

    open my $io, "<:encoding(utf8)", $file
	or bail "Unable to open CSV file: $file\n$!";

=cut
    # remove BOM
    my $bom;
    (my $nb = read($io, $bom, 1) == 1 and $bom eq "\x{FEFF}") or
	bail "Failed to read BOM from CSV file: $file\n$!";
=cut

    my $column_names = $csv->getline($io) or
	bail "Failed to parse CSV column names: $!";
    $_ = lc $_  foreach @$column_names;

    # get the card type, and create a hash of the key field names that maps the column names to column positions
    my ($itype, $col_names_to_pos) = find_card_type($column_names);
    %$col_names_to_pos or
	bail "CSV column names do not match expected names";

    # grab and remove the special field column names
    for (sort { $b <=> $a } values %$col_names_to_pos) {
	splice @$column_names, $_, 1;
    }

    my %Cards;
    my ($n, $rownum) = (1, 1);

    while (my $row = $csv->getline($io)) {
	debug 'ROW: ', $rownum++;
	next if defined $imptypes and (! exists $imptypes->{$itype});

	my (@fieldlist, %cmeta);
	# save the special fields to pass to normalize_card_data below, and then remove them from the row.
	for (keys %$col_names_to_pos) {
	    $cmeta{$_} = $_ eq 'tags' ? [ split(/\s*,\s*/, $row->[$col_names_to_pos->{$_}]) ] :  $row->[$col_names_to_pos->{$_}];
	}
	# remove the special field values
	for (sort { $b <=> $a } values %$col_names_to_pos) {
	    splice @$row, $_, 1;
	}

	# everything that remains in the row is the field data
	for (my $i = 0; $i <= $#$column_names; $i++) {
	    push @fieldlist, [ $column_names->[$i] => $row->[$i] ];		# retain field order
	}

	my $normalized = normalize_card_data(\%card_field_specs, $itype, \@fieldlist, \%cmeta);
	my $cardlist   = explode_normalized($itype, $normalized);

	for (keys %$cardlist) {
	    print_record($cardlist->{$_});
	    push @{$Cards{$_}}, $cardlist->{$_};
	}
	$n++;
    }
    if (! $csv->eof()) {
	warn "Unexpected failure parsing CSV: row $n";
    }

    summarize_import('item', $n - 1);
    return \%Cards;
}

sub do_export {
    add_custom_fields(\%card_field_specs);
    create_pif_file(@_);
}

sub find_card_type {
    my $row = shift;
    my $otype = 'note';
    my %col_names_to_pos;

    for my $type (keys %card_field_specs) {
	for my $cfs (@{$card_field_specs{$type}{'fields'}}) {
	    for (my $i = 0; $i <= $#$row; $i++) {
		if (defined $cfs->[CFS_MATCHSTR] and $row->[$i] =~ /$cfs->[CFS_MATCHSTR]/ms) {
		    $otype = $type	 			if $cfs->[CFS_TYPEHINT];
		    $col_names_to_pos{$cfs->[CFS_FIELD]} = $i	if $cfs->[CFS_FIELD] =~ /^title|notes|tags$/;
		}
	    }
	}
    }

    debug "\t\ttype detected as '$otype'";
    return ($otype, \%col_names_to_pos);
}

1;
