# KeePassX XML export converter
#
# Copyright 2014 Mike Cappella (mike@cappella.us)

package Converters::Keepassx 1.04;

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
use MIME::Base64;

my %card_field_specs = (
    login =>			{ textname => undef, fields => [
	[ 'url',		1, qr/^url$/, ],
	[ 'username',		1, qr/^username$/, ],
	[ 'password',		1, qr/^password$/, ],
    ]},
    note =>                     { textname => undef, fields => [
    ]},
);

$DB::single = 1;					# triggers breakpoint when debugging

sub do_init {
    return {
	'specs'		=> \%card_field_specs,
	'imptypes'  	=> undef,
    };
}

sub do_import {
    my ($file, $imptypes) = @_;

    $_ = slurp_file($file);
    s!<br/>!\n!g;

    my %Cards;
    my $n = 1;

    my $xp = XML::XPath->new(xml => $_);
    my $groupnodes = $xp->find('//group');
    foreach my $groupnode ($groupnodes->get_nodelist) {
	my (@groups, $tags);
	for (my $node = $groupnode; my $parent = $node->getParentNode(); $node = $parent) {
	    my $v = $xp->findvalue('title', $node)->value();
	    unshift @groups, $v   unless $v eq '';
	}
	$tags = join '::', @groups;
	debug 'Group: ', $tags;
	my $entrynodes = $xp->find('entry', $groupnode);
	foreach my $entrynode ($entrynodes->get_nodelist) {
	    my %cmeta;
	    debug "\tEntry:";
	    my @fieldlist;

	    $cmeta{'title'} = $xp->findvalue('title',   $entrynode)->value();
	    $cmeta{'notes'} = $xp->findvalue('comment', $entrynode)->value();
	    $cmeta{'tags'} = $tags;
	    $cmeta{'folder'} = \@groups;

	    for (qw/username password url lastaccess lastmod creation expire/) {
		my $val = $xp->findvalue($_, $entrynode)->value();
		next if $val eq '';
		if ($_ eq 'lastmod' and not $main::opts{'notimestamps'}) {
		    $cmeta{'modified'} = date2epoch($val);
		}
		elsif ($_ eq 'creation' and not $main::opts{'notimestamps'}) {
		    $cmeta{'created'} = date2epoch($val);
		}
		else  {
		    push @fieldlist, [ $_ => $val ];		# retain field order
		}
		debug "\t\t$_: ", $val;
	    }

	    my $itype = find_card_type(\@fieldlist);

	    # skip all types not specifically included in a supplied import types list
	    next if defined $imptypes and (! exists $imptypes->{$itype});

	    # handle creation of attachment files from encoded / compressed string
	    if (my $bin = $xp->findvalue('bin', $entrynode)->value()) {
		my $bindesc = $xp->findvalue('bindesc', $entrynode)->value();

		create_attachment(\decode_base64($bin), undef, $bindesc, $cmeta{'title'});
	    }

	    my $normalized = normalize_card_data(\%card_field_specs, $itype, \@fieldlist, \%cmeta);
	    my $cardlist   = explode_normalized($itype, $normalized);

	    for (keys %$cardlist) {
		print_record($cardlist->{$_});
		push @{$Cards{$_}}, $cardlist->{$_};
	    }
	    $n++;
	}
    }

    summarize_import('item', $n - 1);
    return \%Cards;
}

sub do_export {
    add_custom_fields(\%card_field_specs);
    create_pif_file(@_);
}

sub find_card_type {
    my $type = grep($_->[0] =~ /^url|username|password$/, @{$_[0]}) ? 'login' : 'note';
    debug "type detected as '$type'";
    return $type;
}

# Date converters
# lastmod field:	 yyyy-mm-ddThh:mm:ss
sub parse_date_string {
    local $_ = $_[0];
    my $when = $_[1] || 0;					# -1 = past only, 0 = assume this century, 1 = future only, 2 = 50-yr moving window

    return undef if $_ eq 'Never';

    if (my $t = Time::Piece->strptime($_, "%Y-%m-%dT%H:%M:%S")) {	# KeePassX dates are in standard UTC string format, no TZ
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
