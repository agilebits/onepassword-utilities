# KeePass 2 XML export converter
#
# Copyright 2014 Mike Cappella (mike@cappella.us)

package Converters::Keepass2 1.05;

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
use HTML::Entities;
use Time::Local qw(timegm);
use Time::Piece;
use Compress::Raw::Zlib;
use MIME::Base64;

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

sub do_init {
    return {
	'specs'		=> \%card_field_specs,
	'imptypes'  	=> undef,
    };
}

sub do_import {
    my ($file, $imptypes) = @_;
    my %Cards;

    my $xp = XML::XPath->new(filename => $file);

    my %attachments;
    foreach my $binnode ($xp->findnodes('/KeePassFile/Meta/Binaries/Binary')) {
	my $id = $binnode->getAttribute('ID');
	$attachments{$id}{'iscompressed'} = (defined $binnode->getAttribute('Compressed') and $binnode->getAttribute('Compressed') eq 'True') || 0;
	$attachments{$id}{'data'} = $binnode->string_value;
    }

    my $n = 1;

    my $groupnodes = $xp->find('/KeePassFile/Root//Group');
    foreach my $groupnode ($groupnodes->get_nodelist) {
	my @group = get_group_path($xp, $groupnode);

	my $entrynodes = $xp->find('./Entry', $groupnode);
	foreach my $entrynode ($entrynodes->get_nodelist) {
	    my (%cmeta, @fieldlist);
	    debug "ENTRY:";
	    debug "Node: ", $entrynode->getName;

	    my $entry_data = get_entrydata_from_entry('Element', $xp, $entrynode, $main::opts{'notimestamps'});
	    for (@{$entry_data->{'kvpairs'}}) {
		next if $_->[1] eq '';
		if ($_->[0] =~ /^Title|Notes$/) {
		    $cmeta{lc $_->[0]} = $_->[1];
		}
		elsif ($_->[0] eq 'LastModificationTime' and not $main::opts{'notimestamps'}) {
		    $cmeta{'modified'} = date2epoch($_->[1]);
		}
		elsif ($_->[0] eq 'CreationTime' and not $main::opts{'notimestamps'}) {
		    $cmeta{'created'} = date2epoch($_->[1]);
		}
		else {
		    push @fieldlist, [ $_->[0] => $_->[1] ];
		}
	    }
	    my $itype = find_card_type(\@fieldlist);
	    # skip all types not specifically included in a supplied import types list
	    next if defined $imptypes and (! exists $imptypes->{$itype});

	    $cmeta{'tags'} = join '::', @group;
	    $cmeta{'folder'} = [ @group ];

	    # handle creation of attachment files from encoded / compressed string
	    if (exists $entry_data->{'attachments'}) {
		my $dir;
		for (@{$entry_data->{'attachments'}}) {
		    my $data;
		    if ($attachments{$_->{'id'}}->{'iscompressed'}) {
			my $inf = new Compress::Raw::Zlib::Inflate('-WindowBits' => WANT_GZIP_OR_ZLIB) ;
			my $status = $inf->inflate(decode_base64($attachments{$_->{'id'}}->{'data'}), $data);
			if ($status == Z_OK or $status == Z_STREAM_END) {
			    $dir = create_attachment(\$data, $dir, $_->{'filename'}, $cmeta{'title'});
			}
			else {
			    warn "Failed to inflate compressed data: $_->{'filename'}\n$!";
			}
		    }
		    else {
			$data = decode_base64 $attachments{$_->{'id'}}->{'data'};
			$dir = create_attachment(\$data, $dir, $_->{'filename'}, $cmeta{'title'});
		    }
		}
	    }

	    # History entries
	    my $histentrynodes = $xp->find('./History/Entry', $entrynode);
	    foreach my $histentrynode ($histentrynodes->get_nodelist) {
		my $histentry_data = get_entrydata_from_entry('History element', $xp, $histentrynode, 1);
		if (my @pw = grep { $_->[0] eq 'Password' } @{$histentry_data->{'kvpairs'}}) {
		    if (my @time = grep { $_->[0] eq 'LastModificationTime' } @{$histentry_data->{'kvpairs'}}) {
			push @{$cmeta{'pwhistory'}}, [ $pw[0][1], date2epoch($time[0][1]) ];
		    }
		}
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
    my $f = shift;
    my $type;

    for $type (sort by_test_order keys %card_field_specs) {
	for my $cfs (@{$card_field_specs{$type}{'fields'}}) {
	    for (@$f) {
		my $key = $_->[0];
		if ($cfs->[CFS_TYPEHINT] and $key =~ $cfs->[CFS_MATCHSTR]) {
		    debug "type detected as '$type' (key='$key')";
		    return $type;
		}
	    }
	}
    }

    return 'note';
}

# sort logins as the last to check
sub by_test_order {
    return  1 if $a eq 'login';
    return -1 if $b eq 'login';
    $a cmp $b;
}

sub get_entrydata_from_entry {
    my ($type, $xp, $entrynode, $notimestamps) = @_;

    my %entrydata;

    foreach my $element ($entrynode->getChildNodes) {
	next unless scalar $element->getName;
	debug "$type: ", $element->getName;
	if ($element->getName eq 'String') {
	    my $key = ($xp->findnodes('./Key', $element))[0]->string_value;
	    my $value = ($xp->findnodes('./Value', $element))[0]->string_value;
	    debug "\tkey: $key: '$value'";
	    push @{$entrydata{'kvpairs'}}, [ $key => $value ]	if $value ne '';
	}
	elsif ($element->getName eq 'Binary') {
	    my %a = (
		filename => ($xp->findnodes('./Key',   $element))[0]->string_value,
		id       => ($xp->findnodes('./Value', $element))[0]->getAttribute('Ref'),
	    );
	    debug "\tAttachment $a{'id'}: '$a{'filename'}";
	    push @{$entrydata{'attachments'}}, \%a;
	}
	elsif ($element->getName eq 'Times' and not $notimestamps) {
	    my $mtime = ($xp->findnodes('./LastModificationTime', $element))[0]->string_value;
	    debug "\tkey: LastModificationTime: '$mtime'";
	    push @{$entrydata{'kvpairs'}}, [ 'LastModificationTime' => $mtime ];

	    my $ctime = ($xp->findnodes('./CreationTime', $element))[0]->string_value;
	    debug "\tkey: CreationTime: '$ctime'";
	    push @{$entrydata{'kvpairs'}}, [ 'CreationTime' => $ctime ];
	}
    }

    return \%entrydata;
}
sub get_group_path {
    my ($xp, $node) = @_;

    my @names;
    while ($node->getName ne 'Root') {
	unshift @names, ($xp->findnodes('./Name', $node))[0]->string_value;
	$node = $node->getParentNode;
    }

    shift @names;
    debug "\tGROUP: ", join '::', @names;
    return @names;
}

# Date converters
# LastModificationTime field:	 yyyy-mm-ddThh:mm:ssZ
sub parse_date_string {
    local $_ = $_[0];
    my $when = $_[1] || 0;					# -1 = past only, 0 = assume this century, 1 = future only, 2 = 50-yr moving window

    if (my $t = Time::Piece->strptime($_, "%Y-%m-%dT%H:%M:%SZ")) {	# KeePass 2 dates are in standard UTC string format
	return $t;
    }

    return undef;
}

sub date2epoch {
    my $t = parse_date_string @_;
    return undef if not defined $t;
    return defined $t->year ? 0 + timegm($t->sec, $t->minute, $t->hour, $t->mday, $t->mon - 1, $t->year): $_[0];
}

1;
