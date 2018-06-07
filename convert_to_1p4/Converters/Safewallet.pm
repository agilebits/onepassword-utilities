# SafeWallet XML export converter
#
# Copyright 2014 Mike Cappella (mike@cappella.us)

package Converters::Safewallet 1.02;

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
use Date::Calc qw(check_date Date_to_Days);

my %card_field_specs = (
    address =>			{ textname => undef, type_out => 'identity', fields => [
	[ 'addr_place',		0, qr/^Place$/, ],
	[ 'firstname',		0, qr/^First Name$/, ],
	[ 'lastname',		0, qr/^Last Name$/, ],
	[ 'address',		0, qr/^address$/, ],			# see 'Fixup: combines address', fields: Address #[123]
	[ 'addr1',		1, qr/^Address #1$/, ],			# see 'Fixup: combines address'
	[ 'addr2',		1, qr/^Address #2$/, ],			# see 'Fixup: combines address'
	[ 'addr3',		1, qr/^Address #3$/, ],			# see 'Fixup: combines address'
	[ 'city',		0, qr/^City$/, ],
	[ 'state',		0, qr/^State$/, ],
	[ 'zip',		1, qr/^ZIP$/, ],
	[ 'country',		1, qr/^Country$/, ],
	[ 'homephone',		0, qr/^Phone$/, ],
	[ 'email',		0, qr/^Email$/, ],
    ]},
    bankacct =>			{ textname => undef, fields => [
	[ 'accountNo',          0, qr/^Account #$/, ],
	[ '_branchNumber',	1, qr/^Branch #$/, 		{ custfield => [ $Utils::PIF::sn_branchInfo, $Utils::PIF::k_string, 'branch number' ] } ],
	[ '_bankNumber',	1, qr/^Bank #$/, 		{ custfield => [ $Utils::PIF::sn_branchInfo, $Utils::PIF::k_string, 'bank number' ] } ],
	[ 'bankName',		0, qr/^Branch Name$/, ],
	[ 'routingNo',		0, qr/^Routing #$/, ],
	[ 'contact1',		1, qr/^Contact Person 1$/, ],
	[ 'contactphone1',	0, qr/^Phone 1$/, ],
	[ 'contact2',		1, qr/^Contact Person 2$/, ],
	[ 'contactphone2',	0, qr/^Phone 2$/, ],
	[ 'bankhours',		1, qr/^Opening Hours$/, ],
	[ 'accountType',	0, qr/^Type$/, ],
	[ 'telephonePin',	1, qr/^ATM PIN$/, ],
	[ 'swift',		1, qr/^SWIFT$/, ],
	[ 'url',		0, qr/^Web-Site$/,		{ type_out => 'login' } ],
	[ 'username',		0, qr/^Username$/,		{ type_out => 'login' } ],
	[ 'password',		0, qr/^Password$/,		{ type_out => 'login' } ],
    ]},
    callingcard =>		{ textname => undef, type_out => 'note', fields => [
	[ 'callcardprovider',	0, qr/^Provider$/, ],
	[ 'callcardaccessnum',	1, qr/^Access #$/, ],
	[ 'callcardnum',	0, qr/^Card #$/, ],
	[ 'callcardpin',	0, qr/^PIN$/, 			{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_concealed, 'pin', 'generate'=>'off' ] } ],
	[ 'callcardphone',	0, qr/^If Lost$/, ],
	[ 'callcardusage',	1, qr/^Usage$/, ],
    ]},
    carinfo =>			{ textname => undef, type_out => 'note', fields => [
	[ 'carinfomodel',	1, qr/^Model$/, ],
	[ 'carinfomake',	1, qr/^Make$/, ],
	[ 'carinfoyear',	1, qr/^Year$/, ],
	[ 'carinfolicense',	1, qr/^License$/, ],
	[ 'carinfoexpires',	0, qr/^Expires$/, ],
	[ 'carinfovin',		1, qr/^Vehicle Identification Number \(VIN\)$/, ],
	[ 'carinfoinsurance',	1, qr/^Insurance$/, ],
	[ 'carinfopolicy',	0, qr/^Policy #$/, ],
	[ 'carinfophone',	0, qr/^Phone$/, ],
    ]},
    clothing =>			{ textname => undef, type_out => 'note', fields => [
	[ 'clothingfor',	1, qr/^Size For$/, ],
	[ 'clothingsuit',	1, qr/^Suit$/, ],
	[ 'clothingshoes',	1, qr/^Shoes$/, ],
	[ 'clothingshirt',	1, qr/^Shirt$/, ],
	[ 'clothingwaist',	1, qr/^Waist$/, ],
	[ 'clothingpants',	1, qr/^Pants$/, ],
	[ 'clothingneck',	1, qr/^Neck$/, ],
	[ 'clothinginseam',	1, qr/^Inseam$/, ],
	[ 'clothingskirt',	1, qr/^Skirt$/, ],
	[ 'clothingglove',	1, qr/^Glove$/, ],
    ]},
    contact =>			{ textname => undef, type_out => 'note', fields => [
	[ '_firstname',		0, qr/^First Name$/, ],
	[ '_lastname',		0, qr/^Last Name$/, ],
	[ '_company',		0, qr/^Company$/, ],
	[ '_phonecell',		1, qr/^Mobile Phone$/, ],
	[ '_phonehome',		1, qr/^Home Phone$/, ],
	[ '_phonebiz',		1, qr/^Business Phone$/, ],
	[ '_email',		0, qr/^Email$/, ],
    ]},
    creditcard =>		{ textname => undef, fields => [
	[ 'type',		0, qr/^Card$/, ],
	[ 'bank',		0, qr/^Bank$/, ],
	[ '_firstname',		0, qr/^First Name$/, ],		# see 'Fixup: combine names'
	[ '_lastname',		0, qr/^Last Name$/, ],		# see 'Fixup: combine names'
        [ 'cardholder',         0, qr/^First \+ Last$/, ],	# see 'Fixup: combine names'; input never matches
	[ 'ccnum',		0, qr/^Card #$/, ],
	[ 'expiry',		0, qr/^Expires$/,		{ func => sub { return date2monthYear($_[0], 2) }, keep => 1 } ],
	[ 'cvv',		1, qr/^CVV2$/, ],
	[ 'pin',		0, qr/^PIN$/, ],
	[ 'phoneTollFree',	1, qr/^If Lost$/, ],
    ]},
    driverslicense =>           { textname => undef, fields => [
	[ 'number',		0, qr/^Number$/, ],
	[ 'dllocation',		1, qr/^Location$/, ],
	[ '_issued_on',		1, qr/^Issued On$/,		{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_monthYear, 'issue date' ],
								  func => sub { return date2monthYear($_[0], 2) }, keep => 1 } ],
	[ 'expiry_date',	0, qr/^Expires$/, 		{ func => sub { return date2monthYear($_[0], 2) }, keep => 1 } ],
    ]},
    email =>			{ textname => undef, fields => [
	[ 'pop_username',      	0, qr/^Username$/ ],
	[ 'pop_password',      	0, qr/^Password/ ],
	[ 'pop_server',      	1, qr/^POP3 Server$/ ],
	[ 'smtp_server',      	1, qr/^SMTP Server$/ ],
	[ 'smtp_username',     	0, qr/^SMTP Username$/ ],
	[ 'smtp_password',     	0, qr/^SMTP Password$/ ],
	[ 'emailstorager',     	1, qr/^Storage Space \(mb\)$/ ],
    ]},
    emergency =>		{ textname => undef, type_out => 'note', fields => [
	[ 'emergencyfire',     	1, qr/^Fire$/ ],
	[ 'emergencyambulance',	1, qr/^Ambulance$/ ],
	[ 'emergencypolice',	1, qr/^Police$/ ],
	[ 'emergencydoctor',	0, qr/^Doctor$/ ],
    ]},
    frequentflyer =>		{ textname => undef, type_out => 'rewards', fields => [
	[ 'company_name',     	1, qr/^Airline$/ ],
	[ 'membership_no',     	0, qr/^Account #$/ ],
	[ 'pin',     		0, qr/^PIN$/ ],
	[ 'ffstatus',     	1, qr/^Status$/ ],
	[ '_phone1',     	1, qr/^Phone #1$/ ],
	[ '_phone2',     	1, qr/^Phone #2$/ ],
	[ 'url',     		0, qr/^Web-Site$/,		{ type_out => 'login' } ],
	[ 'username',     	0, qr/^Username$/,		{ type_out => 'login' } ],
	[ 'password',     	0, qr/^Password$/,		{ type_out => 'login' } ],
    ]},
    healthinsurance =>		{ textname => undef, type_out => 'membership', fields => [
	[ '_polid',    		0, qr/^ID$/,			{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_string, 'policy ID' ] } ],
	[ '_grpid',    		1, qr/^Group$/,			{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_string, 'group ID' ] } ],
	[ '_plan',     		1, qr/^Plan$/,			{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_string, 'plan' ] } ],
	[ 'phone',     		0, qr/^Phone$/ ],
	[ '_sponsor',     	1, qr/^Sponsor$/,		{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_string, 'sponsor' ] } ],
    ]},
    idcard =>			{ textname => undef, type_out => 'membership', fields => [
	[ 'idtitle',		1, qr/^Title$/ ],
	[ 'org_name',		1, qr/^Organization$/ ],
	[ '_firstname',		0, qr/^First Name$/, ],		# see 'Fixup: combine names'
	[ '_lastname',		0, qr/^Last Name$/, ],		# see 'Fixup: combine names'
        [ 'member_name',        0, qr/^First \+ Last$/, ],	# see 'Fixup: combine names'; input never matches
	[ 'membership_no',	0, qr/^ID$/ ],
    ]},
    irc =>			{ textname => undef, type_out => 'server', fields => [
	[ 'url',		1, qr/^BNC Server$/ ],
	[ 'username',		1, qr/^User\/Ident$/ ],
	[ 'password',		0, qr/^Password$/ ],
	[ 'ircport',		0, qr/^Port$/ ],
    ]},
    insurance =>		{ textname => undef, type_out => 'membership', fields => [
	[ 'org_name',		0, qr/^Company$/ ],
	[ '_polnum',   		0, qr/^Policy #$/,		{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_string, 'policy num' ] } ],
	[ '_poltype',  		0, qr/^Type$/,			{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_string, 'policy type' ] } ],
	[ 'expiry_date',     	0, qr/^Expires$/,		{ func => sub { return date2monthYear($_[0], 2) }, keep => 1 } ],
	[ 'phone',     		0, qr/^Phone$/ ],
    ]},
    internet =>                 { textname => undef, type_out => 'email', fields => [
	[ 'provider',		0, qr/^Provider$/, ],
	[ 'ispemail',		0, qr/^Email$/, 		{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_string, 'email' ] } ],
	[ 'isplogin',		0, qr/^Login$/, 		{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_string, 'isp login' ] } ],
	[ 'isppassword',	0, qr/^Password$/, 		{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_concealed, 'isp password' ] } ],
	[ 'phone_local',	1, qr/^Dialup$/, ],
	[ 'ispdns1',		1, qr/^Primary DNS$/, ],
	[ 'ispdns2',		1, qr/^Alternate DNS$/, ],
	[ 'pop_server',		1, qr/^POP3$/, ],
	[ 'smtp_server',	1, qr/^SMTP$/, ],
	[ 'smtp_username',	0, qr/^SMTP Username$/, ],
	[ 'smtp_password',	0, qr/^SMTP Password$/, ],
	[ 'ispnntp_server',	1, qr/^NNTP$/, ],
    ]},
    lens =>                 	{ textname => undef, type_out => 'note', fields => [
	[ 'lenstype',		0, qr/^Type$/, ],
	[ 'lensright',		1, qr/^Right \(OD\)$/, ],
	[ 'lenslleft',		1, qr/^Left \(OS\)$/, ],
	[ 'lensdoctor',		0, qr/^Doctor$/, ],
	[ 'lensphone',		0, qr/^Phone Number$/, ],
    ]},
    librarycard =>		{ textname => undef, type_out => 'membership', fields => [
	[ 'org_name',		1, qr/^Library$/ ],
	[ 'membership_no',	0, qr/^Card #$/ ],
    ]},
    note =>                     { textname => undef, fields => [
    ]},
    passport =>                 { textname => undef, fields => [
	[ 'type',		0, qr/^Type$/, ],
	[ 'number',		0, qr/^Number$/, ],
	[ '_firstname',		0, qr/^First Name$/, ],		# see 'Fixup: combine names'
	[ '_lastname',		0, qr/^Last Name$/, ],		# see 'Fixup: combine names'
        [ 'fullname',           0, qr/^First \+ Last$/, ],	# see 'Fixup: combine names'; input never matches
	[ 'birthdate',		0, qr/^Birth Date$/,		{ func => sub { return date2epoch($_[0], 2) } } ],
	[ 'birthplace',		1, qr/^Place$/, ],
	[ 'nationality',	1, qr/^National$/, ],
	[ 'issue_date',		0, qr/^Issued$/, 		{ func => sub { return date2epoch($_[0], 2) } } ],
	[ 'expiry_date',	0, qr/^Expires$/, 		{ func => sub { return date2epoch($_[0], 2) } } ],
	[ 'issuing_authority',	1, qr/Authority/, ],
    ]},
    password =>                 { textname => undef, type_out => 'server', fields => [
	[ 'pwsystem',		1, qr/^System$/, 		{ to_title => 'value' } ],
	[ 'username',		0, qr/^Login$/, ],
	[ 'password',		0, qr/^Password$/, ],
	[ 'pwaccess',		1, qr/^Access$/, ],
    ]},
    prescription =>             { textname => undef, type_out => 'note', fields => [
	[ 'rxdrug',		1, qr/^Drug$/ ],
	[ 'rxamount',		1, qr/^Amount$/ ],
	[ 'rxdosage',		1, qr/^Take$/ ],
	[ 'rxbrand',		0, qr/^Brand$/ ],
	[ 'rxpurchasedate',	0, qr/^Purchased$/ ],
	[ 'rxpharmacy',		1, qr/^Pharmacy$/ ],
	[ 'rxdoctor',		0, qr/^Doctor$/ ],
	[ 'rxphone',		0, qr/^Phone$/ ],
    ]},
    serialnumber =>             { textname => undef, type_out => 'note', fields => [
	[ 'snproduct',		1, qr/^Product$/ ],
	[ 'snbrand',		0, qr/^Brand$/ ],
	[ 'snnum',		1, qr/^Serial #$/ ],
	[ 'snmodel',		1, qr/^Model #$/ ],
	[ 'snversion',		1, qr/^Version$/ ],
	[ 'snpurchasedate',	1, qr/^Purchase Date$/ ],
	[ 'snwebsite',		0, qr/^Web-Site$/ ],
    ]},
    server =>			{ textname => undef, type_out => 'server', fields => [
	[ 'url',		1, qr/^IP$/ ],
	[ 'ircport',		0, qr/^Port$/ ],
	[ 'username',		1, qr/^RCON$/ ],
    ]},
    socialsecurity =>           { textname => undef, fields => [
	[ '_firstname',		0, qr/^First Name$/, ],		# see 'Fixup: combine names'
	[ '_lastname',		0, qr/^Last Name$/, ],		# see 'Fixup: combine names'
        [ 'name',               0, qr/^First \+ Last$/, ],	# see 'Fixup: combine names'; input never matches
	[ 'number',		0, qr/^Number$/ ],
    ]},
    website =>                  { textname => undef, type_out => 'login', fields => [
	[ 'url',		1, qr/^URL$/, ],
	[ 'username',		0, qr/^Login$/, ],
	[ 'password',		0, qr/^Password$/, ],
    ]},
);

$DB::single = 1;					# triggers breakpoint when debugging

my @today = Date::Calc::Today();			# for date comparisons

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

    $_ = slurp_file($file);

    my $n = 1;

    my $xp = XML::XPath->new(xml => $_);

    my $cardnodes = $xp->findnodes('//Card[@Caption] | //T4[@Caption]');
    foreach my $cardnode (@$cardnodes) {
	my (%cmeta, @fieldlist, @groups);

	for (my $node = $cardnode->getParentNode(); $node->getName() =~ /^Folder|T3$/; $node = $node->getParentNode()) {
	    my $v = $node->getAttribute("Caption");
	    unshift @groups, $v   unless $v eq '';
	}
	if (@groups) {
	    push @{$cmeta{'tags'}}, join '::', @groups;
	    $cmeta{'folder'} = [ @groups ];
	    debug 'Group: ', $cmeta{'tags'}[-1];
	}

	$cmeta{'title'} = $xp->findvalue('@Caption', $cardnode)->value;
	debug "\tCard: ", $cmeta{'title'};

	my $iconnum = $xp->findvalue('@Icon', $cardnode)->value;
	debug "\t\ticon # : ", $iconnum;

	my $fav = $xp->findvalue('@Favorite', $cardnode)->value;
	if ($fav eq 'true') {
	    debug "\t\tfavorite: true";
	    push @{$cmeta{'tags'}}, 'Favorite'
	}

	if (my $fieldnodes = $xp->findnodes('*', $cardnode)) {
	    my $fieldindex = 1;;
	    foreach my $fieldnode (@$fieldnodes) {
		next if $fieldnode->getName() !~ /^Property|T\d+$/;
		# handle blank field labels;  type Note has none by default, but labels can be blanked by the user
		my $f = $fieldnode->getAttribute("Caption") || 'Field_' . $fieldindex;
		my $t = $fieldnode->getAttribute("Type") || $fieldnode->getName();
		my $v = $fieldnode->string_value;
		debug "\t\tfield: $f($t) -> $v";
		if ($t =~ /^Note|T267$/) {
		    if ($v ne '') {
			push @{$cmeta{'notes'}}, $f eq 'Note' ? $v : join ': ', $f, $v;
		    }
		}
		else {
		    push @fieldlist, [ $f => $v ];			# maintain the field order, in case destination is notes
		    $fieldindex++;
		}
	    }
	}

	my $itype = find_card_type(\@fieldlist, $iconnum);

	# skip all types not specifically included in a supplied import types list
	next if defined $imptypes and (! exists $imptypes->{$itype});

	# Fixup: combines address
	if ($itype eq 'address') {
	    my (%addr, @newfieldlist);
	    for (@fieldlist) {
		if ($_->[0] =~ /^City|State|Country|ZIP$/) {
		    $addr{lc $_->[0]} = $_->[1];
		}
		elsif ($_->[0] =~ /^Address #[123]$/) {
		    $addr{'street'} = myjoin ', ', $addr{'street'}, $_->[1];
		}
		else {
		    push @newfieldlist, $_;
		}
	    }
	    @fieldlist = @newfieldlist;
	    push @fieldlist, [ 'address' => \%addr ]		if keys %addr;
	}

	# Fixup: combine names
	if ($itype =~ /^idcard|creditcard|passport|socialsecurity$/ and (my @found = grep($_->[0] =~ /^First Name|Last Name$/, @fieldlist)) == 2) {
	    push @fieldlist, [ 'First + Last' =>  myjoin(' ',  $found[0][1], $found[1][1]) ];
	    debug "\t\tfield added: $fieldlist[-1][0] -> $fieldlist[-1][1]";
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

sub find_card_type {
    my $fieldlist = shift;
    my $iconnum = shift;
    my $type = 'note';

    for $type (sort by_test_order keys %card_field_specs) {
	for my $cfs (@{$card_field_specs{$type}{'fields'}}) {
	    next unless $cfs->[CFS_TYPEHINT] and defined $cfs->[CFS_MATCHSTR];
	    for (@$fieldlist) {
		# type hint
		if ($_->[0] =~ $cfs->[CFS_MATCHSTR]) {
		    debug "\t\ttype detected as '$type' (key='$_->[0]')";
		    return $type;
		}
	    }
	}
    }

    if (grep($_->[0] =~ /^Company|Policy #|Type$/, @$fieldlist) >= 2) {
	debug "\t\ttype detected as 'insurance'";
	return 'insurance';
    }

    # socialsecurity fields are ambiguous with those of passport
    if (grep($_->[0] =~ /^First Name|Last Name|Number$/, @$fieldlist) == 3 and
        ! grep($_->[0] =~ /^Type|Authority|Issued|Expires|Place$/, @$fieldlist)) {
	debug "\t\ttype detected as 'socialsecurity'";
	return 'socialsecurity';
    }

    $type = grep($_->[0] eq 'Password', @$fieldlist) ? 'login' : 'note';

    debug "\t\ttype defaulting to '$type'";
    return $type;
}

# sort logins as the last to check
sub by_test_order {
    return  1 if $a eq 'login';
    return -1 if $b eq 'login';
    $a cmp $b;
}

# Date converters
# Safewallet validates date input on Date types
#    SafeWallet 2:	 yyyy-mm-dd hh:mm:ss
#    SafeWallet 3:	 yyyymmddhhmmss
sub parse_date_string {
    local $_ = $_[0];
    my $when = $_[1] || 0;					# -1 = past only, 0 = assume this century, 1 = future only, 2 = 50-yr moving window

    if (/^(?<y>\d{4})-?(?<m>\d{2})-?(?<d>\d{2})(?:\s|\d)/) {	# yyyy-mm-dd or yyyymmdd
	my $m = sprintf "%02d", $+{'m'};
	my $d = sprintf "%02d", $+{'d'};
	if (check_date($+{'y'}, $m, $d)) {
	    return ($+{'y'}, $m, $d);
	}
    }

    return undef;
}

sub date2monthYear {
    my ($y, $m, $d) = parse_date_string @_;
    return defined $y ? $y . $m	: $_[0];
}

sub date2epoch {
    my ($y, $m, $d) = parse_date_string @_;
    return defined $y ? timelocal(0, 0, 3, $d, $m - 1, $y): $_[0];
}

1;
