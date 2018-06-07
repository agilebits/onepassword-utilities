# Enpass CSV export converter
#
# Copyright 2018 Mike Cappella (mike@cappella.us)

package Converters::Enpass 1.00;

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

use Text::CSV;

my %card_field_specs = (
    bankacct =>			{ textname => '', fields => [
	[ 'bankName',		1, qr/^Bank name$/, ],
	[ 'owner',		1, qr/^Account holder$/, ],
	[ 'accountType',	0, qr/^Type$/, ],
	[ 'accountNo',		0, qr/^Account number$/, ],
	[ '_customerid',	0, qr/^Customer ID$/, ],
	[ 'routingNo',		1, qr/^Routing number$/, ],
	[ '_branchname',	1, qr/^Branch name$/, ],
	[ '_branchcode',	1, qr/^Branch code$/, ],
	[ 'branchAddress',	1, qr/^Branch address$/, ],
	[ 'branchPhone',	1, qr/^Branch phone$/, ],
	[ 'swift',		1, qr/^SWIFT$/, ],
	[ 'iban',		1, qr/^IBAN$/, ],
	[ 'ccnum',		1, qr/^Debit Card number$/,	{ type_out => 'creditcard', to_title => sub {' (debit card ' . last4($_[0]->{'value'}) . ')'} }  ],
	[ 'type',		0, qr/^Type___\d+$/, 		{ type_out => 'creditcard' } ], # avoid duplicate: Type
	[ 'pin',		0, qr/^PIN$/,			{ type_out => 'creditcard' } ],
	[ 'cvv',		1, qr/^CVV$/, 			{ type_out => 'creditcard' } ],
	[ '_expiry',		0, qr/^Expiry date$/, 		{ type_out => 'creditcard' } ],
	[ 'cashLimit',		0, qr/^Withdrawal limit$/, 	{ type_out => 'creditcard' } ],
	[ 'phoneLocal',		0, qr/^Helpline$/,		{ type_out => 'creditcard' } ],
	[ '_tpin',		1, qr/^T-PIN$/, ],
	[ 'url',		0, qr/^Website$/,		{ type_out => 'login' } ],
	[ 'username',		0, qr/^Username$/,		{ type_out => 'login' } ],
	[ 'password',		0, qr/^Login password$/,	{ type_out => 'login' } ],
    ]},
    combinationlock =>          { textname => undef, type_out => 'note', fields => [
        [ 'combolocation',      2, 'Location' ],
        [ '_code',          	2, 'Code',		{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_concealed, 'password', 'generate'=>'off' ] } ],
    ]},
    creditcard =>		{ textname => '', fields => [
	[ 'cardholder',		1, qr/^Cardholder$/, ],
	[ 'type',		0, qr/^Type$/, ],
	[ 'ccnum',		0, qr/^Number$/, ],
	[ 'cvv',		1, qr/^CVC$/, ],
	[ 'pin',		0, qr/^PIN$/, ],
	[ '_expiry',		0, qr/^Expiry date$/, ],
	[ '_validfrom',		0, qr/^Valid from$/, ],
	[ 'creditLimit',	1, qr/^Credit limit$/, ],
	[ 'cashLimit',		0, qr/^Withdrawal limit$/, ],
	[ 'interest',		0, qr/^Interest rate$/, ],
	[ 'bank',		1, qr/^Issuing bank$/, ],
	[ '_tpassword',		1, qr/^Transaction password$/, ],
	[ '_issuedon',		0, qr/^Issued on$/, ],
	[ '_iflostphone',	0, qr/^If lost, call$/, ],
	[ 'url',		0, qr/^Website$/,		{ type_out => 'login' } ],
	[ 'username',		0, qr/^Username$/,		{ type_out => 'login' } ],
	[ 'password',		0, qr/^Password$/,		{ type_out => 'login' } ],
    ]},
    database =>			{ textname => '', fields => [
	[ 'database_type',	0, qr/^Type$/, ],
	[ 'hostname',		0, qr/^Server$/, ],
	[ 'port',		0, qr/^Port$/, ],
	[ 'database',		0, qr/^Database$/, ],
	[ 'username',		0, qr/^Username$/, ],
	[ 'password',		0, qr/^Password$/, ],
	[ 'sid',		1, qr/^SID$/, ],
	[ 'alias',		1, qr/^Alias$/, ],
	[ 'options',		1, qr/^Options$/, ],
    ]},
    driverslicense =>		{ textname => '', fields => [
	[ 'number',		0, qr/^Number$/, ],
	[ 'fullname',		0, qr/^Name$/, ],
	[ 'sex',		0, qr/^Sex$/, ],
	[ '_birthdate',		1, qr/^Birth date$/, ],
	[ 'address',		0, qr/^Address$/, ],
	[ 'height',		1, qr/^Height$/, ],
	[ 'class',		1, qr/^Class$/, ],
	[ 'conditions',		1, qr/^Restrictions$/, ],
	[ 'state',		0, qr/^State$/, ],
	[ 'country',		0, qr/^Country$/, ],
	[ '_expiry_date',	0, qr/^Expiry date$/, ],
	[ '_issuedon',		0, qr/^Issued on$/, ],
	[ '_iflostcall',	0, qr/^If lost, call$/, ],
    ]},
    email =>			{ textname => '', fields => [
	[ '_email',		0, qr/^Email$/, ],
	[ 'pop_username',	0, qr/^Username$/, ],
	[ 'pop_password',	0, qr/^Password$/, ],
	[ 'pop_type',		0, qr/^Type$/, ],
	[ 'pop_server',		1, qr/^POP3 server$/, ],
	[ 'imap_server',	1, qr/^IMAP server$/, ],
	[ 'pop_port',		0, qr/^Port$/, ],
	[ 'pop_security',	1, qr/^Security type$/, ],
	[ 'pop_authentication',	1, qr/^Auth\. method$/, ],
	[ '_weblink',		1, qr/^Weblink$/, ],
	[ 'smtp_server',	1, qr/^SMTP server$/, ],
	[ 'smtp_port',		0, qr/^Port___\d+$/, ],
	[ 'smtp_username',	0, qr/^Username___\d+$/, ],
	[ 'smtp_password',	0, qr/^Password___\d+$/, ],
	[ 'smtp_security',	0, qr/^Security type___\d+$/, ],
	[ 'smtp_authentication',0, qr/^Auth\. method___\d+$/, ],
	[ 'provider',		0, qr/^Provider$/, ],
	[ 'provider_website',	0, qr/^Website$/, ],
	[ 'phone_local',	0, qr/^Local phone$/, ],
	[ '_helpline',		0, qr/^Helpline$/, ],
    ]},
    flightdetail =>		{ textname => '', type_out => 'note', fields => [
	[ '_flightnum',		1, qr/^Flight number$/, ],
	[ '_airline',		0, qr/^Airline$/, ],
	[ '_date',		0, qr/^Date$/, ],
	[ '_from',		0, qr/^From$/, ],
	[ '_to',		0, qr/^To$/, ],
	[ '_timegate',		1, qr/^Time\/Gate$/, ],
	[ '_eticket',		1, qr/^E-Ticket number$/, ],
	[ '_confirmnum',	1, qr/^Confirm #$/, ],
	[ '_phone',		0, qr/^Phone$/, ],
	[ 'url',		0, qr/^Website$/,		{ type_out => 'login' } ],
	[ 'username',		0, qr/^Username$/,		{ type_out => 'login' } ],
	[ 'password',		0, qr/^Password$/,		{ type_out => 'login' } ],
    ]},
    frequentflyer =>		{ textname => '', type_out => 'rewards', fields => [
	[ 'membership_no',	1, qr/^Membership No\.$/, ],
	[ 'member_name',	0, qr/^Name$/, ],
	[ 'company_name',	0, qr/^Airline$/, ],
	[ '_date',		0, qr/^Date$/, ],
	[ '_mileage',		1, qr/^Mileage$/, ],
	[ 'customer_service_phone',1, qr/^Customer service$/, ],
	[ 'url',		0, qr/^Website$/,		{ type_out => 'login' } ],
	[ 'username',		0, qr/^Username$/,		{ type_out => 'login' } ],
	[ 'password',		0, qr/^Password$/,		{ type_out => 'login' } ],
    ]},
    ftp =>			{ textname => '', type_out => 'server', fields => [
	[ 'url',		0, qr/^Server$/, ],
	[ '_path',		1, qr/^Path$/, ],
	[ 'username',		0, qr/^Username$/, ],
	[ 'password',		0, qr/^Password$/, ],
	[ 'website',		0, qr/^Website$/, ],
	[ 'support_contact_phone',0, qr/^Phone$/, ],
	[ 'name',		0, qr/^Provider$/, ],

    ]},
    hotelreservations =>	{ textname => '', type_out => 'note', fields => [
	[ '_hotelname',		1, qr/^Hotel name$/, ],
	[ '_roomnum',		1, qr/^Room number$/, ],
	[ '_address',		0, qr/^Address$/, ],
	[ '_reservationid',	1, qr/^Reservation ID$/, ],
	[ '_date',		0, qr/^Date$/, ],
	[ '_nights',		1, qr/^Nights$/, ],
	[ '_hotelreward',	1, qr/^Hotel reward$/, ],
	[ '_phone',		0, qr/^Phone$/, ],
	[ '_email',		0, qr/^Email$/, ],
	[ '_concierge',		1, qr/^Concierge$/, ],
	[ '_restaurant',	1, qr/^Restaurant$/, ],
	[ 'url',		0, qr/^Website$/,		{ type_out => 'login' } ],
	[ 'username',		0, qr/^Username$/,		{ type_out => 'login' } ],
	[ 'password',		0, qr/^Password$/,		{ type_out => 'login' } ],
    ]},
    instantmsg =>		{ textname => '', type_out => 'login', fields => [
	[ '_type',		0, qr/^Type$/, ],
	[ '_id',		1, qr/^ID$/, ],
	[ 'url',		0, qr/^Server$/, ],
	[ '_port',		0, qr/^Port$/, ],
	[ '_nickname',		1, qr/^Nick name$/, ],
	[ 'username',		0, qr/^Username$/, ],
	[ 'password',		0, qr/^Password$/, ],
    ]},
    insurance =>		{ textname => '', text_out => 'note', fields => [
	[ '_policyname',	1, qr/^Policy name$/, ],
	[ '_company',		0, qr/^Company$/, ],
	[ '_policyholder',	1, qr/^Policy holder$/, ],
	[ '_number',		0, qr/^Number$/, ],
	[ '_type',		0, qr/^Type$/, ],
	[ '_premium',		1, qr/^Premium$/, ],
	[ '_sum_assured',	1, qr/^Sum assured$/, ],
	[ '_issuedate',		0, qr/^Issue date$/, ],
	[ '_renewaldate',	1, qr/^Renewal date$/, ],
	[ '_expirydate',	0, qr/^Expiry date$/, ],
	[ '_term',		0, qr/^Term$/, ],
	[ '_nominee',		1, qr/^Nominee$/, ],
	[ '_customerid',	0, qr/^Customer ID$/, ],
	[ '_agentname',		1, qr/^Agent name$/, ],
	[ '_helpline',		0, qr/^Helpline$/, ],
	[ 'url',		0, qr/^Website$/,		{ type_out => 'login' } ],
	[ 'username',		0, qr/^Username$/,		{ type_out => 'login' } ],
	[ 'password',		0, qr/^Password$/,		{ type_out => 'login' } ],
    ]},
    isp =>			{ textname => '', type_out => 'note', fields => [
	[ '_username',		0, qr/^Username$/, ],
	[ '_password',		0, qr/^Password$/, ],
	[ '_dialupphone',	1, qr/^Dialup phone$/, ],
	[ '_isp_system',	1, qr/^ISP\/System$/, ],
	[ '_ip_address',	0, qr/^IP address$/, ],
	[ '_subnetmask',	1, qr/^Subnet mask$/, ],
	[ '_gateway',		1, qr/^Gateway$/, ],
	[ '_primarydns',	1, qr/^Primary DNS$/, ],
	[ '_secondarydns',	1, qr/^Secondary DNS$/, ],
	[ '_wins',		1, qr/^WINS$/, ],
	[ '_smtp',		1, qr/^SMTP$/, ],
	[ '_pop3',		1, qr/^POP3$/, ],
	[ '_nntp',		1, qr/^NNTP$/, ],
	[ '_ftp',		0, qr/^FTP$/, ],
	[ '_telnet',		1, qr/^Telnet$/, ],
	[ '_helpline',		0, qr/^Helpline$/, ],
	[ '_website',		0, qr/^Website$/, ],
	[ '_billinginfo',	0, qr/^Billing info$/, ],
    ]},
    loanmort =>		{ textname => '', text_out => 'note', fields => [
	[ '_lender',		1, qr/^Lender$/, ],
	[ '_type',		0, qr/^Type$/, ],
	[ '_accountnum',	0, qr/^Account number$/, ],
	[ '_principal',		1, qr/^Principal$/, ],
	[ '_interest',		1, qr/^Interest %$/, ],
	[ '_date',		0, qr/^Date$/, ],
	[ '_term',		0, qr/^Term$/, ],
	[ '_balanace',		1, qr/^Balance$/, ],
	[ '_paymentdue',	1, qr/^Payment due$/, ],
	[ '_asset',		1, qr/^Asset$/, ],
	[ '_phone',		0, qr/^Phone$/, ],
	[ 'url',		0, qr/^Website$/,		{ type_out => 'login' } ],
	[ 'username',		0, qr/^Username$/,		{ type_out => 'login' } ],
	[ 'password',		0, qr/^Password$/,		{ type_out => 'login' } ],
    ]},
    login =>			{ textname => '', fields => [
	[ 'username',		3, qr/^Username$/, ],
	[ 'password',		3, qr/^Password$/, ],
	[ 'url',		3, qr/^URL$/, ],
	[ '_phone',		0, qr/^Phone$/, ],
	[ '_securityquestion',	3, qr/^Security question$/, ],
    ]},
    membership =>		{ textname => '', fields => [
	[ 'membership_no',	0, qr/^Member ID$/, ],
	[ 'member_name',	1, qr/^Member name$/, ],
	[ 'org_name',		1, qr/^Organization$/, ],
	[ '_group',		1, qr/^Group$/, ],
	[ 'pin',		0, qr/^PIN$/, ],
	[ 'phone',		0, qr/^Phone$/, ],
	[ '_member_since',	1, qr/^Member since$/, ],
	[ '_expiry_date',	0, qr/^Expiry date$/, ],
	[ '_email',		0, qr/^Email$/, ],
	[ 'url',		0, qr/^Website$/,		{ type_out => 'login', keep => 1 } ],
	[ 'username',		0, qr/^Username$/,		{ type_out => 'login' } ],
	[ 'password',		0, qr/^Password$/,		{ type_out => 'login' } ],
	[ '_iflostcall',	0, qr/^If lost, call$/, ],
    ]},
    mutualfund =>		{ textname => '', text_out => 'note', fields => [
	[ '_fundname',		1, qr/^Fund name$/, ],
	[ '_fundtype',		1, qr/^Fund type$/, ],
	[ '_launchedon',	0, qr/^Launched on$/, ],
	[ '_purchasedon',	0, qr/^Purchased on$/, ],
	[ '_quantity',		0, qr/^Quantity$/, ],
	[ '_puchasednav',	1, qr/^Purchased NAV$/, ],
	[ '_currentnav',	1, qr/^Current NAV$/, ],
	[ '_broker',		0, qr/^Broker$/, ],
	[ '_brokerphone',	0, qr/^Phone$/, ],
	[ 'url',		0, qr/^Website$/,		{ type_out => 'login' } ],
	[ 'username',		0, qr/^Username$/,		{ type_out => 'login' } ],
	[ 'password',		0, qr/^Password$/,		{ type_out => 'login' } ],
    ]},
    note =>			{ textname => 'Note', fields => [
    ]},
    other =>		{ textname => '', text_out => 'note', fields => [
	[ '_field1',		2, qr/^Field 1$/, ],
	[ '_field2',		2, qr/^Field 2$/, ],
    ]},
    outdoorlicense =>		{ textname => '', fields => [
	[ 'number',		0, qr/^Number$/, ],
	[ 'name',		0, qr/^Name$/, ],
	[ 'state',		0, qr/^State$/, ],
	[ '_region',		1, qr/^Region$/, ],
	[ 'country',		0, qr/^Country$/, ],
	[ '_validfrom',		0, qr/^Valid from$/, ],
	[ '_expires',		0, qr/^Expiry date$/, ],
	[ 'game',		1, qr/^Approved wildlife$/, ],
	[ 'quota',		1, qr/^Quota$/, ],
    ]},
    passport =>	{ textname => '', fields => [
	[ 'number',		0, qr/^Number$/, ],
	[ 'fullname',		0, qr/^Full name$/, ],
	[ 'sex',		0, qr/^Sex$/, ],
	[ 'type',		0, qr/^Type$/, ],
	[ 'nationality',	1, qr/^Nationality$/, ],
	[ 'birthplace',		1, qr/^Birth place$/, ],
	[ '_birthdate',		1, qr/^Birthday$/, ],
	[ '_issued_at',		1, qr/^Issued at$/, ],
	[ '_issue_date',	0, qr/^Issued on$/, ],
	[ '_expiry_date',	0, qr/^Expiry date$/, ],
	[ 'issuing_country',	1, qr/^Issuing country$/, ],
	[ 'issuing_authority',	1, qr/^Authority$/, ],
	[ '_replacements',	1, qr/^Replacements$/, ],
	[ '_iflostcall',	0, qr/^If lost, call$/, ],
    ]},
    password =>			{ textname => '', type_out => 'login', fields => [
	[ 'username',		0, qr/^Login$/, ],
	[ 'password',		0, qr/^Password$/, ],
	[ '_access',		1, qr/^Access$/, ],
    ]},
    rewards =>			{ textname => '', fields => [
	[ 'company_name',	0, qr/^Company$/, ],
	[ 'member_name',	0, qr/^Name$/, ],
	[ '_memberid',		0, qr/^Member ID$/, ],
	[ 'membership_no',	0, qr/^Number$/, ],
	[ 'pin',		0, qr/^PIN$/, ],
	[ 'additional_no',	1, qr/^Number 2$/, ],
	[ '_member_since',	1, qr/^Since$/, ],
	[ 'customer_service_phone',0, qr/^Helpline$/, ],
	[ 'reservations_phone',	1, qr/^Reservations phone$/, ],
	[ 'website',		0, qr/^Website$/, ],
    ]},
    server =>			{ textname => '', fields => [
	[ 'admin_console_username', 0, qr/^Admin login$/, ],
	[ 'admin_console_password', 0, qr/^Admin password$/, ],
	[ 'admin_console_url',	0, qr/^Admin URL$/, ],
	[ '_service',		1, qr/^Service$/, ],
	[ '_tasks',		1, qr/^Tasks$/, ],
	[ '_os',		0, qr/^OS$/, ],
	[ '_ram',		1, qr/^RAM$/, ],
	[ '_storage',		1, qr/^Storage$/, ],
	[ '_cpu',		1, qr/^CPU$/, ],
	[ '_raid',		1, qr/^RAID$/, ],
	[ '_location',		0, qr/^Location$/, ],
	[ '_ipaddress',		0, qr/^IP address$/, ],
	[ '_dns',		0, qr/^DNS$/, ],
	[ '_port',		0, qr/^Port$/, ],
	[ 'name',		0, qr/^Hosting provider$/, ],
	[ 'support_contact_url',0, qr/^Support website$/, ],
	[ 'support_contact_phone', 0, qr/^Helpline$/, ],
	[ '_billinginfo',	0, qr/^Billing info$/, ],
    ]},
    socialsecurity =>		{ textname => '', fields => [
	[ 'number',		3, qr/^Number$/, ],
	[ 'name',		3, qr/^Name$/, ],
	[ '_date',		3, qr/^Date$/, ],
    ]},
    software =>			{ textname => '', fields => [
	[ 'product_version',	0, qr/^Version$/, ],
	[ '_product_name',	1, qr/^Product name$/,		{ to_title => 'value' } ],
	[ '_numusers',		1, qr/^No\. of users$/, ],
	[ 'reg_code',		1, qr/^Key$/, ],
	[ 'download_link',	1, qr/^Download page$/, ],
	[ 'reg_name',		1, qr/^Licensed to$/, ],
	[ 'reg_email',		0, qr/^Email$/, ],
	[ 'company',		0, qr/^Company$/, ],
	[ '_order_date',	1, qr/^Purchase date$/, ],
	[ 'order_number',	1, qr/^Order number$/, ],
	[ 'retail_price',	1, qr/^Retail price$/, ],
	[ 'order_total',	0, qr/^Total$/, ],
	[ 'publisher_name',	1, qr/^Publisher$/, ],
	[ 'publisher_website',	0, qr/^Website$/, ],
	[ 'support_email',	0, qr/^Support Email$/, ],
	[ '_helpline',		0, qr/^Helpline$/, ],
	[ 'url',		0, qr/^Login page$/,		{ type_out => 'login' } ],
	[ 'username',		0, qr/^Username$/,		{ type_out => 'login' } ],
	[ 'password',		0, qr/^Password$/,		{ type_out => 'login' } ],
    ]},
    stockinvestment =>		{ textname => '', text_out => 'note', fields => [
	[ '_symbol',		1, qr/^Symbol$/, ],
	[ '_accountnum',	0, qr/^Account number$/, ],
	[ '_type',		0, qr/^Type$/, ],
	[ '_market',		1, qr/^Market$/, ],
	[ '_launchedon',	0, qr/^Launched on$/, ],
	[ '_purchasedon',	0, qr/^Purchased on$/, ],
	[ '_purchasedprice',	0, qr/^Purchase price$/, ],
	[ '_quantity',		0, qr/^Quantity$/, ],
	[ '_currentprice',	1, qr/^Current price$/, ],
	[ '_broker',		0, qr/^Broker$/, ],
	[ '_brokerphone',	0, qr/^Phone$/, ],
	[ 'url',		0, qr/^Website$/,		{ type_out => 'login' } ],
	[ 'username',		0, qr/^Username$/,		{ type_out => 'login' } ],
	[ 'password',		0, qr/^Password$/,		{ type_out => 'login' } ],
    ]},
    travellingvisa =>		{ textname => '', type_out => 'note', fields => [
	[ '_type',		0, qr/^Type$/, ],
	[ '_country',		0, qr/^Country$/, ],
	[ '_fullname',		0, qr/^Full name$/, ],
	[ '_number',		0, qr/^Number$/, ],
	[ '_validfor',		1, qr/^Valid for$/, ],
	[ '_validfrom',		0, qr/^Valid from$/, ],
	[ '_validuntil',	1, qr/^Valid until$/, ],
	[ '_duration',		1, qr/^Duration$/, ],
	[ '_numentries',	1, qr/^No\. of entries$/, ],
	[ '_issued_by',		1, qr/^Issued by$/, ],
	[ '_issued_date',	0, qr/^Issue date$/, ],
	[ '_passportnum',	1, qr/^Passport number$/, ],
	[ '_remarks',		1, qr/^Remarks$/, ],
	[ '_iflostcall',	0, qr/^If lost, call$/, ],
    ]},
    webhosting =>		{ textname => '', type_out => 'server', fields => [
	[ 'name',		0, qr/^Provider$/, ],
	[ 'username', 		0, qr/^Username$/, ],
	[ 'password', 		0, qr/^Password$/, ],
	[ 'admin_console_url',	0, qr/^Admin URL$/, ],
	[ '_os',		0, qr/^OS$/, ],
	[ '_customerid',	0, qr/^Customer ID$/, ],
	[ '_http',		1, qr/^HTTP$/, ],
	[ '_ftp',		0, qr/^FTP$/, ],
	[ '_database',		0, qr/^Database$/, ],
	[ '_services',		1, qr/^Services$/, ],
	[ 'support_contact_url',0, qr/^Support website$/, ],
	[ '_helpline',		0, qr/^Helpline$/, ],
	[ '_fee',		1, qr/^Fee$/, ],
    ]},
    wireless =>			{ textname => '', fields => [
	[ 'name',		1, qr/^Station name$/, ],
	[ 'password',		1, qr/^Station password$/, ],
	[ 'network_name',	1, qr/^Network name$/, ],
	[ 'wireless_password',	1, qr/^Network password$/, ],
	[ 'wireless_security',	0, qr/^Security$/, ],
	[ 'airport_id',		1, qr/^Mac\/Airport #$/, ],
	[ 'server',		1, qr/^Server\/IP address$/, ],
	[ '_username',		0, qr/^Username$/, ],
	[ '_password',		0, qr/^Password$/, ],
	[ 'disk_password',	1, qr/^Storage password$/, ],
	[ '_website',		0, qr/^Support website$/, ],
	[ '_billinginfo',	0, qr/^Billing info$/, ],
    ]},
);

$DB::single = 1;					# triggers breakpoint when debugging

sub do_init {
    return {
	'specs'		=> \%card_field_specs,
	'imptypes'  	=> undef,
        'opts'          => [],
    }
}

sub do_import {
    my ($file, $imptypes) = @_;

    my $csv = Text::CSV->new ({
	    binary => 1,
	    sep_char => ',',
	    eol => "\n",
    });

    open my $io, "<:encoding(utf8)", $file
	or bail "Unable to open CSV file: $file\n$!";

=cut
    # remove BOM
    my $bom;
    (my $nb = read($io, $bom, 1) == 1 and $bom eq "\x{FEFF}") or
	bail "Failed to read BOM from CSV file: $file\n$!";
=cut
    my $column_names;

    my %Cards;
    my ($n, $rownum) = (1, 1);

    while (my $row = $csv->getline($io)) {
	debug 'ROW: ', $rownum;
	if ($rownum++ == 1 and join('_', @$row) =~ /^Title_(?:Field_Value_)+[.]+_Note$/) {
	    debug "Skipping header row";
	    next;
	}

	my (@fieldlist, %cmeta);
	$cmeta{'title'} = shift @$row;
	$cmeta{'notes'} = pop @$row;
	# Everything that remains in the row is the field data as label/value pairs
	my %labels_found;
	while (my $label = shift @$row) {
	    my $value = shift @$row;

	    # make labels unique - there are many dups
	    if (exists $labels_found{$label}) {
		my $newlabel = join '___', $label, ++$labels_found{$label};
		debug "\tfield: $newlabel => $value (original label: $label)";
		$label = $newlabel
	    }
	    else {
		debug "\tfield: $label => $value";
		$labels_found{$label}++;
	    }
	    push @fieldlist, [ $label => $value ];		# retain field order
	}

	my $itype = find_card_type(\@fieldlist);

	next if defined $imptypes and (! exists $imptypes->{$itype});

	my $normalized = normalize_card_data(\%card_field_specs, $itype, \@fieldlist, \%cmeta);
	my $cardlist   = explode_normalized($itype, $normalized);

	for (keys %$cardlist) {
	    print_record($cardlist->{$_});
	    push @{$Cards{$_}}, $cardlist->{$_};
	}
	$n++;
    }
    if (! $csv->eof()) {
	warn "Unexpected failure parsing CSV: row $n";
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

    my $type;
    for $type (sort by_test_order keys %card_field_specs) {
	my ($nfound, @found);
	for my $cfs (@{$card_field_specs{$type}{'fields'}}) {
	    next unless $cfs->[CFS_TYPEHINT] and defined $cfs->[CFS_MATCHSTR];
	    for (@$fieldlist) {
		# type hint, requires matching the specified number of fields
		if ($_->[0] =~ $cfs->[CFS_MATCHSTR]) {
		    $nfound++;
		    push @found, $_->[0];
		    if ($nfound == $cfs->[CFS_TYPEHINT]) {
			debug sprintf "type detected as '%s' (%s: %s)", $type, pluralize('key', scalar @found), join('; ', @found);
			return $type;
		    }
		}
	    }
	}
    }

    $type = grep($_->[0] eq 'Password', @$fieldlist) ? 'login' : 'note';

    debug "\t\ttype defaulting to '$type'";
    return $type;
}

# sort logins as the last to check
sub by_test_order {
    return  1 if $a eq 'password';
    return -1 if $b eq 'password';
    return  1 if $a eq 'login';
    return -1 if $b eq 'login';
    $a cmp $b;
}

sub last4 {
    local $_ = shift;
    s/[- ._:]//;
    /(.{4})$/;
    return $1;
}

1;
