# Safe in Cloud XML export converter
#
# Copyright 2014 Mike Cappella (mike@cappella.us)

package Converters::Safeincloud 1.00;

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

# Icon name to card type mapping, to help find_card_type determine card type.
my %icons;

my %card_field_specs = (
    code =>			{ textname => undef, icon => 'lock', type_out => 'login', fields => [
	[ 'password',		1, qr/^Code$/, ],
    ]},
    creditcard =>		{ textname => undef, icon => 'credit_card', fields => [
	[ 'ccnum',		0, qr/^Number$/, ],
	[ 'cardholder',		1, qr/^Owner$/, ],
	[ '_expiry',		0, qr/^Expires$/, ],
	[ 'cvv',		1, qr/^CVV$/, ],
	[ 'pin',		0, qr/^PIN$/, ],
	[ 'cc_blocking',	1, qr/^Blocking$/, ],
    ]},
    email =>			{ textname => undef, icon => 'email', type_out => 'login', fields => [
	[ 'username',		0, qr/^Email$/, ],
	[ 'password',		0, qr/^Password$/, ],
	[ 'url',		0, qr/^Website$/, ],
    ]},
    passport =>			{ textname => undef,  icon => 'id', fields => [
	[ 'number',		0, qr/^Number$/, ],
	[ 'fullname',		0, qr/^Name$/, ],
	[ '_birthdate',		1, qr/^Birthday$/, ],
	[ '_issue_date',	1, qr/^Issued$/, ],
	[ '_expiry_date',	0, qr/^Expires$/, ],
    ]},
    insurance =>		{ textname => undef,  icon => 'insurance', type_out => 'membership', fields => [
	[ 'membership_no',	0, qr/^Number$/, ],
	[ '_expiry',		0, qr/^Expires$/, ],
	[ 'phone',		0, qr/^Phone$/, ],
    ]},
    login =>			{ textname => undef,  fields => [
	[ 'username',		0, qr/^Login$/, ],
	[ 'password',		0, qr/^Password$/, ],
    ]},
    membership =>		{ textname => undef,  icon => 'membership', fields => [
	[ 'membership_no',	0, qr/^Number$/, ],
	[ 'pin',		0, qr/^Password$/, ],
	[ 'website',		0, qr/^Website$/, ],
	[ 'phone',		0, qr/^Phone$/, ],
    ]},
    note =>                     { textname => undef,  fields => [
    ]},
    webacct =>			{ textname => undef,  icon => 'web_site', type_out => 'login', fields => [
	[ 'username',		0, qr/^Login$/, ],
	[ 'password',		0, qr/^Password$/, ],
	[ 'url',		0, qr/^Website$/, ],
    ]},
);

$DB::single = 1;					# triggers breakpoint when debugging

sub do_init {
    # grab any additional icon numbers from card_field_specs
    for (keys %card_field_specs) {
	$icons{$card_field_specs{$_}{'icon'}} = $_		if exists $card_field_specs{$_}{'icon'};
    }

    return {
	'specs'		=> \%card_field_specs,
	'imptypes'  	=> undef,
	'opts'		=> [],
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

    my %labels;
    my $xp = XML::XPath->new(xml => $_);
    my $dbnodes = $xp->find('//database');
    foreach my $nodes ($dbnodes->get_nodelist) {
	my $labelnodes = $xp->find('label', $nodes);
	# get the label / label id mappings stored as $labels{id} = label;
	$labels{$_->getAttribute('id')} = $_->getAttribute('name')	foreach $labelnodes->get_nodelist;

	my $cardnodes = $xp->find('card', $nodes);
	foreach my $cardnode ($cardnodes->get_nodelist) {
	    my (@fieldlist, @card_tags, $card_note);

	    next if $cardnode->getAttribute('template') eq 'true';
	    my $card_title = $cardnode->getAttribute('title');
	    debug "Card: ", $card_title;

	    my $cardelements = $xp->find('field|label_id|notes', $cardnode);
	    foreach my $cardelement ($cardelements->get_nodelist) {
		if ($cardelement->getName() eq 'field') {
		    push @fieldlist, [ $cardelement->getAttribute('name'), $cardelement->string_value ];
		    debug "\t\t$fieldlist[-1][0]: $fieldlist[-1][1]";
		}
		elsif ($cardelement->getName() eq 'label_id') {
		    push @card_tags, $labels{$cardelement->string_value};
		    debug "\t\tLabel: $card_tags[-1]";
		}
		elsif ($cardelement->getName() eq 'notes') {
		    $card_note  = $cardelement->string_value;
		    debug "\t\tnotes: $card_note";
		}
		else {
		    bail 'Unexpected XPath type encountered: ', $cardelement->getName();
		}
	    }

	    my $icon = $cardnode->getAttribute('symbol');
	    push @fieldlist, [ Color  => $cardnode->getAttribute('color') ];
	    push @card_tags, 'Stared'	if $cardnode->getAttribute('star') eq 'true';

	    my $itype = find_card_type(\@fieldlist, $icon);

	    # skip all types not specifically included in a supplied import types list
	    next if defined $imptypes and (! exists $imptypes->{$itype});

	    # From the card input, place it in the converter-normal format.
	    # The card input will have matched fields removed, leaving only unmatched input to be processed later.
	    my $normalized = normalize_card_data($itype, \@fieldlist, $card_title, \@card_tags, \$card_note);

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
    my $fieldlist = shift;
    my $icon = shift;
    my $type;

    for $type (sort by_test_order keys %card_field_specs) {
	for my $def (@{$card_field_specs{$type}{'fields'}}) {
	    next unless $def->[1] and defined $def->[2];
	    for (@$fieldlist) {
		# type hint
		if ($_->[0] =~ $def->[2]) {
		    debug "\ttype detected as '$type' (key='$_->[0]')";
		    return $type;
		}
	    }
	}
    }

    # Use icon name as a hint at the card type, since it is the only other
    # information available to suggest card type
    if (exists $icons{$icon}) {
	debug "\ttype detected as '$icons{$icon}' icon name = $icon";
	return $icons{$icon};
    }

    $type = grep($_->[0] eq 'Password', @$fieldlist) ? 'login' : 'note';

    debug "\ttype defaulting to '$type'";
    return $type;
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
    my ($type, $fieldlist, $title, $tags, $notesref, $postprocess) = @_;
    my %norm_cards = (
	title	=> $title,
	notes	=> defined $$notesref ? $$notesref : '',
	tags	=> $tags,
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

# sort logins as the last to check
sub by_test_order {
    return  1 if $a eq 'webacct';
    return -1 if $b eq 'webacct';
    return  1 if $a eq 'login';
    return -1 if $b eq 'login';
    $a cmp $b;
}

1;
