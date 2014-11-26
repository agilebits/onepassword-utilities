# LassPass CSV export converter
#
# Copyright 2014 Mike Cappella (mike@cappella.us)

package Converters::Lastpass 1.00;

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
use Text::CSV;
use Time::Local qw(timelocal);
use Date::Calc qw(check_date Decode_Month Date_to_Days);

# note: the second field, the type hint indicator (e.g. $card_field_specs{$type}[$i][1]}),
# is not used, but remains for code-consisency with other converter modules.
#

=cut
Generic
=cut

my %card_field_specs = (
    ##XXX recheck each type - use lastpass defined types, not type-out types
    bankacct => 		{ textname => undef, fields => [
	[ 'cardtype',		0, qr/^NoteType:(Bank Account)(?:\x{0a}|\Z)/ms ],
	[ 'bankName',		0, qr/^(Bank Name):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'accountType',	0, qr/^(Account Type):([^\x{0a}]+)(?:\x{0a}|\Z)/ms,	{ func => sub {return bankstrconv($_[0])} } ],
	[ 'routingNo',		0, qr/^(Routing Number):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'accountNo',		0, qr/^(Account Number):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'swift',		0, qr/^(SWIFT Code):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'iban',		0, qr/^(IBAN Number):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'telephonePin',	0, qr/^(Pin):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'branchAddress',	0, qr/^(Branch Address):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'branchPhone',	0, qr/^(Branch Phone):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ]},
    creditcard => 		{ textname => undef, fields => [
	[ 'cardtype',		0, qr/^NoteType:(Credit Card)(?:\x{0a}|\Z)/ms ],
	[ 'cardholder',		0, qr/^(Name on Card):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'type',		0, qr/^(Type):([^\x{0a}]+)(?:\x{0a}|\Z)/ms,		{ func => sub{return lc $_[0]} } ],
	[ 'ccnum',		0, qr/^(Number):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'cvv',		0, qr/^(Security Code):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'validFrom',		0, qr/^(Start Date):([^\x{0a}]+)(?:\x{0a}|\Z)/ms,	{ func => sub {return date2monthYear($_[0], 2)} } ],
	[ 'expiry',		0, qr/^(Expiration Date):([^\x{0a}]+)(?:\x{0a}|\Z)/ms,	{ func => sub {return date2monthYear($_[0], 2)} } ],
    ]},
    database => 		{ textname => undef, fields => [
	[ 'cardtype',		0, qr/^NoteType:(Database)(?:\x{0a}|\Z)/ms ],
	[ 'database_type',	0, qr/^(Type):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'hostname',		0, qr/^(Hostname):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'port',		0, qr/^(Port):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'database',		0, qr/^(Database):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'username',		0, qr/^(Username):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'password',		0, qr/^(Password):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'sid',		0, qr/^(SID):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'alias',		0, qr/^(Alias):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ]},
    driverslicense => 		{ textname => undef, fields => [
	[ 'cardtype',		0, qr/^NoteType:(Driver's License)(?:\x{0a}|\Z)/ms ],
	[ 'number',		0, qr/^(Number):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'expiry_date',	0, qr/^(Expiration Date):([^\x{0a}]+)(?:\x{0a}|\Z)/ms,	{ func => sub {return date2monthYear($_[0], 2)}, keep => 1 } ],
	[ 'class',		0, qr/^(License Class):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'fullname',		0, qr/^(Name):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'address',		0, qr/^(Address):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'city',		0, qr/^(City \/ Town):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'state',		0, qr/^(State):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'zip',		0, qr/^(ZIP \/ Postal Code):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'country',		0, qr/^(Country):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'birthdate',		0, qr/^(Date of Birth):([^\x{0a}]+)(?:\x{0a}|\Z)/ms,	{ func => sub {return date2epoch($_[0], -1)} } ],
	[ 'sex',		0, qr/^(Sex):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'height',		0, qr/^(Height):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ]},
    email => 			{ textname => undef, fields => [
	[ 'cardtype',		0, qr/^NoteType:(Email Account)(?:\x{0a}|\Z)/ms ],
	[ 'pop_username',	0, qr/^(Username):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'pop_password',	0, qr/^(Password):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'pop_server',		0, qr/^(Server):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'pop_port',		0, qr/^(Port):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'pop_type',		0, qr/^(Type):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'smtp_server',	0, qr/^(SMTP Server):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'smtp_port',		0, qr/^(SMTP Port):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ]},
    healthinsurance => 		{ textname => undef, type_out => 'membership', fields => [
	[ 'cardtype',		0, qr/^NoteType:(Health Insurance)(?:\x{0a}|\Z)/ms ],
	[ 'org_name',		0, qr/^(Company):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'phone',		0, qr/^(Company Phone):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'poltype',		0, qr/^(Policy Type):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'polid',		0, qr/^(Policy Number):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'grpid',		0, qr/^(Group ID):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'member_name',	0, qr/^(Member Name):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'membership_no',	0, qr/^(Member ID):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'physician',		0, qr/^(Physician Name):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'physicianphone',	0, qr/^(Physician Phone):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'physicianaddr',	0, qr/^(Physician Address):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'copay',		0, qr/^(Co-pay):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ]},
    identity =>			{ textname => undef, type_out => 'identity', fields => [		# special handling
	[ 'cardtype',		0, undef ],
	[ 'language', 		0, qr/^profilelanguage$/ ],
	[ 'title', 		0, qr/^title$/ ],
	[ 'firstname', 		0, qr/^firstname$/ ],
	[ 'firstname2', 	0, qr/^firstname2$/ ],
	[ 'firstname3', 	0, qr/^firstname3$/ ],
	[ 'initial', 		0, qr/^middlename$/ ],
	[ 'lastname', 		0, qr/^lastname$/ ],
	[ 'lastname2', 		0, qr/^lastname2$/ ],
	[ 'lastname3', 		0, qr/^lastname3$/ ],
	[ 'username', 		0, qr/^username$/ ],
	[ 'sex', 		0, qr/^gender$/, 		{ func => sub {return $_[0] =~ /F/i ? 'Female' : 'Male'} } ],
	[ 'birthdate', 		0, qr/^birthday$/,		{ func => sub {return date2epoch($_[0], 2)} } ],
	[ 'number', 		0, qr/^ssn$/,			{ type_out => 'socialsecurity' } ],
	[ 'name',		0, qr/^ssnfullname$/,		{ type_out => 'socialsecurity', as_title => sub {return 'SS# ' . $_[0]{'value'}} } ],
	[ 'company', 		0, qr/^company$/ ],

	[ 'address', 		0, qr/^address$/ ],		# combined from original fields: address1 address2 address3
	[ 'city', 		0, qr/^city$/ ],
	[ 'state', 		0, qr/^state$/ ],
	[ 'zip', 		0, qr/^zip$/ ],
	[ 'country', 		0, qr/^country$/ ],

	[ 'county', 		0, qr/^county$/ ],
	[ 'state_name', 	0, qr/^state_name$/ ],
	[ 'country_cc3l', 	0, qr/^country_cc3l$/ ],
	[ 'country_name', 	0, qr/^country_name$/ ],
	[ 'timezone', 		0, qr/^timezone$/ ],
	[ 'email', 		0, qr/^email$/ ],
	[ 'cellphone', 		0, qr/^cellphone$/ ],		# combined from original fields: mobilephone3lcc mobilephone mobileext
	[ 'defphone', 		0, qr/^defphone$/ ],		# combined from original fields: phone3lcc phone phoneext
	[ 'fax', 		0, qr/^fax$/ ],			# combined from original fields: fax3lcc fax faxext
	[ 'homephone', 		0, qr/^homephone$/ ],	 	# combined from original fields: evephone3lcc evephone eveext
	[ 'mobilephone3lcc', 	0, qr/^mobilephone3lcc$/ ],
	[ 'mobilephone', 	0, qr/^mobilephone$/ ],
	[ 'mobileext', 		0, qr/^mobileext$/ ],
	[ 'cardholder', 	0, qr/^ccname$/,		{ type_out => 'creditcard' } ],
	[ 'ccnum', 		0, qr/^ccnum$/,			{ type_out => 'creditcard',	as_title => sub {return 'Credit Card ending ' . last4($_[0]->{'value'})} } ],
	[ 'validFrom', 		0, qr/^ccstart$/,		{ type_out => 'creditcard',	func => sub {return date2monthYear($_[0], 2)}, keep => 1 } ],
	[ 'expiry', 		0, qr/^ccexp$/,			{ type_out => 'creditcard',	func => sub {return date2monthYear($_[0], 2)}, keep => 1 } ],
	[ 'cvv', 		0, qr/^cccsc$/,			{ type_out => 'creditcard' } ],
	[ 'ccissuenum', 	0, qr/^ccissuenum$/,		{ type_out => 'creditcard' } ],
	[ 'bankName', 		0, qr/^bankname$/,		{ type_out => 'bankacct',	as_title => sub {return $_[0]->{'value'}} } ],
	[ 'accountNo', 		0, qr/^bankacctnum$/,		{ type_out => 'bankacct',	to_title => sub {return ' (' . last4($_[0]->{'value'}) . ')'} } ],
	[ 'routingNo', 		0, qr/^bankroutingnum$/,	{ type_out => 'bankacct' } ],
	[ 'customfield1text', 	0, qr/^customfield1text$/ ],
	[ 'customfield1value', 	0, qr/^customfield1value$/ ],
	[ 'customfield1alttext',0, qr/^customfield1alttext$/ ],
	[ 'customfield2text', 	0, qr/^customfield2text$/ ],
	[ 'customfield2value', 	0, qr/^customfield2value$/ ],
	[ 'customfield2alttext',0, qr/^customfield2alttext$/ ],
	[ 'customfield3text', 	0, qr/^customfield3text$/ ],
	[ 'customfield3value', 	0, qr/^customfield3value$/ ],
	[ 'customfield3alttext',0, qr/^customfield3alttext$/ ],
	[ 'customfield4text', 	0, qr/^customfield4text$/ ],
	[ 'customfield4value', 	0, qr/^customfield4value$/ ],
	[ 'customfield4alttext',0, qr/^customfield4alttext$/ ],
	[ 'customfield5text', 	0, qr/^customfield5text$/ ],
	[ 'customfield5value', 	0, qr/^customfield5value$/ ],
	[ 'customfield5alttext',0, qr/^customfield5alttext$/ ],
    ]},
    insurance => 		{ textname => undef, type_out => 'membership', fields => [
	[ 'cardtype',		0, qr/^NoteType:(Insurance)(?:\x{0a}|\Z)/ms ],
	[ 'org_name',		0, qr/^(Company):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'poltype',		0, qr/^(Policy Type):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'polid',		0, qr/^(Policy Number):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'expiry_date',	0, qr/^(Expiration):([^\x{0a}]+)(?:\x{0a}|\Z)/ms,	{ func => sub {return date2monthYear($_[0], 2)}, keep => 1 } ],
	[ 'agentname',		0, qr/^(Agent Name):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'phone',		0, qr/^(Agent Phone):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'website',		0, qr/^(URL):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ]},
    instantmessage => 		{ textname => undef, type_out => 'login', fields => [
	[ 'cardtype',		0, qr/^NoteType:(Instant Messenger)(?:\x{0a}|\Z)/ms ],
	[ 'imtype',		0, qr/^(Type):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'username',		0, qr/^(Username):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'password',		0, qr/^(Password):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'url',		0, qr/^(Server):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'import',		0, qr/^(Port):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ]},
    login => 			{ textname => undef, fields => [			# special handling
	[ 'cardtype',		0, undef ],
	[ 'username',		0, qr/^username$/ ],
	[ 'password',		0, qr/^password$/ ],
	[ 'url',		0, qr/^url$/ ],
    ]},
    note => undef,									# special handling
    membership => 		{ textname => undef, fields => [
	[ 'cardtype',		0, qr/^NoteType:(Membership)(?:\x{0a}|\Z)/ms ],
	[ 'org_name',		0, qr/^(Organization):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'membership_no',	0, qr/^(Membership Number):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'member_name',	0, qr/^(Member Name):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'member_since',	0, qr/^(Start Date):([^\x{0a}]+)(?:\x{0a}|\Z)/ms,	{ func => sub {return date2monthYear($_[0], 2) }, keep => 1 } ],
	[ 'expiry_date',	0, qr/^(Expiration):([^\x{0a}]+)(?:\x{0a}|\Z)/ms,	{ func => sub {return date2monthYear($_[0], 2) }, keep => 1 } ],
	[ 'website',		0, qr/^(Website):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'phone',		0, qr/^(Telephone):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'pin',		0, qr/^(Password):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ]},
    passport => 		{ textname => undef, fields => [
	[ 'cardtype',		0, qr/^NoteType:(Passport)(?:\x{0a}|\Z)/ms ],
	[ 'type',		0, qr/^(Type):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'fullname',		0, qr/^(Name):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'issuing_country',	0, qr/^(Country):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'number',		0, qr/^(Number):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'sex',		0, qr/^(Sex):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'nationality',	0, qr/^(Nationality):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'issuing_authority',	0, qr/^(Issuing Authority):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'birthdate',		0, qr/^(Date of Birth):([^\x{0a}]+)(?:\x{0a}|\Z)/ms,   { func => sub {return date2epoch($_[0], -1)} } ],
	[ 'issue_date',		0, qr/^(Issued Date):([^\x{0a}]+)(?:\x{0a}|\Z)/ms,     { func => sub {return date2epoch($_[0], -1)} } ],
	[ 'expiry_date',	0, qr/^(Expiration Date):([^\x{0a}]+)(?:\x{0a}|\Z)/ms, { func => sub {return date2epoch($_[0],  2)} } ],
    ]},
    server => 			{ textname => undef, fields => [
	[ 'cardtype',		0, qr/^NoteType:(Server)(?:\x{0a}|\Z)/ms ],
	[ 'url',		0, qr/^(Hostname):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'username',		0, qr/^(Username):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'password',		0, qr/^(Password):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ]},
    socialsecurity => 		{ textname => undef, fields => [
	[ 'cardtype',		0, qr/^NoteType:(Social Security)(?:\x{0a}|\Z)/ms ],
	[ 'name',		0, qr/^(Name):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'number',		0, qr/^(Number):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ]},
    software => 		{ textname => undef, fields => [
	[ 'cardtype',		0, qr/^NoteType:(Software License)(?:\x{0a}|\Z)/ms ],
	[ 'reg_code',		0, qr/^(License Key):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'product_version',	0, qr/^(Version):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'publisher_name',	0, qr/^(Publisher):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'support_email',	0, qr/^(Support Email):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'publisher_website',	0, qr/^(Website):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'retail_price',	0, qr/^(Price):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'order_date',		0, qr/^(Purchase Date):([^\x{0a}]+)(?:\x{0a}|\Z)/ms, { func => sub {return date2epoch($_[0], 2)} } ],
	[ 'order_number',	0, qr/^(Order Number):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'nlicenses',		0, qr/^(Number of Licenses):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'order_total',	0, qr/^(Order Total):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ]},
    sshkey => 			{ textname => undef, type_out => 'server', fields => [
	[ 'cardtype',		0, qr/^NoteType:(SSH Key)(?:\x{0a}|\Z)/ms ],
	[ 'sshbitstrength',	0, qr/^(Bit Strength):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'sshformat',		0, qr/^(Format):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'sshpassphrase',	0, qr/^(Passphrase):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'sshprivkey',		0, qr/^(Private Key):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'sshpubkey',		0, qr/^(Public Key):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'admnin_console_url',	0, qr/^(Hostname):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'sshdate',		0, qr/^(Date):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ]},
    wireless => 		{ textname => undef, fields => [
	[ 'cardtype',		0, qr/^NoteType:(Wi-Fi Password)(?:\x{0a}|\Z)/ms ],
	[ 'network_name',	0, qr/^(SSID):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'wireless_password',	0, qr/^(Password):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'wireless_conntype',	0, qr/^(Connection Type):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'wireless_connmode',	0, qr/^(Connection Mode):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'wireless_auth',	0, qr/^(Authentication):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'wireless_encrypt',	0, qr/^(Encryption):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'wireless_use8201x',	0, qr/^(Use 802\.1X):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'wireless_fipsmode',	0, qr/^(FIPS Mode):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'wireless_keytype',	0, qr/^(Key Type):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'wireless_protected',	0, qr/^(Protected):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'wireless_keyindex',	0, qr/^(Key Index):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
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

    my $csv = Text::CSV->new ({
	    binary => 1,
	    eol => "\x{a}",
	    sep_char => ',',
	    auto_diag => 1,
    });

    open my $io, "<:encoding(utf8)", $file
	or bail "Unable to open CSV file: $file\n$!";

    $csv->column_names($csv->getline($io)) or 
	bail "Failed to parse CSV column names: $!";

    my (%Cards, %saved_ssns);;
    my ($n, $rownum) = (1, 1);
    my ($npre_explode, $npost_explode);
    while (my $hr = $csv->getline_hr($io)) {
	debug 'ROW: ', $rownum++;

	my ($itype, $card_title, $card_notes, @card_tags, @fieldlist);

	# Switch on the form of CSV export:
	#    - standard entries (LastPass CSV File)
	#    - profiles (Form Fill Profiles)
	if (! exists $hr->{'profilename'}) {
	    # Lastpass CSV field order / header names
	    #
	    #    url, username, password, extra, name, grouping, fav
	    #
	    # LastPass CSV File export has two types: Site and Secure Note
	    #
	    # Field 'extra' contains lines of specific secure notes label:value pairs
	    # Secure notes types will have URL = "http://sn"

	    $card_title =  $hr->{'name'};
	    $card_notes =  $hr->{'extra'};
	    push @card_tags, 'Favorite'		if $hr->{'fav'} == 1;
	    push @card_tags, $hr->{'grouping'}	if $hr->{'grouping'} ne '(none)' and $hr->{'grouping'} ne '';

	    if ($hr->{'url'} ne 'http://sn') {
		$itype = 'login';
		for (qw/username password url/) {
		    push @fieldlist, [ $_ => $hr->{$_} ]	if $hr->{$_} ne '';
		}
	    }
	    else {
		$itype = pull_fields_from_note(\@fieldlist, \$card_notes);
	    }
	}
	# Form Fill profiles will map to one or more 1P4 types:
	#    Identity, Credit Card, Bank Account, and Social Security Number
	else {
	    $itype = 'identity';
	    # LastPass Form Fill Profiles export 
	    
	    my $fullname = join ' ', $hr->{'firstname'}, $hr->{'lastname'};
	    $card_title = $fullname;

	    $card_notes = 'Form Fill Profile: ' . $hr->{'profilename'};		delete $hr->{'profilename'};
	    $card_notes .= "\n" . $hr->{'notes'}	if $hr->{'notes'} ne '';	delete $hr->{'notes'};

	    $hr->{'ssnfullname'}  = $fullname;
	    $hr->{'defphone'}	  = join ' ',  grep {$_ ne ''} map {$hr->{$_}} qw/phone3lcc phone phoneext/; 
	    $hr->{'homephone'}	  = join ' ',  grep {$_ ne ''} map {$hr->{$_}} qw/evephone3lcc evephone eveext/; 
	    $hr->{'cellphone'}	  = join ' ',  grep {$_ ne ''} map {$hr->{$_}} qw/mobilephone3lcc mobilephone mobileext/; 
	    $hr->{'fax'}	  = join ' ',  grep {$_ ne ''} map {$hr->{$_}} qw/fax3lcc fax faxext/; 
	    $hr->{'address'}{'street'}	  = join ', ', grep {$_ ne ''} map {$hr->{$_}} qw/address1 address2 address3/; 
	    for (qw/city state country zip/) {
		$hr->{'address'}{$_} = $hr->{$_};
		delete $hr->{$_};
	    }
	    delete $hr->{$_} for qw/address1 address2 address3 phone3lcc phone phoneext
				    evephone3lcc evephone eveext mobilephone3lcc mobilephone mobileext fax3lcc fax faxext/;

	    # Social Security fields
	    if ($hr->{'ssn'} ne '') {
		# save the SSN #'s to avoid duplicate SS cards
		if (++$saved_ssns{$hr->{'ssn'} =~ s/[-\s]//gr} > 1) {
		    verbose("Skipped creating duplicate social security entry from form profile");
		    delete $hr->{'ssn'};
		}
	    }

	    for (keys $hr) {
		debug "KEY: $_";
		push @fieldlist, [ $_ => $hr->{$_} ]		if defined $hr->{$_} and $hr->{$_} ne '';
	    }
	}

	debug "\t\ttype determined as '$itype'";

	# skip all types not specifically included in a supplied import types list
	next if defined $imptypes and (! exists $imptypes->{$itype});

	# From the card input, place it in the converter-normal format.
	# The card input will have matched fields removed, leaving only unmatched input to be processed later.
	my $normalized = normalize_card_data($itype, \@fieldlist, $card_title, \@card_tags, \$card_notes);

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
    if (! $csv->eof()) {
	warn "Unexpected failure parsing CSV: row $n";
    }

    $n--;
    verbose "Imported $n card", pluralize($n) ,
	$npre_explode ? " ($npre_explode card" . pluralize($npre_explode) .  " expanded to $npost_explode cards)" : "";
    return \%Cards;
}

sub do_export {

    add_new_field('driverslicense',  'city',		$Utils::PIF::sn_main,	$Utils::PIF::k_string,    'city / town');
    add_new_field('driverslicense',  'zip',		$Utils::PIF::sn_main,	$Utils::PIF::k_string,    'zip / postal code');

    add_new_field('membership',      'poltype',		$Utils::PIF::sn_main,	$Utils::PIF::k_string,    'policy type');
    add_new_field('membership',      'polid',		$Utils::PIF::sn_main,	$Utils::PIF::k_string,    'policy ID');
    add_new_field('membership',      'grpid',		$Utils::PIF::sn_main,	$Utils::PIF::k_string,    'group ID');
    add_new_field('membership',      'agentname',	$Utils::PIF::sn_main,	$Utils::PIF::k_string,    'agent name');

    add_new_field('server',          'sshbitstrength',	'server.SSH Info',	$Utils::PIF::k_string,    'bit strength');
    add_new_field('server',          'sshformat',	'server.SSH Info',	$Utils::PIF::k_string,    'format');
    add_new_field('server',          'sshpassphrase',	'server.SSH Info',	$Utils::PIF::k_concealed, 'passphrase');
    add_new_field('server',          'sshprivkey',	'server.SSH Info',	$Utils::PIF::k_concealed, 'private key');
    add_new_field('server',          'sshpubkey',	'server.SSH Info',	$Utils::PIF::k_string,    'public key');
    add_new_field('server',          'sshdate',		'server.SSH Info',	$Utils::PIF::k_string,    'date');

    add_new_field('software',        'nlicenses',	$Utils::PIF::sn_order,	$Utils::PIF::k_string,    'number of licenses');

    create_pif_file(@_);
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
    my ($type, $fieldlist, $title, $tags, $notesref, $postprocess) = @_;
    my %norm_cards;
    $norm_cards{'title'} = $title	if $title ne '';
    $norm_cards{'tags'}  = $tags;
    $norm_cards{'notes'} = $$notesref;

    #[1..$#$defs#]
    my $defs = $card_field_specs{$type}{'fields'};
    for my $def (@{$defs}[1..$#$defs]) {
	my $h = {};
	for (my $i = 0; $i < @$fieldlist; $i++) {
	    my ($inkey, $value) = @{$fieldlist->[$i]};
	    next if not defined $value or $value eq '';

	    # Patterns in %card_field_specs are used to match inside a note, so create a
	    # key:value string that will allow the RE to match, except for the special case
	    # login and identity types.
	    my $pat = $type =~ /^login|identity$/ ? $inkey : join ':', $inkey, $value;

	    if ($def->[2] and $pat =~ $def->[2]) {
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
		for (qw/as_title to_title/) {
		    if (exists $def->[3]{$_}) {
			$h->{$_}	= ref $def->[3]{$_} eq 'CODE' ? $def->[3]->{$_}($h) : $h->{$def->[3]{$_}}
		    }
		}
		push @{$norm_cards{'fields'}}, $h;
		splice @$fieldlist, $i, 1;	# delete matched so undetected are pushed to notes below
		last;
	    }
	}
    }

    # map remaining keys to notes
    $norm_cards{'notes'} .= "\n"	if defined $norm_cards{'notes'} and length $norm_cards{'notes'} > 0 and @$fieldlist;
    for (@$fieldlist) {
	next if $_->[1] eq '';
	$norm_cards{'notes'} .= "\n"	if defined $norm_cards{'notes'} and length $norm_cards{'notes'} > 0;
	$norm_cards{'notes'} .= join ': ', @$_;
    }

    return \%norm_cards;
}
sub pull_fields_from_note {
    my ($fieldlist, $notes) = @_;

    for my $type (keys %card_field_specs) {
	my $defs = $card_field_specs{$type}{'fields'};

	next if !defined $defs;		# XXX

	# the first entry in the note indicates the note type (e.g. NoteType:Bank Account)
	if ($defs->[0][2] and $$notes =~ s/$defs->[0][2]//ms) {
	    for (@{$defs}[1..$#$defs]) {
		if ($$notes =~ s/$_->[2]//ms) {
		    my ($label, $val) = ($1, $2);
		    push @$fieldlist, [ $label => $val ];		# maintains original order
		}
	    }
	    return $type;
	}
    }

    return 'note';
}


# input conversion routines
#
sub bankstrconv {
    local $_ = shift;
    return  'savings' 		if /sav/i;
    return  'checking'		if /check/i;
    return  'loc'		if /line|loc|credit/i;
    return  'amt'		if /atm/i;
    return  'money_market'	if /money|market|mm/i;
    return  'other';
}

=cut
sub old_date2monthYear {
    # input form: 2014-12-01
    local $_ = shift;

    if (/(^\d{4}+)-(\d{2})-01$/) {
	if (check_date($1, $2, 1)) {	# y, m, d
	    return $1 . sprintf("%02d", $2);
	}
    }

    return undef;
}

sub birthdayconv {
    # input form: 1964-02-28
    local $_ = shift;

    if (/(^\d{4}+)-(\d{2})-(\d{2})$/) {
	if (check_date($1, $2, $3)) {	# y, m, d
	    return timelocal(0,0,0,$3,$2 - 1,$1);
	}
    }

    return undef;
}
=cut

# Date converters
# lastpass dates: month,d,yyyy   month,yyyy   yyyy-mm-dd
sub parse_date_string {
    local $_ = $_[0];
    my $when = $_[1] || 0;					# -1 = past only, 0 = assume this century, 1 = future only, 2 = 50-yr moving window

    if (/^(?<m>[^,]+),(?:(?<d>\d{1,2}),)?(?<y>\d{4})$/ or	# month,d,yyyy or month,yyyy
	/^(?<y>\d{4}+)-(?<m>\d{2})-(?<d>\d{2})$/) { 		# yyyy-mm-dd
	my $days_today = Date_to_Days(@today);

	my $d_present = exists $+{'d'};
	my $d = sprintf "%02d", $+{'d'} // "1";
	my $m = $+{'m'};
	my $y = $+{'y'};
	$m = sprintf "%02d", $m !~ /^\d{1,2}$/ ? Decode_Month($m) : $m;
	for my $century (qw/20 19/) {
	    if (length $y eq 2) {
		$y = sprintf "%d%02d", $century, $y;
		$y = Moving_Window($y)	if $when == 2;
	    }
	    if (check_date($y, $m, $d)) {
		next if ($when == -1 and Date_to_Days($y,$m,$d) > $days_today);
		next if ($when ==  1 and Date_to_Days($y,$m,$d) < $days_today);
		return ($y, $m, $d_present ? $d : undef);
	    }
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
    return defined $y ? timelocal(0, 0, 0, $d, $m - 1, $y): $_[0];
}

sub last4 {
    my $_ = shift;
    s/[- ._:]//;
    /(.{4})$/;
    return $1;
}

1;
