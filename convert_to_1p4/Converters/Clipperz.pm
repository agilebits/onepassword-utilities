# Clipperz JSON export converter
#
# Copyright 2014 Mike Cappella (mike@cappella.us)

package Converters::Clipperz 1.00;

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
use JSON::PP;

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
	'opts'		=> [],
    };
}

sub do_import {
    my ($file, $imptypes) = @_;
    my %Cards;

    my $decoded;
    {
        local $/;
        open my $fh, '<', $file or bail "Unable to open file: $file\n$!";
        $_   = <$fh>;
	s/^\x{ef}\x{bb}\x{bf}//	if $^O eq 'MSWin32';
        $decoded = decode_json $_;
        close $fh;
    }

    my $n = 1;
    my ($npre_explode, $npost_explode);
    for (@$decoded) {
	my $itype = find_card_type($_->{'currentVersion'}{'fields'});

	# skip all types not specifically included in a supplied import types list
	next if defined $imptypes and (! exists $imptypes->{$itype});

	# From the card input, place it in the converter-normal format.
	# The card input will have matched fields removed, leaving only unmatched input to be processed later.
	my $normalized = normalize_card_data($itype, $_, $_->{'label'}, undef, \$_->{'data'}{'notes'});

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
    my $f = shift;

    for my $type (sort by_test_order keys %card_field_specs) {
	for my $def (@{$card_field_specs{$type}{'fields'}}) {
	    for (keys %$f) {
		# type hint
		if ($def->[1] and $f->{$_}{'label'} =~ $def->[2]) {
		    debug "type detected as '$type' (key='$f->{$_}{'label'}')";
		    return $type;
		}
	    }
	}
    }

    debug "\t\ttype defaulting to 'note'";
    return 'note';
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
    my ($type, $carddata, $title, $tags, $notesref, $postprocess) = @_;
    my %norm_cards = (
	title	=> $title,
	notes	=> $$notesref,
	tags	=> $tags,
    );
    my $f = $carddata->{'currentVersion'}{'fields'};

    for my $def (@{$card_field_specs{$type}{'fields'}}) {
	my $h = {};
	for (keys %$f) {
	    my ($inkey, $value) = ($f->{$_}{'label'}, $f->{$_}{'value'});
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
		delete $f->{$_};	# delete matched so undetected are pushed to notes below
	    }
	}
    }

    # map remaining keys to notes
    $norm_cards{'notes'} .= "\n"	if length $norm_cards{'notes'} > 0 and keys %$f;
    for (keys %$f) {
	next if $f->{$_}{'value'} eq '';
	$norm_cards{'notes'} .= "\n"	if length $norm_cards{'notes'} > 0;
	$norm_cards{'notes'} .= join ': ', $f->{$_}{'label'}, $f->{$_}{'value'};
    }

    return \%norm_cards;
}

# sort logins as the last to check
sub by_test_order {
    return  1 if $a eq 'login';
    return -1 if $b eq 'login';
    $a cmp $b;
}

1;
