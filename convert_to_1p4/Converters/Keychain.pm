# OS X Keychain text export converter
#
# Copyright 2014 Mike Cappella (mike@cappella.us)

package Converters::Keychain 1.03;

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

use Encode;
use Time::Local qw(timelocal);
use Time::Piece;

my $max_password_length = 50;

my %card_field_specs = (
    login =>			{ textname => undef, fields => [
	[ 'username',		0, qr/^username$/ ],
	[ 'password',		0, qr/^password$/ ],
	[ 'url',		0, qr/^url$/ ],
    ]},
    note =>			{ textname => undef, fields => [
    ]},
);

my (%entry, $itype);

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
			     $_[0] =~ /^Safari Session State Key$/ or
			     $_[0] =~ /^Call History User Data Key$/}, action => 'SKIP',
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
		{ c => sub { $_[0] =~ s/0x00000000 // } },
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
    # desc must come before DATA so that 'secure note' type can be used as a condition in DATA below
    desc => [
		{ c => sub { $_[0] =~ s/^"(.*)"$/$1/; $itype = 'note' if $_[0] eq 'secure note'; $_[0] } },
    ],
    DATA => [
		# secure note data, early terminates rule list testing
		{ c => sub { $itype eq 'note' and $_[0] =~ s/^.*<key>NOTE<\/key>\\012\\011<string>(.+?)<\/string>.*$/$1/ }, action => 'BREAK',
		    msg => sub { debug "\t\tskipping non-password record: $entry{'CLASS'}: ", $entry{'svce'} // $entry{'srvr'} } },

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
	'opts'		=> [ [ q{-m or --modified           # set item's last modified date },
			       'modified|m' ],
			   ],
    };
}

sub do_import {
    my ($file, $imptypes) = @_;
    my (%Cards, %dup_check);

    my $contents = slurp_file($file, 'utf8');

    my ($n, $examined, $skipped, $duplicates) = (1, 0, 0, 0);

KEYCHAIN_ENTRY:
    while ($contents) {
	if ($contents =~ s/\Akeychain: (.*?)\n+(?=$|^keychain: ")//ms) {
	    local $_ = $1; my $orig = $1;
	    $itype = 'login';

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
RULE:
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
			    elsif ($rule->{'action'} eq 'BREAK') {
				debug "\t    breaking out of rule chain";
				next RULE;
			    }
			}
		    }

		    $rulenum++;
		}
	    }

	    for (keys %entry) {
		debug sprintf "\t    %-12s : %s", $_, $entry{$_}	if exists $entry{$_};
	    }

	    #my $itype = find_card_type(\%entry);

	    my (%h, @fieldlist, %cmeta);
	    if ($itype eq 'login') {
		$h{'password'}	= $entry{'DATA'};
		$h{'username'}	= $entry{'acct'}						if exists $entry{'acct'};
		if (exists $entry{'srvr'}) {
		    $h{'url'}	= $entry{'srvr'};
		    $h{'url'}	= $entry{'ptcl'} . '://' . $h{'url'}				if $entry{'ptcl'} ne '';
		    $h{'url'}  .= $entry{'path'}						if $entry{'path'} ne '';
		}
	    }
	    elsif ($itype eq 'note') {
		# convert ascii string DATA, which contains \### octal escapes, into UTF-8
		my $octets = encode("ascii", $entry{'DATA'});
		$octets =~ s/\\(\d{3})/"qq|\\$1|"/eeg;
		$cmeta{'notes'} = decode("UTF-8", $octets);
	    }
	    else {
		die "Unexpected itype: $itype";
	    }

	    # will be added to notes
	    $h{'protocol'}	= $entry{'ptcl'}					if exists $entry{'ptcl'} and $entry{'ptcl'} =~ /^afp|smb$/;
	    $h{'created'}	= $entry{'cdat'}					if exists $entry{'cdat'};
	    if (exists $entry{'mdat'}) {
		if ($main::opts{'modified'}) {
		    $cmeta{'modified'} = date2epoch($entry{'mdat'});
		}
		else {
		    $h{'modified'}	= $entry{'mdat'};
		}
	    }

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
	    $cmeta{'title'} = $sv;

	    push @fieldlist, [ $_ => $h{$_} ]	for keys %h;

	    my $normalized = normalize_card_data(\%card_field_specs, $itype, \@fieldlist, \%cmeta);
	    my $cardlist   = explode_normalized($itype, $normalized);

	    for (keys %$cardlist) {
		print_record($cardlist->{$_});
		push @{$Cards{$_}}, $cardlist->{$_};
	    }
	    $n++;
	}
	else {
	    bail "Keychain parse failed, after entry $examined; unexpected: ", substr $contents, 0, 2000;
	}
    }

    verbose "Examined $examined ", pluralize('item', $examined);
    verbose "Skipped $skipped non-login ", pluralize('item', $skipped);
    verbose "Skipped $duplicates duplicate ", pluralize('item', $duplicates);

    summarize_import('item', $n - 1);
    return \%Cards;
}


sub do_export {
    add_custom_fields(\%card_field_specs);
    create_pif_file(@_);
}

sub find_card_type {
    my $eref = shift;

    my $type = (exists $eref->{'desc'} and $eref->{'desc'} eq 'secure note') ? 'note' : 'login';
    debug "\t\ttype set to '$type'";
    return $type;
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

# Date converters
# LastModificationTime field:	 yyyy-mm-dd hh:mm:ss
sub parse_date_string {
    local $_ = $_[0];
    my $when = $_[1] || 0;					# -1 = past only, 0 = assume this century, 1 = future only, 2 = 50-yr moving window

    if (my $t = Time::Piece->strptime($_, "%Y-%m-%d %H:%M:%S")) {
	return $t;
    }

    return undef;
}

sub date2epoch {
    my $t = parse_date_string @_;
    return undef if not defined $t;
    return defined $t->year ? 0 + timelocal($t->sec, $t->minute, $t->hour, $t->mday, $t->mon - 1, $t->year): $_[0];
}

1;
