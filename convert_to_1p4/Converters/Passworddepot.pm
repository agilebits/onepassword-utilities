# Password Depot XML export converter
#
# Copyright 2015 Mike Cappella (mike@cappella.us)

package Converters::Passworddepot 1.00;

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
	[ '_additioncode',      0, qr/^IDS_CardAdditionalCode$/ ],
	[ '_additioninfo',      0, qr/^IDS_CardAdditionalInfo$/ ],
	[ 'pin',      		0, qr/^IDS_CardPIN$/ ],
    ]},
    eccard =>			{ textname => undef, type_out => 'bankacct', fields => [
	[ 'password',		0, qr/^PASSWORD$/,			{ type_out => 'login' } ],
	[ 'username',		0, qr/^USERNAME$/,			{ type_out => 'login' } ],
	[ 'url',		0, qr/^URL$/,				{ type_out => 'login' } ],
	[ 'owner',		0, qr/^IDS_ECHolder$/ ],
	[ 'accountNo',		0, qr/^IDS_ECAccountNumber$/ ],
	[ '_bankcode',		0, qr/^IDS_ECBLZ$/ ],
	[ 'bankName',		0, qr/^IDS_ECBankName$/ ],
	[ '_bic',		0, qr/^IDS_ECBIC$/ ],
	[ 'iban',		0, qr/^IDS_ECIBAN$/ ],
	[ 'branchPhone',	0, qr/^IDS_ECPhone$/ ],
	[ 'telephonePin',	0, qr/^IDS_ECPIN$/ ],
	[ '_eccardnum',		0, qr/^IDS_ECCardNumber$/ ],
	[ '_legitimacyid',	0, qr/^IDS_ECLegitimacyID$/ ],
    ]},
    encryptedfile =>		{ textname => undef, type_out => 'note', fields => [
	[ 'filepath',		0, undef ],
    ]},
    identity =>			{ textname => undef, fields => [
	[ '_acct_or_id',	0, qr/^IDS_IdentityName$/ ],
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
	[ '_fax',		0, qr/^IDS_IdentityFax$/ ],
    ]},
    information =>		{ textname => undef, type_out => 'note', fields => [
    ]},
    password =>                 { textname => undef, type_out => 'login', fields => [
	[ 'username',		0, qr/^USERNAME$/, ],
	[ 'password',		0, qr/^PASSWORD$/, ],
	[ 'url',		0, qr/^URL$/, ],
    ]},
    software =>			{ textname => undef, type_out => 'software', fields => [
	[ '_product',		0, qr/^IDS_LicenseProduct$/ ],
	[ 'product_version',	0, qr/^IDS_LicenseVersion$/ ],
	[ 'reg_name',		0, qr/^IDS_LicenseName$/ ],
	[ 'reg_code',		0, qr/^IDS_LicenseKey$/ ],
	[ '_reg_code2',		0, qr/^IDS_LicenseAdditionalKey$/ ],
	[ '_licenseprotected',	0, qr/^IDS_LicenseProtected$/ ],
	[ 'url',		0, qr/^IDS_LicenseURL$/,		{ type_out => 'login' } ],
	[ 'username',		0, qr/^IDS_LicenseUserName$/,		{ type_out => 'login' } ],
	[ 'password',		0, qr/^IDS_LicensePassword$/,		{ type_out => 'login' } ],

	[ 'order_date',		0, qr/^IDS_LicensePurchaseDate$/,	{ func => sub { return days2epoch($_[0]) } } ],
	[ 'order_number',	0, qr/^IDS_LicenseOrderNumber$/ ],
	[ 'reg_email',		0, qr/^IDS_LicenseEmail$/ ],
	[ '_licenseexpires',	0, qr/^IDS_LicenseExpires$/ ],
    ]},
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

    my $cardnodes = $xp->findnodes('//PASSWORDS//ITEM');
    foreach my $cardnode (@$cardnodes) {
	my (@card_tags, @groups);

	for (my $node = $cardnode->getParentNode(); $node->getName() =~ /^GROUP$/; $node = $node->getParentNode()) {
	    my $v = $node->getAttribute("NAME");
	    unshift @groups, $v   unless $v eq '';
	}
	shift @groups	if scalar @groups;			# toss the wallet name
	if (@groups) {
	    push @card_tags, join '::', @groups;
	    debug 'Group: ', $card_tags[-1];
	}

	my (%c, $card_title, @card_notes, $itype, @fieldlist);
	if (my $fieldnodes = $xp->findnodes('*', $cardnode)) {
	    my $fieldindex = 1;;
	    foreach my $fieldnode (@$fieldnodes) {
		my $f = $fieldnode->getName();
		my $v = $fieldnode->string_value;

		next unless $f =~ /^(DESCRIPTION|TYPE|PASSWORD|USERNAME|URL|EXPIRYDATE|LASTMODIFIED|IMPORTANCE|COMMENT|CATEGORY|CREATED|URLS|CUSTOMFIELDS)$/;

		if ($f eq 'DESCRIPTION') {
		    $card_title = $v // 'Untitled';
		    debug "\tCard: ", $card_title;
		}
		elsif ($f eq 'TYPE') {
		    $itype = item_type_to_name($v);
		}
		elsif ($f eq 'COMMENT') {
		    unshift @card_notes, $v . "\n"		if $v ne '';
		}
		elsif ($f eq 'CATEGORY') {
		    push @card_tags, $v				if $v ne '';
		}
		elsif ($f eq 'IMPORTANCE') {
		    push @card_tags, join ': ', 'Importance', (qw/High unused Low/)[$v]	if $v == 0 or $v == 2;
		}
		elsif ($f eq 'URLS') {
		    push @card_notes, 'Extra URLs' . $v		if $v ne '';
		}
		elsif ($f eq 'EXPIRYDATE' and ($itype eq 'software' or $v eq '00.00.0000')) {
		    1;	# skip
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
				unshift @card_notes, $v . "\n"		if $v ne '';
			    }
			    else {
				debug "\t    cField: $f = ", $v // '';
				push @fieldlist, [ $f => $v ]	if $v ne '';		# maintain the field order, in case destination is notes
				$fieldindex++;
			    }
			}
		    }
		}
		else {
		    # Ignore the fields URL, USERNAME, and PASSWORD which are redundant since the data is
		    # held in equivalent CUSTOMFIELDS fields.
		    unless ($itype =~ /^creditcard|identity|software$/ and $f =~ /^URL|USERNAME|PASSWORD$/) {
			debug "\t    Field: $f = ", $v // '';
			push @fieldlist, [ $f => $v ];			# maintain the field order, in case destination is notes
			$fieldindex++;
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

	# From the card input, place it in the converter-normal format.
	# The card input will have matched fields removed, leaving only unmatched input to be processed later.
	my $normalized = normalize_card_data($itype, \@fieldlist, $card_title, \@card_tags, \@card_notes, \@groups);

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

    $n--;
    verbose "Imported $n card", pluralize($n) ,
	$npre_explode ? " ($npre_explode card" . pluralize($npre_explode) .  " expanded to $npost_explode cards)" : "";
    return \%Cards;
}

sub do_export {
    add_new_field('bankacct',       '_bankcode',	$Utils::PIF::sn_main,		$Utils::PIF::k_string,    'bank code');
    add_new_field('bankacct',       '_bic',		$Utils::PIF::sn_main,		$Utils::PIF::k_string,    'bic');
    add_new_field('bankacct',       '_eccardnum',	'otherbank.EC Card',		$Utils::PIF::k_string,    'card number');
    add_new_field('bankacct',       '_legitimacyid',	'otherbank.EC Card',		$Utils::PIF::k_string,    'legitimacy id');

    add_new_field('identity',       '_acct_or_id',	'other.Miscellaneous',		$Utils::PIF::k_string,    'account/id');
    add_new_field('identity',       '_fax',		$Utils::PIF::sn_address,	$Utils::PIF::k_string,    'fax');
    add_new_field('creditcard',     '_additioncode',	$Utils::PIF::sn_details,	$Utils::PIF::k_string,    'additional code');
    add_new_field('creditcard',     '_additioninfo',	$Utils::PIF::sn_details,	$Utils::PIF::k_string,    'additional info');
    add_new_field('creditcard',     '_legitimacyid',	$Utils::PIF::sn_details,	$Utils::PIF::k_string,    'legitimacy id');
    # Can't place extra fields into main section of software
    add_new_field('software',       '_product',		'other.Miscellaneous',		$Utils::PIF::k_string,    'product');
    add_new_field('software',       '_reg_code2',	'other.Miscellaneous',		$Utils::PIF::k_string,    'additional key');
    add_new_field('software',       '_licenseexpires',	'other.Miscellaneous',		$Utils::PIF::k_string,    'license expiry');

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
    my ($type, $fieldlist, $title, $tags, $notesref, $folder, $postprocess) = @_;
    my %norm_cards = (
	title	=> $title,
	notes	=> $notesref,
	tags	=> $tags,
	folder	=> $folder,
    );

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
		push @{$norm_cards{'fields'}}, $h;
		splice @$fieldlist, $i, 1;	# delete matched so undetected are pushed to notes below
		last;
	    }
	}
    }

    # map remaining keys to notes
    for (@$fieldlist) {
	next if $_->[1] eq '';
	push @{$norm_cards{'notes'}}, join ': ', @$_;
    }

    $postprocess and ($postprocess)->($type, \%norm_cards);
    return \%norm_cards;
}

# Date converters
# Password Depot validates date input on Date types.  Dates are stored in several formats:
#     mm/yyyy		fields: IDS_CardExpires
sub parse_date_string {
    local $_ = $_[0];
    my $when = $_[1] || 0;					# -1 = past only, 0 = assume this century, 1 = future only, 2 = 50-yr moving window

    if (/^(?<m>\d{2})\/(?<y>\d{4})/) {		# mm/yyyy
	my $m = sprintf "%02d", $+{'m'};
	if (check_date($+{'y'}, $m, 1)) {
	    return ($+{'y'}, $m, 1);
	}
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

1;
