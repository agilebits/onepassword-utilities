# IronKey Identity Manager XML export converter
#
# Copyright 2015 Mike Cappella (mike@cappella.us)

package Converters::Ironkeyim 1.00;

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
use Time::Local qw(timelocal);
use Time::Piece;

# encrypted file
my %card_field_specs = (
    login =>                 { textname => undef, type_out => 'login', fields => [
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

    {
	local $/ = undef;
	open my $fh, '<', $file or bail "Unable to open file: $file\n$!";
	$_ = <$fh>;
	close $fh;
    }

    my $n = 1;
    my ($npre_explode, $npost_explode);

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
		my @fieldlist;
		my %cardfields = ();

		# skip all types not specifically included in a supplied import types list
		next if defined $imptypes and (! exists $imptypes->{$itype});

		for (qw/Name Password CreatedDate ModifiedDate/) {
		    $cardfields{$_} = $loginnode->getAttribute($_);
		    debug "\t    Field: $_ = ", $cardfields{$_} // '';
		}
		$cardfields{'URL'} = $accountnode->getAttribute('Link');

		my $card_title = $accountnode->getAttribute('Name');
		$card_title .= ' - ' . $cardfields{'Name'}	if $nlogins > 1;

		my ($card_tags, @card_folder);

		if ($accountnode->getAttribute('ParentID') ne '') {
		    $card_tags = path_from_id($accountnode->getAttribute('ParentID'));
		    @card_folder = split /::/, $card_tags;
		}

		my $card_notes = $accountnode->getAttribute('Comments');
		$card_notes =~ s/\/n/\x0d\x0a/g;

		if ($main::opts{'modified'}) {
		    $card_modified = date2epoch($cardfields{'ModifiedDate'});
		    delete $cardfields{'ModifiedDate'};
		}

		for (keys %cardfields) {
		    push @fieldlist, [ $_ => $cardfields{$_} ];			# done for confority with other converters - no inherent field order
		}

		# From the card input, place it in the converter-normal format.
		# The card input will have matched fields removed, leaving only unmatched input to be processed later.
		my $normalized = normalize_card_data($itype, \@fieldlist,
		    { title	=> $card_title,
		      tags	=> $card_tags,
		      notes	=> $card_notes,
		      folder	=> \@card_folder,
		      modified	=> $card_modified });

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

# Places card data into a normalized internal form.
#
# Basic card data passed as $norm_cards hash ref:
#    title
#    notes
#    tags
#    folder
#    modified
# Per-field data hash {
#    inkey	=> imported field name
#    value	=> field value after callback processing
#    valueorig	=> original field value
#    outkey	=> exported field name
#    outtype	=> field's output type (may be different than card's output type)
#    keep	=> keep inkey:valueorig pair can be placed in notes
#    to_title	=> append title with a value from the narmalized card
# }
sub normalize_card_data {
    my ($type, $fieldlist, $norm_cards) = @_;

    for my $def (@{$card_field_specs{$type}{'fields'}}) {
	my $h = {};
	for (my $i = 0; $i < @$fieldlist; $i++) {
	    my ($inkey, $value) = @{$fieldlist->[$i]};
	    next if not defined $value or $value eq '';

	    if (!defined $def->[2] or $inkey =~ $def->[2]) {
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
		push @{$norm_cards->{'fields'}}, $h;
		splice @$fieldlist, $i, 1;	# delete matched so undetected are pushed to notes below
		last;
	    }
	}
    }

    # map remaining keys to notes
    $norm_cards->{'notes'} .= "\n"	if defined $norm_cards->{'notes'} and length $norm_cards->{'notes'} > 0 and @$fieldlist;
    for (@$fieldlist) {
	next if $_->[1] eq '';
	$norm_cards->{'notes'} .= "\n"	if defined $norm_cards->{'notes'} and length $norm_cards->{'notes'} > 0;
	$norm_cards->{'notes'} .= join ': ', @$_;
    }

    return $norm_cards;
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
    return defined $t->year ? 0 + timelocal($t->sec, $t->minute, $t->hour, $t->mday, $t->mon - 1, $t->year): $_[0];
}

1;
