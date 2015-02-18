# EssentialPIM CSV export converter
#
# Copyright 2015 Mike Cappella (mike@cappella.us)

package Converters::Essentialpim 1.00;

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
    password =>			{ textname => '', type_out => 'login', fields => [
	[ 'title',		0, qr/^Title$/, ],
	[ 'username',		1, qr/^User Name$/, ],
	[ 'password',		1, qr/^Password$/, ],
	[ 'url',		1, qr/^URL$/, ],
	[ 'notes',		0, qr/^Notes$/, ],
    ]},
    note =>			{ textname => 'Note', fields => [
    ]},
);

$DB::single = 1;					# triggers breakpoint when debugging

sub do_init {
    return {
	'specs'		=> \%card_field_specs,
	'imptypes'  	=> qw/userdefined/,
        'opts'          => [],
    }
}

sub do_import {
    my ($file, $imptypes) = @_;

    my $csv = Text::CSV->new ({
	    binary => 1,
	    allow_loose_quotes => 1,
	    sep_char => ',',
	    eol => ",\n",
    });

    open my $io, "<:encoding(utf8)", $file
	or bail "Unable to open CSV file: $file\n$!";

    # remove BOM
    my $bom;
    (my $nb = read($io, $bom, 1) == 1 and $bom eq "\x{FEFF}") or
	bail "Failed to read BOM from CSV file: $file\n$!";

    my $column_names = $csv->getline($io) or
	bail "Failed to parse CSV column names: $!";

    # get the card type, and create a hash of the key field names that maps the column names to column positions
    my ($itype, $card_names_to_pos) = find_card_type($column_names);
    %$card_names_to_pos or
	bail "CSV column names do not match expected names";

    # grab and remove the special field column names
    for (sort { $b <=> $a } values $card_names_to_pos) {
	splice @$column_names, $_, 1;
    }

    my %Cards;
    my ($n, $rownum) = (1, 1);
    my ($npre_explode, $npost_explode);

    while (my $row = $csv->getline($io)) {
	debug 'ROW: ', $rownum++;
	next if defined $imptypes and (! exists $imptypes->{$itype});

	my (@fieldlist, %hr);
	# save the special fields to pass to normalize_card_data below, and then remove them from the row.
	for (keys %$card_names_to_pos) {
	    $hr{$_} = $row->[$card_names_to_pos->{$_}];
	}
	# remove the special field values
	for (sort { $b <=> $a } values $card_names_to_pos) {
	    splice @$row, $_, 1;
	}

	# everything that remains in the row is the the field data
	for (my $i = 0; $i <= $#$column_names; $i++) {
	    debug "\tcust field: $column_names->[$i] => $row->[$i]";
	    push @fieldlist, [ $column_names->[$i] => $row->[$i] ];		# retain field order
	}

	# From the card input, place it in the converter-normal format.
	# The card input will have matched fields removed, leaving only unmatched input to be processed later.
	my $normalized = normalize_card_data($itype, \@fieldlist, $hr{'title'}, undef, \$hr{'notes'}, undef);

	# Returns list of 1 or more card/type hashes;possible one input card explodes to multiple output cards
	# common function used by all converters?
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

# Place card data into normalized internal form.
# per-field normalized hash {
#    inkey	=> imported field name
#    value	=> field value after callback processing
#    valueorig	=> original field value
#    outkey	=> exported field name
#    outtype	=> field's output type (may be different than card's output type)
#    keep	=> keep inkey:valueorig pair can be placed in notes
#    to_title	=> append title with a value from the narmalized card
# }
sub normalize_card_data {
    my ($type, $fieldlist, $title, $tags, $notesref, $folder, $postprocess) = @_;
    my %norm_cards = (
	title	=> $title,
	notes	=> $$notesref,
	tags	=> $tags,
	folder	=> $folder,
    );

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
		push @{$norm_cards{'fields'}}, $h;
		splice @$fieldlist, $i, 1;	# delete matched so undetected are pushed to notes below
		last;
	    }
	}
    }

    # map remaining keys to notes
    $norm_cards{'notes'} .= "\n"	if defined $norm_cards{'notes'} and length $norm_cards{'notes'} > 0 and @$fieldlist;
    for (@$fieldlist) {
	next if $_->[1] eq '';
	$norm_cards{'notes'} .= "\n"	if defined $norm_cards{'notes'} and length $norm_cards{'notes'} > 0;
	$norm_cards{'notes'} .= join ': ', @$_;
    }

    return \%norm_cards;
}

sub find_card_type {
    my $row = shift;
    my $otype = 'note';
    my %col_names_to_pos;

    for my $type (keys %card_field_specs) {
	for my $def (@{$card_field_specs{$type}{'fields'}}) {
	    for (my $i = 0; $i < $#$row; $i++) {
		if (defined $def->[2] and $row->[$i] =~ /$def->[2]/ms) {
		    $otype = $type	 		if $def->[1];		# type hint
		    $col_names_to_pos{$def->[0]} = $i		if $def->[0] =~ /^title|notes$/;
		}
	    }
	}
    }

    debug "\t\ttype detected as '$otype'";
    return ($otype, \%col_names_to_pos);
}

1;
