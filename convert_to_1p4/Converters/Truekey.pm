# True Key JSON export converter
#
# Copyright 2016 Mike Cappella (mike@cappella.us)

package Converters::Truekey 1.00;

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

use JSON::PP;

my %card_field_specs = (
    login =>                    { textname => undef, fields => [
        [ 'url',		1, qr/^url$/, ],
        [ 'username',		1, qr/^login$/, ],
        [ 'password',		1, qr/^password$/, ],
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

    $_ = slurp_file($file);

    my $decoded = decode_json $_;

    exists $decoded->{'logins'} or
	bail "Export JSON file - unexpected format";

    my $n = 1;
    for my $entry (@{$decoded->{'logins'}}) {
	my (%cmeta, @fieldlist);
	my $itype = find_card_type($entry);

	# skip all types not specifically included in a supplied import types list
	next if defined $imptypes and (! exists $imptypes->{$itype});

	$cmeta{'title'} = $entry->{'name'};
	$cmeta{'notes'} = $entry->{'memo'};
	if ($entry->{'favorite'} eq 'true') {
	    $cmeta{'tags'} = 'Favorite';
	    $cmeta{'folder'}  = [ 'Favorite' ];
	}

	for my $label (qw/login password url/) {
	    my $value = $entry->{$label};
	    next if not defined $value or $value eq '';
	    push @fieldlist, [ $label => $value ];		# @fieldlist maintains card's field order
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

sub find_card_type {
    my $f = shift;

    for my $type (sort by_test_order keys %card_field_specs) {
	for my $cfs (@{$card_field_specs{$type}{'fields'}}) {
	    for (keys %$f) {
		if ($cfs->[CFS_TYPEHINT] and $_ =~ $cfs->[CFS_MATCHSTR]) {
		    debug "type detected as '$type' (key='$_')";
		    return $type;
		}
	    }
	}
    }

    debug "\t\ttype defaulting to 'note'";
    return 'note';
}

# sort logins as the last to check
sub by_test_order {
    return  1 if $a eq 'login';
    return -1 if $b eq 'login';
    $a cmp $b;
}

1;
