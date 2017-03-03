# Password Safe XML export converter
#
# Copyright 2016 Mike Cappella (mike@cappella.us)

package Converters::Passwordsafe 1.00;

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

use XML::XPath;
use XML::XPath::XMLParser;
use Time::Local qw(timelocal);
use Time::Piece;

my %card_field_specs = (
    login =>                 { textname => undef, type_out => 'login', fields => [
	[ 'username',		0, qr/^username$/, ],
	[ 'password',		0, qr/^password$/, ],
	[ 'url',		0, qr/^url$/, ],
	[ '_email',		0, qr/^email$/, ],
    ]},
    note =>                     { textname => '', fields => [
    ]},
);

$DB::single = 1;					# triggers breakpoint when debugging

my %groupid_map;

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
    my %Cards;

    $_ = slurp_file($file);

    my $n = 1;

    my $xp = XML::XPath->new(xml => $_);

    my $root = $xp->find('/passwordsafe');
    my $delimiter = $root->[0]->getAttribute('delimiter');
    my $dbversion = $root->[0]->getAttribute('WhatSaved');

    my $entrynodes = $xp->findnodes('//entry', $root);
    foreach my $entrynode (@$entrynodes) {
	my (%cmeta, @fieldlist, @groups);

	my $itype = 'login';

	# skip all types not specifically included in a supplied import types list
	next if defined $imptypes and (! exists $imptypes->{$itype});

	for (qw/group title username password url notes email rmtimex pmtimex ctimex pwhistory/) {
	    my $val = $xp->findvalue($_, $entrynode)->value();
	    if ($_ eq 'title') {
		$cmeta{'title'} = $val // 'Untitled';
	    }
	    elsif ($_ eq 'notes') {
		$cmeta{'notes'} = $val // '';
		$cmeta{'notes'} =~ s/$delimiter/\n/g;
	    }
	    elsif ($_ eq 'group') {
		$cmeta{'tags'} = $val;
		$cmeta{'folder'} = [ $val ];
		debug 'Group: ', $cmeta{'tags'};
	    }
	    elsif ($_ =~ /^(?:rm|pm|c)timex$/ and $main::opts{'modified'}) {
		# rmtimex: last modification time for non-password item
		# pmtimex: last modification time for password
		# ctime:   record's creation time
		# use the most recent of the three to set the modified time
		my $epochtime = date2epoch($val);
		if (! defined $cmeta{'modified'} or $epochtime > $cmeta{'modified'}) {
		    $cmeta{'modified'} = $epochtime
		}
	    }
	    elsif ($_ eq 'pwhistory') {
		my $historynodes = $xp->find('.//history_entry', $entrynode);
		foreach my $historynode (@$historynodes) {
		    my $pass = $xp->findvalue('oldpassword', $historynode)->value();
		    my $time = $xp->findvalue('changedx',    $historynode)->value();
		    push @{$cmeta{'pwhistory'}}, [ $pass, date2epoch($time) ];
		}
	    }
	    else {
		push @fieldlist, [ $_ => $val ];
	    }
	    debug "\t    field: $_ = ", $val // '';
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

# Date converters
#     yyyy-MM-DDThh:mm:ss
sub parse_date_string {
    local $_ = $_[0];
    my $when = $_[1] || 0;					# -1 = past only, 0 = assume this century, 1 = future only, 2 = 50-yr moving window

    if (my $t = Time::Piece->strptime($_, "%Y-%m-%dT%H:%M:%S")) {	# yyyy-MM-DDThh:mm:ss
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
