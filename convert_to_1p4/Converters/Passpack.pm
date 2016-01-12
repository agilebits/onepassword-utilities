# Passpack CSV export converter
#
# Copyright 2015 Mike Cappella (mike@cappella.us)

package Converters::Passpack 1.01;

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
	[ 'title',		0, qr/^title$/, ],
	[ 'username',		0, qr/^username$/, ],
	[ 'password',		0, qr/^password$/, ],
	[ 'url',		0, qr/^url$/, ],
	[ 'notes',		0, qr/^notes$/, ],
	[ 'email',		0, qr/^email$/,		{ custfield => [ 'other.Other Information', $Utils::PIF::k_string, 'email' ] } ],
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
	    #allow_loose_quotes => 1,
	    sep_char => ",",
	    eol => "\n",
    });

    open my $io, "<:encoding(utf8)", $file
	or bail "Unable to open CSV file: $file\n$!";

    if ($^O eq 'MSWin32') {
	# remove BOM
	my $bom;
	(my $nb = read($io, $bom, 1) == 1 and $bom eq "\x{FEFF}") or
	    bail "Failed to read BOM from CSV file: $file\n$!";
    }

    my %Cards;
    my ($n, $rownum) = (1, 1);

    $csv->column_names(qw/title username password url tags notes email/);
    while (my $row = $csv->getline_hr($io)) {
	debug 'ROW: ', $rownum++;

	my $itype = find_card_type($row);

	next if defined $imptypes and (! exists $imptypes->{$itype});

	my (%cmeta, @fieldlist);
	# Grab the special fields and delete them from the row
	@cmeta{qw/title notes tags/} = @$row{qw/title notes tags/};
	delete @$row{qw/title notes tags/};

	# Everything that remains in the row is the the field data
	for (keys %$row) {
	    debug "\tcust field: $_ => $row->{$_}";
	    push @fieldlist, [ $_ => $row->{$_} ];
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
    my $hr = shift;
    my $type = ($hr->{'url'} ne '' or $hr->{'username'} ne '' or $hr->{'password'} ne '') ? 'login' : 'note';
    debug "type detected as '$type'";
    return $type;
}

1;
