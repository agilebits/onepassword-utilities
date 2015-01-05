# KeePass 2 XML export converter
#
# Copyright 2014 Mike Cappella (mike@cappella.us)

package Converters::Keepass2 1.01;

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
use XML::Parser;
use HTML::Entities;

my %card_field_specs = (
    login =>			{ textname => undef, fields => [
	[ 'url',		1, qr/^URL$/, ],
	[ 'username',		1, qr/^UserName$/, ],
	[ 'password',		1, qr/^Password$/, ],
    ]},
    note =>                     { textname => undef, fields => [
    ]},
);

$DB::single = 1;					# triggers breakpoint when debugging

my %fields = ();
my @paths;		# xml paths
my @group;		# current group hierarchy
my $currentkey;		# the current key name being parsed
my $collecting = 1;	# is the parser currently collecting data?
my $xmldbg = 0;

my @gCards;

sub do_init {
    return {
	'specs'		=> \%card_field_specs,
	'imptypes'  	=> undef,
	'opts'		=> [],
    };
}

sub do_import {
    my ($file, $imptypes) = @_;

    my $parser = new XML::Parser(ErrorContext => 2);

    $parser->setHandlers(
	Char =>     \&char_handler,
	Start =>    \&start_handler,
	End =>      \&end_handler,
	Final =>    \&final_handler,
	Default =>  \&default_handler
    );

    $parser->parsefile($file);

    @gCards or
	bail "No entries detected in the export file\n";

    my %Cards;
    my $n = 1;
    my ($npre_explode, $npost_explode);
    for my $c (@gCards) {
	my ($card_title, $card_tags, $card_notes) = ($c->{'Title'}, $c->{'Tags'}, $c->{'Notes'});
	delete @{$c}{qw/Title Tags Notes/};

	my $itype = find_card_type($c);

	# skip all types not specifically included in a supplied import types list
	next if defined $imptypes and (! exists $imptypes->{$itype});

	# From the card input, place it in the converter-normal format.
	# The card input will have matched fields removed, leaving only unmatched input to be processed later.
	my $normalized = normalize_card_data($itype, $c, $card_title, $card_tags, \$card_notes);

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

    $n--;
    verbose "Imported $n card", pluralize($n) ,
	$npre_explode ? " ($npre_explode card" . pluralize($npre_explode) .  " expanded to $npost_explode cards)" : "";
    return \%Cards;
}

sub do_export {
    create_pif_file(@_);
}

sub find_card_type {
    my $c = shift;
    my $type;

    for $type (sort by_test_order keys %card_field_specs) {
	for my $def (@{$card_field_specs{$type}{'fields'}}) {
	    for my $key (keys %$c) {
		# type hint
		if ($def->[1] and $key =~ $def->[2]) {
		    debug "type detected as '$type' (key='$key')";
		    return $type;
		}
	    }
	}
    }

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
	notes	=> defined $$notesref ? $$notesref : '',
	tags	=> $tags,
    );

    for my $def (@{$card_field_specs{$type}{'fields'}}) {
	my $h = {};
	for (keys %$carddata) {
	    my ($inkey, $value) = ($_, $carddata->{$_});
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
		delete $carddata->{$_};		# delete matched so undetected are pushed to notes below
	    }
	}
    }

    # map remaining keys to notes
    $norm_cards{'notes'} .= "\n"	if length $norm_cards{'notes'} > 0 and keys %$carddata;
    for (keys %$carddata) {
	next if $carddata->{$_} eq '';
	$norm_cards{'notes'} .= "\n"	if length $norm_cards{'notes'} > 0;
	$norm_cards{'notes'} .= join ': ', $_, $carddata->{$_};
    }

    return \%norm_cards;
}

# sort logins as the last to check
sub by_test_order {
    return  1 if $a eq 'login';
    return -1 if $b eq 'login';
    $a cmp $b;
}

# handlers below


sub start_handler {
    my ($p, $el) = @_;

    push @paths, my $path = join('::', $p->context, $el);
    $xmldbg && debug 'START path: ', $path;

    if (defined $p->current_element) {

	# Ignore the data in the card's History group
	if ($path =~ /::Group::Entry::History$/) {
	    $xmldbg && debug "START HISTORY - collecting disabled";
	    $collecting = 0;
	    return;
	}

	return if not $collecting;
	if ($path =~ /::Group$/) {
	    $xmldbg && debug "=== START GROUP";
	    push @group, '';
	}
	elsif ($path =~ /::Group::Entry$/) {
	    $xmldbg && debug "START ENTRY";
	    %fields = ();
	}
	elsif ($path =~ /::Group::Entry::String::Key$/) {
	    $xmldbg && debug "START KEY";
	}
    }
}

sub char_handler {
    my ($p, $data) = @_;

    my $path = $paths[-1];

    #if ($data eq '&' or $data eq '<' or $data eq '>') { $data = encode_entities($data); }	# only required when output is XML
    # the expat parser returns entities as single characters
    #else					      { $data = decode_entities($data); }

    return if not $collecting;

    if ($path =~ /::Group::Name$/) {
	$group[-1] .= $data;
	debug "\tGROUP name: ==> '$group[-1]'";
    }
    elsif ($path =~ /::Group::Entry::String::Key$/) {
	debug " **** current key: '$data'";
	$currentkey = $data;
    }
    elsif ($path =~ /::Group::Entry::String::Value$/) {
	debug " **** Field: $currentkey ==> '$data'";
	$fields{$currentkey} .= $data;
    }
    else {
	$xmldbg && debug "\t\t...ignoring char data: ", $data =~ /^\s+/ms ? 'WHITESPACE' : $data;
    }
}

sub end_handler {
    my ($p, $el) = @_;

    my $path = pop @paths;
    $xmldbg && debug '__END path: ', $path;

    if ($path =~ /::Group::Entry::History$/) {
	$xmldbg && debug "END HISTORY - collecting enabled";
	$collecting = 1;
	return;
    }

    return if not $collecting;

    if ($path =~ /::Group$/) {
	my $grp = pop @group;
	$xmldbg && debug "========= END GROUP: ", $grp;
    }
    elsif ($path =~ /::Group::Entry$/) {
	$xmldbg && debug "END ENTRY: ... output values\n";
	debug "END ENTRY: ... output values\n";
	$fields{'Tags'} = join '::', @group[1..$#group];
	push @gCards, { %fields };
	#print Dumper \%fields;

	return;
    }
}

sub final_handler {
    #print Dumper(\%fields);
}

sub default_handler { }

1;
