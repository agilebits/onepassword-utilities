# OS X Keychain text export converter
#
# Copyright 2014 Mike Cappella (mike@cappella.us)

package Converters::Keychain 1.00;

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
use Utils::Utils qw(verbose debug bail pluralize myjoin unfold_and_chop print_record);

my $max_password_length = 50;

my %card_field_specs = (
    login =>                    { textname => undef, fields => [
	[ 'username',		0, qr/^username$/ ],
	[ 'password',		0, qr/^password$/ ],
	[ 'url',		0, qr/^url$/ ],
    ]},
);

my %entry;

# The following table drives transformations or actions for an entry's attributes, or the class or
# data section (all are collected into a single hash).  Each ruleset is evaluated in order, as are
# each of the rules within a set.  The key 'c' points to a code reference, which is passed the data
# value for the given type being tested.  It can transform the value in place, or simply test it and
# return a string (for debug output).  When the key 'action' is set to 'SKIP', the entry being tested
# will be rejected from consideration for export when the 'c' code reference returns a TRUE value.
# And in that case, the code ref pointed to by 'msg' will be run to produce debug output, used to
# indicate the reason for the rejection.
#
# The table facilitates adding new transformations and rejection rules, as necessary,
# through empirical discover based on user feedback.
my @rules = (
    CLASS => [
		{ c => sub { $_[0] !~ /^inet|genp$/ }, action => 'SKIP', msg => sub { debug "\tskipping non-password class: ", $_[0] } },
    ],
    svce => [
		{ c => sub { $_[0] =~ s/^0x([A-F\d]+)\s+".*"$/pack "H*", $1/ge } },
		{ c => sub { $_[0] =~ s/^"(.*)"$/$1/ } },
		{ c => sub { $_[0] =~ /^Apple Persistent State Encryption$/ or 
			     $_[0] =~ /^Preview Signature Privacy$/ or
			     $_[0] =~ /^Safari Session State Key$/ }, action => 'SKIP',
		    msg => sub { debug "\t\tskipping non-password record: $entry{'CLASS'}: ", $_[0] } },
    ],
    srvr => [
		{ c => sub { $_[0] =~ s/^"(.*)"$/$1/ } },
		{ c => sub { $_[0] =~ s/\.((?:_afpovertcp|_smb)\._tcp\.)?local// } },
    ],
    path => [
		{ c => sub { $_[0] =~ s/^"(.*)"$/$1/ } },
		{ c => sub { $_[0] =~ s/^<NULL>$// } },
    ],
    ptcl => [
		{ c => sub { $_[0] =~ s/htps/https/ } },
		{ c => sub { $_[0] =~ s/^"(\S+)\s*"$/$1/ } },
    ],
    acct => [
		{ c => sub { $_[0] =~ s/^0x([A-F\d]+)\s+".*"$/pack "H*", $1/ge } },
		{ c => sub { $_[0] =~ s/^"(.*)"$/$1/ } },
    ],
    mdat => [
		{ c => sub { $_[0] =~ s/^0x\S+\s+"(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z.+"$/$1-$2-$3 $4:$5:$6/g } },
    ],
    cdat => [
		{ c => sub { $_[0] =~ s/^0x\S+\s+"(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z.+"$/$1-$2-$3 $4:$5:$6/g } },
    ],
    DATA => [
		{ c => sub { $_[0] !~ s/^"(.+)"$/$1/ }, action => 'SKIP',
		    msg => sub { debug "\t\tskipping non-password record: $entry{'CLASS'}: ", $entry{'svce'} // $entry{'srvr'} } },
		{ c => sub { $_[0] =~ /^[A-Z\d]{8}-[A-Z\d]{4}-[A-Z\d]{4}-[A-Z\d]{4}-[A-Z\d]{12}$/ }, action => 'SKIP',
		    msg => sub { debug "\t\tskipping non-password record: $entry{'CLASS'}: ", $entry{'svce'} // $entry{'srvr'} } },
		{ c => sub { length $_[0] > $max_password_length }, action => 'SKIP',
		    msg => sub { debug "\t\tskipping record with improbably long password: $entry{'CLASS'}: ", $entry{'svce'} // $entry{'srvr'} } },
		{ c => sub { join '', "\trecord: class = $entry{'CLASS'}: ", $entry{'svce'} // $entry{'srvr'} } },	# debug output only
    ],
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
    my (%Cards, %dup_check);
    my $contents = $_;;

    {
	local $/;
	open my $fh, '<:encoding(utf8)', $file or bail "Unable to open file: $file\n$!";
	$contents = <$fh>;
	close $fh;
    }

    my ($n, $examined, $skipped, $duplicates) = (1, 0, 0, 0);
    my ($npre_explode, $npost_explode);

KEYCHAIN_ENTRY:
    while ($contents) {
	if ($contents =~ s/\Akeychain: (.*?)\n+(?=$|^keychain: ")//ms) {
	    local $_ = $1; my $orig = $1;

	    $examined++;
	    debug "Entry ", $examined;

	    s/\A"(.*?)"\n^(.+)/$2/ms;
	    my $keychain = $1;
	    #debug 'Keychain: ', $keychain;

	    s/\Aclass: "?(.*?)"? ?\n//ms;
	    my $class = $1;

	    # attributes
	    s/\Aattributes:\n(.*?)(?=^data:)//ms;
	    %entry = map { clean_attr_name(split /=/, $_) } split /\n\s*/, $1 =~ s/^\s+//r;

	    $entry{'CLASS'} = $class;

	    # data
	    s/\Adata:\n(.+)\z//ms;
	    $entry{'DATA'}  = defined $1 ? $1 : '';

	    # run the rules in the rule set above
	    # for each set of rules for an entry key...
	    for (my $i = 0;  $i < @rules; $i += 2) {
		my ($key, $ruleset) = ($rules[$i], $rules[$i + 1]);

		debug "  considering rules for ", $key;
		next if not exists $entry{$key};

		# run the entry key's rules...
		my $rulenum = 1;
		for my $rule (@$ruleset) {
		    debug "\t    rule $rulenum: called with ", unfold_and_chop $entry{$key};

		    my $ret = ($rule->{'c'})->($entry{$key});

		    debug "\t    rule $rulenum: returns ", $ret || 0, '   ', unfold_and_chop $entry{$key};

		    if (exists $rule->{'action'}) {
			if ($ret) {
			    if ($rule->{'action'} eq 'SKIP') {
				$skipped++;
				($rule->{'msg'})->($entry{$key})		if exists $rule->{'msg'};
				next KEYCHAIN_ENTRY;
			    }
			}
		    }

		    $rulenum++;
		}
	    }

	    for (keys %entry) {
		debug sprintf "\t    %-12s : %s", $_, $entry{$_}	if exists $entry{$_};
	    }

	    my %h;
	    $h{'password'}	= $entry{'DATA'};
	    $h{'username'}	= $entry{'acct'}					if exists $entry{'acct'};
	    $h{'url'}		= $entry{'ptcl'} . '://' . $entry{'srvr'} . $entry{'path'}	if exists $entry{'srvr'};

	    # will be added to notes
	    $h{'modified'}	= $entry{'mdate'}					if exists $entry{'mdate'};
	    $h{'created'}	= $entry{'cdate'}					if exists $entry{'cdate'};
	    $h{'protocol'}	= $entry{'ptcl'}					if exists $entry{'ptcl'} and $entry{'ptcl'} =~ /^afp|smb$/;

	    for (keys %h) {
		debug sprintf "\t    %-12s : %s", $_, $h{$_}				if exists $h{$_};
	    }
 
	    # don't set/use $sv before $entry{''svce'} is removed of _afp*, _smb*, and .local, since it defeats dup detection
	    my $sv = $entry{'svce'} // $entry{'srvr'};

	    my $s = join ':::', 'sv', $sv,
		map { exists $h{$_} ? "$_ => $h{$_}" : 'URL => none' } qw/url username password/;

	    if (exists $dup_check{$s}) {
		debug "  *skipping duplicate entry for ", $sv;
		$duplicates++;
		next
	    }
	    $dup_check{$s}++;

	    my $itype = find_card_type(\%h);

	    # From the card input, place it in the converter-normal format.
	    # The card input will have matched fields removed, leaving only unmatched input to be processed later.
	    my $normalized = normalize_card_data($itype, \%h, $sv, undef, \undef);

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
	else {
	    bail "Keychain parse failed, after entry $examined; unexpected: ", substr $contents, 0, 2000;
	}
    }

    $n--;
    verbose "Examined $examined record", pluralize($examined);
    verbose "Skipped $skipped non-login record", pluralize($skipped);
    verbose "Skipped $duplicates duplicate record", pluralize($duplicates);

    verbose "Imported $n record", pluralize($n) ,
	$npre_explode ? " ($npre_explode card" . pluralize($npre_explode) .  " expanded to $npost_explode cards)" : "";
    return \%Cards;
}

sub do_export {
    create_pif_file(@_);
}

sub find_card_type {
    debug "\t\ttype defaulting to 'login'";
    return 'login';
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
    my ($type, $carddata, $title, $tags, $saved_notes, $postprocess) = @_;
    my %norm_cards = (
	title	=> $title,
	tags	=> $tags,
    );

    for my $def (@{$card_field_specs{$type}{'fields'}}) {
	my $h = {};
	for my $key (keys %$carddata) {
	    if ($key =~ /$def->[2]/) {
		next if not defined $carddata->{$key} or $carddata->{$key} eq '';
		my ($inkey, $value) = ($key, $carddata->{$key});
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
		delete $carddata->{$key};
	    }
	}
    }

    for my $key (keys %$carddata) {
	$norm_cards{'notes'} .= "\n"	if defined $norm_cards{'notes'};
	$norm_cards{'notes'} .= join ': ', $key, $carddata->{$key};
    }

    return \%norm_cards;
}

# sort logins as the last to check
sub by_test_order {
    return  1 if $a eq 'login';
    return -1 if $b eq 'login';
    $a cmp $b;
}

sub clean_attr_name {
    return ($_[0] =~ /"?([^<"]+)"?<\w+>$/, $_[1]);
}

1;
