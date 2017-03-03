# Key Finder XML export converter
#
# Copyright 2016 Mike Cappella (mike@cappella.us)

package Converters::Keyfinder 1.03;

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


=cut
        [ 'product_version',    $sn_main,               $k_string,      'version' ],
        [ 'reg_code',           $sn_main,               $k_string,      'license key',          'guarded'=>'yes', 'multiline'=>'yes' ],
        [ 'reg_name',           $sn_customer,           $k_string,      'licensed to' ],
        [ 'reg_email',          $sn_customer,           $k_email,       'registered email' ],
        [ 'company',            $sn_customer,           $k_string,      'company' ],
        [ 'download_link',      $sn_publisher,          $k_url,         'download page' ],
        [ 'publisher_name',     $sn_publisher,          $k_string,      'publisher' ],
        [ 'publisher_website',  $sn_publisher,          $k_url,         'website' ],
        [ 'retail_price',       $sn_publisher,          $k_string,      'retail price' ],
        [ 'support_email',      $sn_publisher,          $k_email,       'support email' ],
        [ 'order_date',         $sn_order,              $k_date,        'purchase date' ],
        [ 'order_number',       $sn_order,              $k_string,      'order number' ],
        [ 'order_total',        $sn_order,              $k_string,      'order total' ],
=cut

# a list of title REs to skip
my @ignored_titles = (
    '^Apple Coreservices Appleidauthenticationinfo',
);

my %card_field_specs = (
    software =>			{ textname => undef, fields => [
	[ 'reg_code',		1, qr/^serial(?:number)?|licenseCode|regcode$/i, ],
    ]},
);

$DB::single = 1;					# triggers breakpoint when debugging

sub do_init {
    return {
	'specs'		=> \%card_field_specs,
	'imptypes'  	=> undef,
	'opts'		=> [ ],
    };
}

sub do_import {
    my ($file, $imptypes) = @_;

    $_ = slurp_file($file);

    my (%Cards, %records);
    my $n = 1;

    my $xp = XML::XPath->new(xml => $_);
    my $dbnodes = $xp->find('//Key');
    foreach my $node ($dbnodes->get_nodelist) {
	my $scan_type = $node->getParentNode->getName();
	my $computer_name = $node->getParentNode->getParentNode->getAttribute('computerName');

	my $title = $node->getAttribute('NAME');
	next if grep { $title =~ qr/$_/ } @ignored_titles;

	my ($type, $value) = ($node->getAttribute('TYPE'), $node->getAttribute('VALUE'));
	debug "   $computer_name($scan_type):\ttitle; $title, type: $type, value: $value";

	$records{$title}{$type} = $value;
	$records{$title}{'SCANTYPE__'} = $scan_type;
	$records{$title}{'COMPUTER__'} = $computer_name;
    }

    for my $title (keys %records) {
	my (%cmeta, @fieldlist);

	$cmeta{'title'} = $title;

	debug "Card: ", $cmeta{'title'};

	for (keys %{$records{$title}}) {
	    push @fieldlist, [ $_, $records{$title}{$_}  ];
	    debug "\t\t$fieldlist[-1][0]: $fieldlist[-1][1]";
	}

	my $itype = find_card_type(\@fieldlist);

	# skip all types not specifically included in a supplied import types list
	next if defined $imptypes and (! exists $imptypes->{$itype});

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

sub find_card_type {
    my $fieldlist = shift;
    my $type = 'software';

=cut
    for $type (sort by_test_order keys %card_field_specs) {
	for my $cfs (@{$card_field_specs{$type}{'fields'}}) {
	    next unless $cfs->[CFS_TYPEHINT] and defined $cfs->[CFS_MATCHSTR];
	    for (@$fieldlist) {
		# type hint
		if ($_->[0] =~ $cfs->[CFS_MATCHSTR]) {
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
=cut

    debug "\ttype defaulting to '$type'";
    return $type;
}

# sort logins as the last to check
sub by_test_order {
    return  1 if $a eq 'webacct';
    return -1 if $b eq 'webacct';
    return  1 if $a eq 'login';
    return -1 if $b eq 'login';
    $a cmp $b;
}

sub date2epoch {
    my $msecs = shift;
    return $msecs / 1000;
}

1;
