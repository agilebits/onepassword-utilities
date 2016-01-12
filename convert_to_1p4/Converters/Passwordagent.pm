# Password Agent XML export converter
#
# Copyright 2015 Mike Cappella (mike@cappella.us)

package Converters::Passwordagent 1.01;

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
	[ 'username',		0, qr/^account$/, ],
	[ 'password',		0, qr/^password$/, ],
	[ 'url',		0, qr/^link$/, ],
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

    my $entrynodes = $xp->findnodes('//entry');
    foreach my $entrynode (@$entrynodes) {
	my (%cmeta, @fieldlist, @groups);

	for (my $node = $entrynode->getParentNode(); my $parent = $node->getParentNode(); $node = $parent) {
	    my $v = $xp->findvalue('name', $node)->value();
	    next if $v eq 'Root';
	    unshift @groups, $v   unless $v eq '';
	}
	$cmeta{'tags'} = join '::', @groups;
	$cmeta{'folder'} = [ @groups ];
	debug 'Group: ', $cmeta{'tags'};

	# type: 0 == Login; 1 == Note
	my $itype = $xp->findvalue('type', $entrynode)->value() == 1 ? 'note' : 'login';

	# skip all types not specifically included in a supplied import types list
	next if defined $imptypes and (! exists $imptypes->{$itype});

	for (qw/name account password link note date_added date_modified date_expire/) {
	    my $val = $xp->findvalue($_, $entrynode)->value();
	    if ($_ eq 'name') {
		$cmeta{'title'} = $val // 'Untitled';
	    }
	    elsif ($_ eq 'note') {
		$cmeta{'notes'} = $val // '';
	    }
	    elsif ($_ eq 'date_modified' and $main::opts{'modified'}) {
		$cmeta{'modified'} = date2epoch($val);
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
#     d-mm-yyyy			keys: date_added, date_modified, date_expire
sub parse_date_string {
    local $_ = $_[0];
    my $when = $_[1] || 0;					# -1 = past only, 0 = assume this century, 1 = future only, 2 = 50-yr moving window

    #s#^(\d/\d{2}/\d{4})$#0$1#;
    if (my $t = Time::Piece->strptime($_, "%m/%d/%Y")) {	# d/mm/yyyy
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
