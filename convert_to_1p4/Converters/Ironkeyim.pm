# IronKey Identity Manager XML export converter
#
# Copyright 2015 Mike Cappella (mike@cappella.us)

package Converters::Ironkeyim 1.01;

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

# encrypted file
my %card_field_specs = (
    login =>                    { textname => undef, type_out => 'login', fields => [
	[ 'username',		0, qr/^Name$/, ],
	[ 'password',		0, qr/^Password$/, ],
	[ 'url',		0, qr/^URL$/, ],
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

    my $groupnodes = $xp->findnodes('//Groups//Group');
    foreach my $groupnode (@$groupnodes) {
	$groupid_map{$groupnode->getAttribute('ID')} = {
	    name   => $groupnode->getAttribute('Name'),
	    parent => $groupnode->getAttribute('ParentID') 
	};
    }

    my $accountnodes = $xp->findnodes('//Accounts//Account');
    foreach my $accountnode (@$accountnodes) {
	my (@card_group, $card_modified);
	my $itype = 'login';

	my $nlogins = $accountnode->findvalue("count(Logins/*)");

	if (my $loginnodes = $xp->findnodes('Logins/*', $accountnode)) {
	    my $loginindex = 1;;
	    foreach my $loginnode (@$loginnodes) {
		my (%cmeta, @fieldlist);
		my %cardfields = ();

		# skip all types not specifically included in a supplied import types list
		next if defined $imptypes and (! exists $imptypes->{$itype});

		for (qw/Name Password CreatedDate ModifiedDate/) {
		    $cardfields{$_} = $loginnode->getAttribute($_);
		    debug "\t    Field: $_ = ", $cardfields{$_} // '';
		}
		$cardfields{'URL'} = $accountnode->getAttribute('Link');

		$cmeta{'title'} = $accountnode->getAttribute('Name');
		$cmeta{'title'} .= ' - ' . $cardfields{'Name'}	if $nlogins > 1;

		if ($accountnode->getAttribute('ParentID') ne '') {
		    $cmeta{'tags'} = path_from_id($accountnode->getAttribute('ParentID'));
		    $cmeta{'folder'} = [ split /::/, $cmeta{'tags'} ];
		}

		$cmeta{'notes'} = $accountnode->getAttribute('Comments');
		$cmeta{'notes'} =~ s/\/n/\x0d\x0a/g;

		if ($main::opts{'modified'}) {
		    $cmeta{'modified'} = date2epoch($cardfields{'ModifiedDate'});
		    delete $cardfields{'ModifiedDate'};
		}

		push @fieldlist, [ $_ => $cardfields{$_} ]	 for keys %cardfields;		# no inherent field order

		my $normalized = normalize_card_data(\%card_field_specs, $itype, \@fieldlist, \%cmeta);
		my $cardlist   = explode_normalized($itype, $normalized);

		for (keys %$cardlist) {
		    print_record($cardlist->{$_});
		    push @{$Cards{$_}}, $cardlist->{$_};
		}
		$n++;
	    }
	}
    }

    summarize_import('item', $n - 1);
    return \%Cards;
}

sub do_export {
    add_custom_fields(\%card_field_specs);
    create_pif_file(@_);
}

sub path_from_id {
    my $id = shift;

    if (! exists $groupid_map{$id}) {
	say "*** Unexpected group id: '$id'";
	return '';
    }

    return $groupid_map{$id}{'name'}	if $groupid_map{$id}{'parent'} eq '';

    return join '::', path_from_id($groupid_map{$id}{'parent'}), $groupid_map{$id}{'name'};
}

# Date converters
#     yyyy-mm-ddThh:mm:ss.sssZ		attributes: CreatedDate, ModifiedDate
sub parse_date_string {
    local $_ = $_[0];
    my $when = $_[1] || 0;					# -1 = past only, 0 = assume this century, 1 = future only, 2 = 50-yr moving window

    s/\.\d{3}Z$//;				# seconds: floating point to int, and drop the Z timezone indicator

    if (my $t = Time::Piece->strptime($_, "%Y-%m-%dT%H:%M:%S")) {	# dd.mm.yyyyThh:mm:ss
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
