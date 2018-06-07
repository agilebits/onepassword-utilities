# Keeper HTML export converter
#
# Copyright 2015 Mike Cappella (mike@cappella.us)

package Converters::Keeper 1.01;

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
use HTML::Entities;

my %card_field_specs = (
    login =>                    { textname => undef, fields => [
        [ 'url',		1, 'Login URL', ],
        [ 'username',		1, 'Login', ],
        [ 'password',		1, 'Password', ],
    ]},
);

$DB::single = 1;					# triggers breakpoint when debugging

sub do_init {
    return {
	'specs'		=> \%card_field_specs,
	'imptypes'  	=> undef,
        'opts'          => [],
    };
}

sub do_import {
    my ($file, $imptypes) = @_;
    my %Cards;

    my $data = slurp_file($file, 'UTF-8');

    my $n;
    if ($data =~ m#^.*?<tr>(.*?)</tr>#ims) {
	$n = process_html(\$data, \%Cards, $imptypes);
    }
    else {
	$n = process_csv($file, \%Cards, $imptypes);
    }
	
    summarize_import('item', $n - 1);
    return \%Cards;
}

sub process_csv {
    my ($file, $Cards, $imptypes) = @_;

    my $csv = Text::CSV->new ({
	    binary =>	1,
	    sep_char =>	",",
	    #eol => 	$^O eq 'MSWin32' ? "\x{0d}\x{0a}" : "\n",
	    eol => 	"\n",
    });

    open my $io,  "<:encoding(utf8)", $file or
	bail "Unable to open file for reading: $file";

    if ($^O eq 'MSWin32') {
	# remove possible BOM
	my $bom;
	if (my $nb = read($io, $bom, 1) == 1) {
	    if ($bom ne "\x{FEFF}") {		# no BOM, reopen the file
		close $io;
		open $io,  "<:encoding(utf8)", $file or
		    bail "Unable to open file for reading: $file";
	    }
	}
    }

    my ($n, $rownum) = (1, 1);
    while (my $row = $csv->getline($io)) {
        debug 'ROW: ', $rownum++;

	my (%cmeta, @fieldlist, $tmp);
        if ($tmp = shift @$row) {
	    $cmeta{'tags'}	=   $tmp;
	    $cmeta{'folder'}	= [ $tmp ];
	}
        $cmeta{'title'}	= (shift @$row) || 'Untitled';
	push @fieldlist, [ 'Login'	=> shift @$row ];
	push @fieldlist, [ 'Password'	=> shift @$row ];
	push @fieldlist, [ 'Login URL'	=> shift @$row ];
	my $notes = shift @$row;
        $cmeta{'notes'}	= $notes	if defined $notes;
	shift @$row;						# unknown field - maybe attachment?

	while (@$row) {
	    push @fieldlist, [ $row->[0] => $row->[1] ]		if $row->[1] ne '';
	    shift @$row; shift @$row;
	}

	if (do_common($Cards, \@fieldlist, \%cmeta, $imptypes)) {
	    $n++;
	}
    }
    return $n;
}

sub process_html {
    my ($data, $Cards, $imptypes) = @_;

    my $n = 1;
    my @labels;
    while ($$data =~ s#^.*?<tr>(.*?)</tr>##ims) {
	$_ = $1;

	next if /<td colspan="\d+">/ims;		# skip page headings

	# get the table column labels
	if (/<th>/i) {
	    push @labels, decode_entities($1)	 while s/<th>(.+?)<\/th>//ims;
	    splice @labels, 0, 2;	# get rid of Folder and Title
	    splice @labels, 3, 1;	# get rid of Notes
	    next;
	}
	elsif (! /<td>/i) {
	    next;
	}

	my (%cmeta, @fieldlist, @values);

	# get the table column values
	push @values, decode_entities($1)	 while s/<td>(.*?)<\/td>//ims;

	# pull out the meta data
	if (my $folder = shift @values) {
	    $cmeta{'tags'}	=   $folder;
	    $cmeta{'folder'}	= [ $folder ];
	}
	$cmeta{'title'} = shift(@values) || 'Untitled';
	my $note = splice(@values, 3, 1);
	$cmeta{'notes'} = $note	if $note ne '';

	# populate @fieldlist
	for (my $i = 0; $i < @labels; $i++) {
	    next if $values[$i] eq '';
	    push @fieldlist, [ $labels[$i] => $values[$i] ];
	}

	if (do_common($Cards, \@fieldlist, \%cmeta, $imptypes)) {
	    $n++;
	}
    }

    return $n;
}

sub do_common {
    my ($Cards, $fieldlist, $cmeta, $imptypes) = @_;

    my $itype = find_card_type($fieldlist);

    # skip all types not specifically included in a supplied import types list
    return undef	if defined $imptypes and (! exists $imptypes->{$itype});

    my $normalized = normalize_card_data(\%card_field_specs, $itype, $fieldlist, $cmeta);
    my $cardlist   = explode_normalized($itype, $normalized);

    for (keys %$cardlist) {
	print_record($cardlist->{$_});
	push @{$Cards->{$_}}, $cardlist->{$_};
    }

    return 1;
}

sub do_export {
    add_custom_fields(\%card_field_specs);
    create_pif_file(@_);
}

sub find_card_type {
    my $fieldlist = shift;

    for my $type (keys %card_field_specs) {
	for my $cfs (@{$card_field_specs{$type}{'fields'}}) {
	    for (@$fieldlist) {
		if ($cfs->[CFS_TYPEHINT] and $_->[0] eq $cfs->[CFS_MATCHSTR]) {
		    debug "type detected as '$type' (key='$_->[0]')";
		    return $type;
		}
	    }
	}
    }

    debug "\t\ttype defaulting to 'note'";
    return 'note';
}

1;
