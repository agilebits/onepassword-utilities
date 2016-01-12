# Keeper HTML export converter
#
# Copyright 2015 Mike Cappella (mike@cappella.us)

package Converters::Keeper 1.00;

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

    my $html = slurp_file($file, 'UTF-8');

    my $n = 1;
    my @labels;
    while ($html =~ s/^.*?<tr>(.*?)<\/tr>//ims) {
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
	    $cmeta{'tags'} = $folder;
	    $cmeta{'folder'} = [ $folder ];
	}
	$cmeta{'title'} = shift(@values) || 'Untitled';
	my $note = splice(@values, 3, 1);
	$cmeta{'notes'} = $note	if $note ne '';

	# populate @fieldlist
	for (my $i = 0; $i < @labels; $i++) {
	    next if $values[$i] eq '';
	    push @fieldlist, [ $labels[$i] => $values[$i] ];
	}

	my $itype = find_card_type(\@fieldlist);

	# skip all types not specifically included in a supplied import types list
	next if defined $imptypes and (! exists $imptypes->{$itype});

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
