# Clipperz JSON export converter
#
# Copyright 2014 Mike Cappella (mike@cappella.us)

package Converters::Clipperz 1.02;

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
use HTML::Entities;

my %card_field_specs = (
    bankacct =>                 { textname => undef, fields => [
	[ 'bankName',		0, qr/^Bank$/, 				{ to_title => 'value' } ],
	[ 'accountNo',		0, qr/^Account number$/, ],
	[ 'url',		1, qr/^Bank website$/,			{ type_out => 'login' } ],
	[ 'username',		1, qr/^Online banking ID$/,		{ type_out => 'login' } ],
	[ 'password',		1, qr/^Online banking password$/,	{ type_out => 'login' } ],
    ]},
    login =>                    { textname => undef, fields => [
        [ 'url',		1, qr/^Web address$/, ],
        [ 'username',		1, qr/^Username or email$/, ],
        [ 'password',		1, qr/^Password$/, ],
    ]},
    creditcard =>               { textname => undef, fields => [
        [ 'type',		1, qr/^Type /, 				{ to_title => 'value' } ],
        [ 'ccnum',		0, qr/^Number$/, ],
        [ 'cardholder',		1, qr/^Owner name$/, ],
        [ '_expires',		1, qr/^Expiry date$/, ],
        [ 'cvv',		1, qr/^CVV2$/, ],
        [ 'pin',		0, qr/^PIN$/, ],
        [ 'url',		1, qr/^Card website$/, 			{ type_out => 'login' }],
        [ 'username',		0, qr/^Username$/, 			{ type_out => 'login' }],
        [ 'password',		0, qr/^Password$/, 			{ type_out => 'login' }],
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
    if (/<textarea>(.+?)<\/textarea>/) {
	$_ = decode_entities $1;
    }

    s/^\x{ef}\x{bb}\x{bf}//	if $^O eq 'MSWin32';		# remove BOM
    my $decoded = decode_json $_;

    my $n = 1;
    for my $entry (@$decoded) {
	my (%cmeta, @fieldlist);
	my $itype = find_card_type($entry->{'currentVersion'}{'fields'});

	# skip all types not specifically included in a supplied import types list
	next if defined $imptypes and (! exists $imptypes->{$itype});

	$cmeta{'title'} = $entry->{'label'};
	$cmeta{'notes'} = $entry->{'data'}{'notes'};

	for my $key (keys %{$entry->{'currentVersion'}{'fields'}}) {
	    my ($label, $value) = ( @{$entry->{'currentVersion'}{'fields'}{$key}}{'label','value'} );
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
		if ($cfs->[CFS_TYPEHINT] and $f->{$_}{'label'} =~ $cfs->[CFS_MATCHSTR]) {
		    debug "type detected as '$type' (key='$f->{$_}{'label'}')";
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
