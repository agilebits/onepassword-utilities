# Password Depot XML export converter
#
# Copyright 2015 Mike Cappella (mike@cappella.us)

package Converters::Passworddepot 1.02;

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
use Date::Calc qw(check_date Add_Delta_Days);

# encrypted file
my %card_field_specs = (
    creditcard =>		{ textname => undef, fields => [
	[ 'type',		0, qr/^IDS_CardType$/,			{ func => sub { return ccard_type_to_name($_[0]) } } ],
	[ 'ccnum',		0, qr/^IDS_CardNumber$/ ],
	[ 'cardholder',		0, qr/^IDS_CardHolder$/ ],
	[ 'expiry',		0, qr/^IDS_CardExpires$/, 		{ func => sub { return date2monthYear($_[0], 2) } } ],
	[ 'cvv',		0, qr/^IDS_CardCode$/ ],
	[ 'phoneTollFree',      0, qr/^IDS_CardPhone$/ ],
	[ 'website',      	0, qr/^IDS_CardURL$/ ],
	[ '_additioncode',      0, qr/^IDS_CardAdditionalCode$/,	{ custfield => [ $Utils::PIF::sn_details, $Utils::PIF::k_string, 'additional code' ] } ],
	[ '_additioninfo',      0, qr/^IDS_CardAdditionalInfo$/,	{ custfield => [ $Utils::PIF::sn_details, $Utils::PIF::k_string, 'additional info' ] } ],
	[ 'pin',      		0, qr/^IDS_CardPIN$/ ],
    ]},
    eccard =>			{ textname => undef, type_out => 'bankacct', fields => [
	[ 'password',		0, qr/^PASSWORD$/,			{ type_out => 'login' } ],
	[ 'username',		0, qr/^USERNAME$/,			{ type_out => 'login' } ],
	[ 'url',		0, qr/^URL$/,				{ type_out => 'login' } ],
	[ 'owner',		0, qr/^IDS_ECHolder$/ ],
	[ 'accountNo',		0, qr/^IDS_ECAccountNumber$/ ],
	[ '_bankcode',		0, qr/^IDS_ECBLZ$/,			{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_string, 'bank code' ] } ],
	[ 'bankName',		0, qr/^IDS_ECBankName$/ ],
	[ '_bic',		0, qr/^IDS_ECBIC$/,			{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_string, 'bic' ] } ],
	[ 'iban',		0, qr/^IDS_ECIBAN$/ ],
	[ 'branchPhone',	0, qr/^IDS_ECPhone$/ ],
	[ 'telephonePin',	0, qr/^IDS_ECPIN$/ ],
	[ '_eccardnum',		0, qr/^IDS_ECCardNumber$/,		{ custfield => [ 'otherbank.EC Card', $Utils::PIF::k_string, 'card number' ] } ],
	[ '_legitimacyid',	0, qr/^IDS_ECLegitimacyID$/,		{ custfield => [ 'otherbank.EC Card', $Utils::PIF::k_string, 'legitimacy id' ] } ],
    ]},
    encryptedfile =>		{ textname => undef, type_out => 'note', fields => [
	[ 'filepath',		0, qr/^_NeverMatches_$/ ],
    ]},
    identity =>			{ textname => undef, fields => [
	[ '_acct_or_id',	0, qr/^IDS_IdentityName$/,		{ custfield => [ 'other.Miscellaneous', $Utils::PIF::k_string, 'account/id' ] } ],
	[ 'email',		0, qr/^IDS_IdentityEmail$/ ],
	[ 'firstname',		0, qr/^IDS_IdentityFirstName$/ ],
	[ 'lastname',		0, qr/^IDS_IdentityLastName$/ ],
	[ 'company',		0, qr/^IDS_IdentityCompany$/ ],
	[ 'address',            0, qr/^address$/, ],			# combines original fields: Address[12]
	[ 'addr1',		0, qr/^IDS_IdentityAddress1$/ ],
	[ 'addr2',		0, qr/^IDS_IdentityAddress2$/ ],
	[ 'city',		0, qr/^IDS_IdentityCity$/ ],
	[ 'state',		0, qr/^IDS_IdentityState$/ ],
	[ 'zip',		0, qr/^IDS_IdentityZIP$/ ],
	[ 'country',		0, qr/^IDS_IdentityCountry$/ ],
	[ 'defphone',		0, qr/^IDS_IdentityPhone$/ ],
	[ 'website',		0, qr/^IDS_IdentityWebsite$/ ],
	[ 'birthdate',		0, qr/^IDS_IdentityBirthDate$/,		{ func => sub { return days2epoch($_[0]) } } ],
	[ 'cellphone',		0, qr/^IDS_IdentityMobile$/ ],
	[ '_fax',		0, qr/^IDS_IdentityFax$/,		{ custfield => [ $Utils::PIF::sn_address, $Utils::PIF::k_string, 'fax' ] } ],
    ]},
    information =>		{ textname => undef, type_out => 'note', fields => [
    ]},
    password =>                 { textname => undef, type_out => 'login', fields => [
	[ 'username',		0, qr/^USERNAME$/, ],
	[ 'password',		0, qr/^PASSWORD$/, ],
	[ 'url',		0, qr/^URL$/, ],
    ]},
    software =>			{ textname => undef, type_out => 'software', fields => [
    									# Can't place extra fields into main section of software
	[ '_product',		0, qr/^IDS_LicenseProduct$/,		{ custfield => [ 'other.Miscellaneous', $Utils::PIF::k_string, 'product' ] } ],
	[ 'product_version',	0, qr/^IDS_LicenseVersion$/ ],
	[ 'reg_name',		0, qr/^IDS_LicenseName$/ ],
	[ 'reg_code',		0, qr/^IDS_LicenseKey$/ ],
	[ '_reg_code2',		0, qr/^IDS_LicenseAdditionalKey$/,	{ custfield => [ 'other.Miscellaneous', $Utils::PIF::k_string, 'additional key' ] } ],
	[ '_licenseprotected',	0, qr/^IDS_LicenseProtected$/ ],
	[ 'url',		0, qr/^IDS_LicenseURL$/,		{ type_out => 'login' } ],
	[ 'username',		0, qr/^IDS_LicenseUserName$/,		{ type_out => 'login' } ],
	[ 'password',		0, qr/^IDS_LicensePassword$/,		{ type_out => 'login' } ],
	[ 'order_date',		0, qr/^IDS_LicensePurchaseDate$/,	{ func => sub { return days2epoch($_[0]) } } ],
	[ 'order_number',	0, qr/^IDS_LicenseOrderNumber$/ ],
	[ 'reg_email',		0, qr/^IDS_LicenseEmail$/ ],
	[ '_licenseexpires',	0, qr/^IDS_LicenseExpires$/,		{ custfield => [ 'other.Miscellaneous', $Utils::PIF::k_string, 'license expiry' ] } ],
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

    $_ = slurp_file($file);

    my $n = 1;

    my $xp = XML::XPath->new(xml => $_);

    my $cardnodes = $xp->findnodes('//PASSWORDS//ITEM');
    foreach my $cardnode (@$cardnodes) {
	my (@groups, $itype, %cmeta, @fieldlist);

	for (my $node = $cardnode->getParentNode(); $node->getName() =~ /^GROUP$/; $node = $node->getParentNode()) {
	    my $v = $node->getAttribute("NAME");
	    unshift @groups, $v   unless $v eq '';
	}
	shift @groups	if scalar @groups;			# toss the wallet name
	if (@groups) {
	    push @{$cmeta{'tags'}}, join '::', @groups;
	    $cmeta{'folder'} = \@groups;
	    debug 'Group: ', $cmeta{'tags'}[-1];
	}

	if (my $fieldnodes = $xp->findnodes('*', $cardnode)) {
	    foreach my $fieldnode (@$fieldnodes) {
		my $f = $fieldnode->getName();
		my $v = $fieldnode->string_value;

		next unless $f =~ /^(DESCRIPTION|TYPE|PASSWORD|USERNAME|URL|EXPIRYDATE|LASTMODIFIED|IMPORTANCE|COMMENT|CATEGORY|CREATED|URLS|CUSTOMFIELDS)$/;

		if ($f eq 'DESCRIPTION') {
		    $cmeta{'title'} = $v // 'Untitled';
		    debug "\tCard: ", $cmeta{'title'};
		}
		elsif ($f eq 'TYPE') {
		    $itype = item_type_to_name($v);
		}
		elsif ($f eq 'COMMENT') {
		    unshift @{$cmeta{'notes'}}, $v . "\n"		if $v ne '';
		}
		elsif ($f eq 'CATEGORY') {
		    push @{$cmeta{'tags'}}, $v				if $v ne '';
		}
		elsif ($f eq 'IMPORTANCE') {
		    push @{$cmeta{'tags'}}, join ': ', 'Importance', (qw/High unused Low/)[$v]	if $v == 0 or $v == 2;
		}
		elsif ($f eq 'URLS') {
		    push @{$cmeta{'notes'}}, 'Extra URLs' . $v		if $v ne '';
		}
		elsif ($f eq 'EXPIRYDATE' and ($itype eq 'software' or $v eq '00.00.0000')) {
		    1;	# skip
		}
		elsif ($f eq 'LASTMODIFIED' and not $main::opts{'notimestamps'}) {
		    $cmeta{'modified'} = date2epoch($v);
		}
		elsif ($f eq 'CREATED' and not $main::opts{'notimestamps'}) {
		    $cmeta{'created'} = date2epoch($v);
		}
		elsif ($f eq 'CUSTOMFIELDS') {
		    if (my $customfieldnodes = $xp->findnodes('FIELD', $fieldnode)) {
			($f, $v) = (undef, undef);
			foreach my $customfieldnode (@$customfieldnodes) {
			    $f = ($xp->findnodes('NAME', $customfieldnode))->string_value;
			    $v = ($xp->findnodes('VALUE', $customfieldnode))->string_value;
			    if ($itype eq 'encryptedfile') {
				$v = join '', $v, $f;
				$f = 'filepath';
			    }
			    if ($itype eq 'information' and $f eq 'IDS_InformationText') {
				unshift @{$cmeta{'notes'}}, $v . "\n"		if $v ne '';
			    }
			    else {
				debug "\t    cField: $f = ", $v // '';
				push @fieldlist, [ $f => $v ]	if $v ne '';
			    }
			}
		    }
		}
		else {
		    # Ignore the fields URL, USERNAME, and PASSWORD which are redundant since the data is
		    # held in equivalent CUSTOMFIELDS fields.
		    unless ($itype =~ /^creditcard|identity|software$/ and $f =~ /^URL|USERNAME|PASSWORD$/) {
			debug "\t    Field: $f = ", $v // '';
			push @fieldlist, [ $f => $v ];
		    }
		}
	    }
	}

	# skip all types not specifically included in a supplied import types list
	next if defined $imptypes and (! exists $imptypes->{$itype});

	if ($itype eq 'identity') {
	    my (%addr, @newfieldlist);
	    for (@fieldlist) {
		if ($_->[0] =~ /^IDS_Identity(City|State|ZIP|Country)$/) {
		    $addr{lc $1} = $_->[1];
		}
		elsif ($_->[0] =~ /^IDS_IdentityAddress[12]$/) {
		    $addr{'street'} = myjoin ', ', $addr{'street'}, $_->[1];
		}
		else {
		    push @newfieldlist, $_;
		}
	    }
	    @fieldlist = @newfieldlist;
	    push @fieldlist, [ 'address' => \%addr ]		if keys %addr;
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

sub item_type_to_name {
    my $index = shift;
    my $type = (qw/password creditcard software identity information eccard encryptedfile/)[$index];
    debug "\t\ttype detected as '$type'";
    return $type;
}

sub ccard_type_to_name {
    my $index = shift;
    return ('Mastercard', 'Discover', 'VISA', 'American Express', 'JCB', 'Diners Club')[$index];
}

# Date converters
# Password Depot validates date input on Date types.  Dates are stored in several formats:
#     mm[/.]yyyy		fields: IDS_CardExpires
#     dd.mm.yyyy hh:mm:ss 	fields: LASTMODIFIED, CREATED, LASTACCESSED
sub parse_date_string {
    local $_ = $_[0];
    my $when = $_[1] || 0;					# -1 = past only, 0 = assume this century, 1 = future only, 2 = 50-yr moving window

    if (/^(?<m>\d{2})[.\/](?<y>\d{4})/) {		# mm/yyyy or mm.yyyy
	my $m = sprintf "%02d", $+{'m'};
	if (check_date($+{'y'}, $m, 1)) {
	    return ($+{'y'}, $m, 1);
	}
    }
    elsif (my $t = Time::Piece->strptime($_, "%d.%m.%Y %H:%M:%S")) {	# dd.mm.yyyy hh:mm:ss
	return $t;
    }

    return undef;
}

sub date2monthYear {
    my ($y, $m, $d) = parse_date_string @_;
    return defined $y ? $y . $m	: $_[0];
}

# Converts a Password Depot number of days since 12/31/1899 value into a 1Password epoch value
sub days2epoch {
    my $days = shift;

    my ($year,$month,$day) = Add_Delta_Days(1899, 12, 31, $days - 1);
    return timelocal(0, 0, 0, $day, $month - 1, $year);
}

sub date2epoch {
    my $t = parse_date_string @_;
    return undef if not defined $t;
    return defined $t->year ? 0 + timelocal($t->sec, $t->minute, $t->hour, $t->mday, $t->mon - 1, $t->year): $_[0];
}

1;
