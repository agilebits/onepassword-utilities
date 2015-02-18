# eWallet text export converter
#
# Copyright 2014 Mike Cappella (mike@cappella.us)

package Converters::Ewallet 1.01;

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
use Time::Local qw(timelocal);
use Date::Calc qw(check_date Date_to_Days Moving_Window);

# The %card_field_specs hash maps input card types to 1P4 card types and their assosciated fields. 
#
#   KEY   =>                    { textname => 'Card Text Name', fields => [
#       [ 1p4_Field_Key,     SetType?, field label match pattern, value_mod_callback, retain_key? ]
#
# Do Not Reorder the fields within a type - they match the order found in the text output and help parsing
#
#    dstkey =>			1, RE or str, {
#						func	 => <callback func ref>
#						type_out => <exptype>
#						keep	 => 0|1
#						to_title => normalized card field key
#					      }

my %card_field_specs = (
    bankacct =>                 { textname => undef, fields => [
	[ 'bankName',		1, qr/^(Bank Name) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'branchPhone',	0, qr/^(Telephone) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'accountType',	0, qr/^(Account Type) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,	{ func => \&bankstrconv } ],
	[ 'accountNo',		0, qr/^(Account Number) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'telephonePin',	0, qr/^(PIN) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ '_sortcode',		1, qr/^(Sort Code) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'swift',		1, qr/^(SWIFT Code) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'routingNo',		1, qr/^(ABA\/Routing(?: #)?) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],	# 7.3mac: " #", but not 7.64win
	[ '_pin2',		1, qr/^(PIN2) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'url',		0, qr/^(URL) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,		 { type_out => 'login' } ],
	[ 'username',		0, qr/^(User Name) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,	 { type_out => 'login' } ],
	[ 'password',		0, qr/^(Password) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,		 { type_out => 'login' } ],
    ]},
    callingcard =>              { textname => undef, type_out => 'login', fields => [
	[ '_provider',		1, qr/^(Provider) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ '_accessnum',		0, qr/^(Access Number):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],	# 7.64win no :
	[ '_cardnum',		0, qr/^(Card Number):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :
	[ '_pin',		0, qr/^(PIN) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'notesinst',		1, qr/^(Notes and Instructions) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'phonenum',		0, qr/^(?|(Phone Number)|(?:(If card is lost or stolen call):)) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],	# 7.64win: Phone Number
	[ 'url',		0, qr/^(URL) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'username',		0, qr/^(User Name) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'password',		0, qr/^(Password) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ]},
    carinfo =>                 { textname => undef, type_out => 'note', fields => [
	[ 'caryear',		1, qr/^(Year) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'carmake',		1, qr/^(Make) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'carmodel',		0, qr/^(Model) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'carlicense',		0, qr/^(License Number):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],	# 7.64win no :
	[ 'carlicenseexpiry',	0, qr/^(Expires on):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :
	[ 'carvin',		1, qr/^(Vehicle Number):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],	# 7.64win no :
	[ 'carcylinders',	1, qr/^(Cylinders):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :
	[ 'carinscompany',	1, qr/^(Insurance Company):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],	# 7.64win no :
	[ 'carinspolicy',	0, qr/^(Policy Number):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],	# 7.64win no :
	[ 'carinsphone',	1, qr/^(Insurance Telephone) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'carinsexpiry',	0, qr/^(Expires on):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :, note Expires on above also
	[ 'carinsphone2',	0, qr/^(Phone Number) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'url',		0, qr/^(URL) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,		{ type_out => 'login' } ],
	[ 'username',		0, qr/^(User Name) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,	{ type_out => 'login' } ],
	[ 'password',		0, qr/^(Password) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,		{ type_out => 'login' } ],
    ]},
    cellphone =>                { textname => undef, type_out => 'login', fields => [
	[ 'cellmfg',		0, qr/^(Manufacturer) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'cellmodel',		0, qr/^(Model) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'cellphonenum',	0, qr/^(Phone Number) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ '_pin',		0, qr/^(PIN) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'cellpassword',	0, qr/^(Password) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'cellseccode',	1, qr/^(Security Code) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'phonehelp',		1, qr/^(Help Phone Number):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],	# 7.64win no :
	[ 'cellsim',		1, qr/^(SIM) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'cellemei',		1, qr/^(IMEI\/ESN) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'cellcarrier',	1, qr/^(Carrier) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'url',		0, qr/^(URL) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms],
	[ 'username',		0, qr/^(User Name) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'password',		0, qr/^(Site Password) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ]},
    clothes =>                  { textname => undef, type_out => 'note', fields => [
	[ 'clothesfor',		1, qr/^(Sizes For) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'clothessuit',	1, qr/^(Suit):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'clotheswaist',	1, qr/^(Waist):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :
	[ 'clothesinseam',	1, qr/^(Inseam):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :
	[ 'clothesshoe',	1, qr/^(Shoe):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'clothespants',	1, qr/^(Pants):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :
	[ 'clothesshirt',	1, qr/^(Shirt):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :
	[ 'clothesneck',	1, qr/^(Neck):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'clothesglove',	1, qr/^(Glove):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :
	[ 'clothesother',	0, qr/^(Other) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ]},
    combolock =>                { textname => undef, type_out => 'login', fields => [
	[ 'combolock',		1, qr/^(Lock):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'combolocation',	0, qr/^(Location):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :
	[ 'password',		1, qr/^(Combination) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'comboother',		0, qr/^(Other) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ]},
    contact =>                  { textname => undef, type_out => 'note', fields => [
	[ 'contactname',	0, qr/^(Name) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'contactcompany',	1, qr/^(Company) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'contactphone1',	1, qr/^(Telephone 1):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :
	[ 'contactphone2',	1, qr/^(Telephone 2):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :
	[ 'contactphone3',	1, qr/^(Telephone 3):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :
	[ 'contactemail',	1, qr/^(Email):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :
	[ 'contactother',	0, qr/^(Other Information) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'contactwebsite',	1, qr/^(Web Site) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ]},
    contactlens =>              { textname => undef, type_out => 'note', fields => [
	[ 'clensrpow',		1, qr/^(Right (?:\(O\.D\.\) )?Power):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],	# 7.64win no :, adds "(O.D.) "
	[ 'clensrbasecurve',	1, qr/^((?:Right )?Base Curve):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],	# 7.64win no :, adds "Right "
	[ 'clensrdiameter',	1, qr/^((?:Right )?Diameter):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :, adds "Right "
	[ 'clenslpow',		1, qr/^(Left (?:\(O\.S\.\) )?Power):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],	# 7.64win no :, adds "(O.S.) "
	[ 'clenslbasecurve',	1, qr/^((?:Left )?Base Curve):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :, adds "Left "; "Base Curve" exists above
	[ 'clensldiameter',	1, qr/^((?:Left )?Diameter):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :, adds "Left "; "Diameter" exists above
	[ 'clensdoc',		0, qr/^(Doctor's Name):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :
	[ 'clensdocphone',	0, qr/^(Doctor's Phone)(?: #:)? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no "# :"
	[ 'clensother',		0, qr/^(Other Information) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'url',		0, qr/^(URL) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,		{ type_out => 'login' } ],
	[ 'username',		0, qr/^(User Name) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,	{ type_out => 'login' } ],
	[ 'password',		0, qr/^(Password) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,		{ type_out => 'login' } ],
	[ 'clenstype',		0, qr/^(Lens Type) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'clensstore',		0, qr/^(Store) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'clenscost',		0, qr/^(Cost) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'clensradd',		0, qr/^(Right Add) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'clensrbase',		0, qr/^(Right Base) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'clensrprism',	0, qr/^(Right Prism) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'clensladd',		0, qr/^(Left Add) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'clenslbase',		0, qr/^(Left Base) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'clenslprism',	0, qr/^(Left Prism) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ]},
    creditcard =>               { textname => undef, fields => [
	[ 'bank',		1, qr/^(Card Provider) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'type',		1, qr/^(Credit Card Type) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms, 	{ func => sub{return lc $_[0]} } ],
	[ 'ccnum',		0, qr/^(Card Number) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
				# 7.64win: "Expiration Date", 7.3mac: "Expires: "
	[ 'expiry',		0, qr/^(Expir(?:es|ation Date)):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms, { func => sub { return date2monthYear($_[0], 2) }, keep => 1 } ],
	[ 'pin',		0, qr/^(PIN) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'cardholder',		1, qr/^(Name on Card) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'phoneTollFree',	0, qr/^(Phone Number|If card is lost or stolen call):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ], # 7.64win: "Phone Number"
	[ 'validFrom',		1, qr/^(Start Date) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,	 	{ func => sub { return date2monthYear($_[0], 2) }, keep => 1 } ],
	[ 'cvv',		1, qr/^(3-digit CVC#) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'url',		0, qr/^(URL) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,			{ type_out => 'login' } ],
	[ 'username',		0, qr/^(User Name) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,		{ type_out => 'login' } ],
	[ 'password',		0, qr/^(Password) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,			{ type_out => 'login' } ],
    ]},
    driverslicense =>           { textname => undef, fields => [
	[ 'number',		0, qr/^((?:Driver's )?License Number):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],	# 7.64win: adds "Driver's "
	[ '_location',		1, qr/^(City\/Location):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ '_dateissued',	1, qr/^(Date Issued):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'expiry_date',	0, qr/^(Expiration Date):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,	 { func => sub { return date2monthYear($_[0], 2) }, keep => 1 } ],
	[ '_otherinfo',		0, qr/^(Other Info) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'url',		0, qr/^(URL) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'state',		1, qr/^(State\/Province) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'class',		1, qr/^(Class) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'phone',		0, qr/^(Phone Number) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ]},
    email =>                    { textname => undef, fields => [
	[ 'provider',		0, qr/^(System):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'pop_username',	0, qr/^(User Name) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'pop_password',	0, qr/^(Password) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'smtp_server',	1, qr/^(Outgoing SMTP Server):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :
	[ 'pop_server',		1, qr/^(Incoming (?:POP|Pop) Server):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],	# 7.64win no : and "POP"
	[ '_phoneaccess',	0, qr/^(Access Phone Number):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :
	[ 'provider_website',	0, qr/^(Support URL):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ '_phonesupport',	0, qr/^(Support Phone (?:Number )):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],	# 7.64win no : and "Number "
    ]},
    emergency =>                { textname => undef, type_out => 'note', fields => [
	[ 'emergencynums',	0, qr/^(Title|Emergency Numbers) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],	# 7.64win "Title"
	[ 'emergencyfire',	1, qr/^(Fire): ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],				# 7.64win no :
	[ 'emergencyambulance',	1, qr/^(Ambulance):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'emergencypolice',	1, qr/^(Police):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'emergencydoctor',	0, qr/^(Doctor):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'emergencypoison',	1, qr/^(Poison):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'emergencyphone1',	1, qr/^(Number1) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'emergencyphone2',	1, qr/^(Number2) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'emergencyphone3',	1, qr/^(Number3) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ]},
    general =>                  { textname => undef, type_out => 'note', fields => [
	[ 'generaltitle',	0, qr/^(Title) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'generalinfo1',	1, qr/^(Info1) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'generalinfo2',	1, qr/^(Info2) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'generalinfo3',	1, qr/^(Info3) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'generalinfo4',	1, qr/^(Info4) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'generalinfo5',	1, qr/^(Info5) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'generalinfo6',	1, qr/^(Info6) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ]},
    health =>                   { textname => undef, type_out => 'membership', fields => [
	[ 'healthtitle',	0, qr/^(Card Title) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'healthid',		0, qr/^(ID Number):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'org_name',		0, qr/^(Group):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'healthplan',		1, qr/^(Plan):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],				# 7.64win no :
	[ 'healthphone',	0, qr/^(Telephone):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'healthspon',		1, qr/^(Plan Sponsor):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'healthother',	0, qr/^(Other) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'url',		0, qr/^(URL) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,		{ type_out => 'login' } ],
	[ 'username',		0, qr/^(User Name) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,	{ type_out => 'login' } ],
	[ 'password',		0, qr/^(Password) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,		{ type_out => 'login' } ],
    ]},
    idcard =>                   { textname => undef, type_out => 'membership', fields => [
	[ 'idtitle',		0, qr/^(Card Title) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'org_name',		1, qr/^(Country or Organization) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'membership_no',	0, qr/^(ID Number)(?!:) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],	# note no :
	[ 'member_name',	0, qr/^(Name) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'website',		0, qr/^(URL) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'idusername',		0, qr/^(User Name) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'pin',		0, qr/^(Password) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'phone',		0, qr/^(Phone Number) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ]},
    insurance =>                { textname => undef, type_out => 'membership', fields => [
	[ 'insureco',		0, qr/^(Insurance Company) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'insurepol',		0, qr/^(Policy Number):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :
	[ 'insuretype',		0, qr/^((?:Insurance )?Type): ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no "Insurance "
				# 7.64win: "Expiration Date", 7.3mac: "Expires On: "
	[ 'expiry_date',	0, qr/^(Expir(?:es On|ation Date)):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms, { func => sub { return date2monthYear($_[0], 2) }, keep => 1 } ],
	[ 'phone',		0, qr/^((?:Phone|Telephone) Number):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],	# 7.64win "Phone Number"
	[ 'insureother',	0, qr/^(Other Information) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'insureagent',	1, qr/^(Agent) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'url',		0, qr/^(URL) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,		{ type_out => 'login' } ],
	[ 'username',		0, qr/^(User Name) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,	{ type_out => 'login' } ],
	[ 'password',		0, qr/^(Password) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,		{ type_out => 'login' } ],
    ]},
    internet =>                 { textname => undef, type_out => 'server', fields => [
	[ 'name',		1, qr/^(ISP\/System) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'internetphone',	0, qr/^(Access Phone Number):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :
	[ 'username',		0, qr/^(User Name):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms, ],			# 7.64win no :
	[ 'password',		0, qr/^(Password) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms, ],
	[ 'url',		0, qr/^(URL):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms, ],				# 7.64win no :
	[ 'internetip',		1, qr/^(IP Address):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms, ],			# 7.64win no :
	[ 'internethost',	1, qr/^(Host Name|Hostname):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms, ],		# 7.64win "Hostname"
	[ 'internetmail',	1, qr/^(Mail Server):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms, ],			# 7.64win no :
	[ 'internetnews',	1, qr/^(News Server) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms, ],
	[ 'internetsuppemail',	1, qr/^(Support email) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms, ],
	[ 'internetnetmask',	1, qr/^(Netmask) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms, ],
	[ 'internetgateway',	1, qr/^(Default Gateway) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms, ],
	[ 'internetdns',	1, qr/^(Name Server) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms, ],
    ]},
    lens =>              	{ textname => undef, type_out => 'note', fields => [
	[ 'lensrsph',		1, qr/^(Right (?:\(O\.D\.\) )?SPH):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],	# 7.64win no :, adds "(O.D.) "
	[ 'lensrcyl',		1, qr/^((?:Right )?CYL):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :, adds "Right "
	[ 'lensraxis',		1, qr/^((?:Right )?AXIS):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :, adds "Right "
	[ 'lenslsph',		1, qr/^(Left (?:\(O\.S\.\) )?SPH):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],	# 7.64win no :, adds "(O.S.) "
	[ 'lenslcyl',		1, qr/^((?:Left )?CYL):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :, adds "Left "
	[ 'lenslaxis',		1, qr/^((?:Left )?AXIS):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :, adds "Left "
	[ 'lenspupil',		1, qr/^(Pupil Distance \(mm\)):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],	# 7.64win no :
	[ 'lensdoc',		0, qr/^(Doctor's Name):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :
	[ 'lensdoc',		0, qr/^(Doctor's Phone) (?:#: )?([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no "#:"
	[ 'lensother',		0, qr/^(Other Information) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'url',		0, qr/^(URL) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,		{ type_out => 'login' } ],
	[ 'username',		0, qr/^(User Name) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,	{ type_out => 'login' } ],
	[ 'password',		0, qr/^(Password) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,		{ type_out => 'login' } ],
	[ 'lenstype',		0, qr/^(Lens Type) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'lensframe',		1, qr/^(Frame Type) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'lensstore',		0, qr/^(Store) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'lenscost',		0, qr/^(Cost) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'lensradd',		0, qr/^(Right Add) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'lensrbase',		0, qr/^(Right Base) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'lensrprism',		0, qr/^(Right Prism) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'lensladd',		0, qr/^(Left Add) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'lenslbase',		0, qr/^(Left Base) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'lenslprism',		0, qr/^(Left Prism) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ]},
    librarycard =>              { textname => undef, type_out => 'membership', fields => [
	[ 'libname',		1, qr/^(Library Name) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'membership_no',	1, qr/^(Library Card Number) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'url',		0, qr/^(URL):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,		{ type_out => 'login' } ],	# 7.64win no :
	[ 'username',		0, qr/^(User Name):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,	{ type_out => 'login' } ],	# 7.64win no :
	[ 'password',		0, qr/^(Password) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,		{ type_out => 'login' } ],
	[ 'pin',		0, qr/^(PIN) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'phone',		0, qr/^(Phone Number) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ]},
    membership =>               { textname => undef, fields => [
	[ 'org_name',		1, qr/^(Organization) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'membership_no',	0, qr/^(ID Number):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'phone',		0, qr/^(Phone Number|Telephone):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],	# 7.64win no :, "Phone Number"
				# 7.64win: "Expiration Date", 7.3mac: "Expires On: "
	[ 'expiry_date',	0, qr/^(Expir(?:es On|ation Date)):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,	{ func => sub { return date2monthYear($_[0], 2) }, keep => 1 } ],
	[ 'url',		0, qr/^(URL) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,		{ type_out => 'login' } ],
	[ 'username',		0, qr/^(User Name) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,	{ type_out => 'login' } ],
	[ 'password',		0, qr/^(Password) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,		{ type_out => 'login' } ],
	[ 'pin',		0, qr/^(PIN) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ '_points',		0, qr/^(Points\/Miles to Date) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ]},
    note =>                     { textname => undef, fields => [
    ]},
    passport =>                 { textname => undef, fields => [
	[ 'type',		0, qr/^(Type):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],				# 7.64win no :
	[ 'issuing_country',	0, qr/^(Code of issuing state):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],	# 7.64win no :
	[ 'number',		1, qr/^(Passport (?:No\.|Number)):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],	# 7.64win no :, uses "Passport No."
	[ 'surname',		1, qr/^(Surname):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'sex',		0, qr/^(Sex):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'fullname',		1, qr/^(Given [Nn]ames):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win lcase n
				   # no :, 7.64win "Date of birth"
	[ 'birthdate',		1, qr/^(Birth Date|Date of birth):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,	{ func => sub { return date2epoch($_[0], -1) }, keep => 1 } ],
	[ 'birthplace',		1, qr/^(Birth place|Place of birth):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],	# 7.64win no :, "Place of birth"
	[ 'nationality',	1, qr/^(Nationality):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
				   # 7.64win no :, "Date of issue" and "Date of expiration"
	[ 'issue_date',		0, qr/^(Issued|Date of issue):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,		{ func => sub { return date2epoch($_[0], -1) }, keep => 1 } ],
	[ 'expiry_date',	0, qr/^(Expires|Date of expiration):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,	{ func => sub { return date2epoch($_[0],  2) }, keep => 1 } ],
	[ 'issuing_authority',	1, qr/^(Authority):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'phone',		0, qr/^(Phone Number) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ]},
    password =>                 { textname => undef, type_out => 'login', fields => [
	[ 'pwlogin',		0, qr/^(System):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'username',		0, qr/^(User Name):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'password',		0, qr/^(Password) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'url',		0, qr/^(URL):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],				# 7.64win no :
	[ '_pin',		0, qr/^(PIN) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'pwtype',		0, qr/^(Account Type) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'pwphone',		0, qr/^(Phone Number) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ]},
    prescription =>           	{ textname => undef, type_out => 'note', fields => [
	[ 'rxdrug',		1, qr/^(Drug Name):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'rxamount',		1, qr/^(Amount):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'rxwhen',		1, qr/^(When to Take):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'rxbrand',		0, qr/^(Brand):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'rxdate',		0, qr/^((?:Purchase )?Date):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :, "Purchase Date"
	[ 'rxpharmacy',		1, qr/^(Pharmacy):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'rxdoctor',		0, qr/^(Doctor):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'rxdocphone',		0, qr/^(Doctor's Phone|Phone No\.):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],	# 7.64win no :, "Doctor's Phone"
	[ 'rxphone',		1, qr/^(Pharmacy Phone Number) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'rxgeneric',		1, qr/^(Generic For) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'rxexpiry',		0, qr/^(Expiration) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'rxnumber',		1, qr/^(Rx Number) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'rxrefills',		1, qr/^(Number of Refills) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'url',		0, qr/^(URL) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,		{ type_out => 'login' } ],
	[ 'username',		0, qr/^(User Name) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,	{ type_out => 'login' } ],
	[ 'password',		0, qr/^(Password) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,		{ type_out => 'login' } ],
	[ 'rxtype',		0, qr/^(Type) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'rxdatestart',	1, qr/^(Date Started) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'rxdatestop',		1, qr/^(Date Stopped) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ]},
    serialnum =>           	{ textname => undef, type_out => 'note', fields => [
	[ 'serialprod',		1, qr/^(Product) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'serialbrand',	0, qr/^(Brand):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'serialno',		1, qr/^(Serial Number):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :
	[ 'serialmodel',	1, qr/^(Model Number):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'serialpurchloc',	1, qr/^(Purchase Location):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :
	[ 'serialpurchdate',	0, qr/^(Purchase Date):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :
	[ 'serialother',	0, qr/^(Other Information) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'serialwebsite',	0, qr/^(URL) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms, ],
	[ 'serialwarranty',	1, qr/^(Warranty) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms, ],
	[ 'serialphone',	0, qr/^(Phone Number) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'serialregname',	1, qr/^(Registered Name) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ]},
    socialsecurity =>           { textname => undef, fields => [
				# 7.3mac has a first line "Social Security"; perhaps it was a Type designator
	[ '_account_num',	0, qr/^(Type|Account Number) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win "Type", 7.3mac "Account Number"
	[ 'number',		1, qr/^(Social Security Number) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'name',		0, qr/^(Name) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'url',		0, qr/^(URL) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,		{ type_out => 'login' } ],
	[ 'username',		0, qr/^(User Name) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,	{ type_out => 'login' } ],
	[ 'password',		0, qr/^(Password) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,		{ type_out => 'login' } ],
	[ '_phone',		0, qr/^(Phone Number) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ]},
    software =>                 { textname => undef, fields => [
	[ '_title2',		0, qr/^(Title) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'publisher_name',	0, qr/^(Manufacturer):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'product_version',	1, qr/^(Version):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ '_label',		1, qr/^(Name\/Label) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ '_number',	        1, qr/^(Number (?!of Refills))([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'reg_name',		0, qr/^(Name):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],				# 7.64win no :
	[ 'reg_code',		1, qr/^(Key):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],				# 7.64win no :
	[ 'order_date',		0, qr/^(Purchase Date):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,	{ func => sub { return date2epoch($_[0], -1) }, keep => 1 } ], # 7.64win no :
	[ '_purchasefrom',	1, qr/^(Purchased From):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :
	[ '_support',	        1, qr/^(Support(?: Information)?):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],	# 7.64win no :, "Support Information"
	[ '_partnum',		1, qr/^(Part Number) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ '_softlocation',	0, qr/^(Location) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'url',		0, qr/^(URL) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,		{ type_out => 'login' } ],
	[ 'username',		0, qr/^(User Name) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,	{ type_out => 'login' } ],
	[ 'password',		0, qr/^(Password) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms,		{ type_out => 'login' } ],
	[ '_phonenum',		0, qr/^(Phone Number) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ]},
    voicemail =>           	{ textname => undef, type_out => 'login', fields => [
	[ 'vmaccessnum',	0, qr/^((?:Voice Mail )?Access Number):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],	# 7.64win no :, "Access Number"
	[ 'password',		0, qr/^(Password):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'vmplay',		1, qr/^(Play):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],				# 7.64win no :
	[ 'vmdelete',		1, qr/^(Delete):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'vmsave',		1, qr/^(Save):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],				# 7.64win no :
	[ 'vmrecord',		1, qr/^(Record):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'vmnext',		1, qr/^(Next):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],				# 7.64win no :
	[ 'vmprev',		1, qr/^(Prev):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],				# 7.64win no :
	[ 'vmrewind',		1, qr/^(Rewind):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'vmffwd',		1, qr/^(FFwd):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],				# 7.64win no :
	[ 'vmhelp',		1, qr/^(Help):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],				# 7.64win no :
    ]},
    votercard =>           	{ textname => undef, type_out => 'note', fields => [
	[ 'votename',		0, qr/^(Name) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'votenumber',		1, qr/^(Voter Number):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'voteward',		1, qr/^(Ward):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],				# 7.64win no :
	[ 'voteprecinct',	1, qr/^(Precinct):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'voteissuedate',	1, qr/^(Issue Date):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'votelocation',	1, qr/^(Voting Location):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],		# 7.64win no :
	[ 'votecongress',	1, qr/^(Congress):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
	[ 'votesenate',		1, qr/^(State Senate):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],			# 7.64win no :
				# 7.64win "State Rep."; 7.3mac "State Rep:<newline>"Representative:"
	[ 'votestaterep2',	1, qr/^(State Rep)(?:\.|:\x{0a}Representative):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'voteurl',		0, qr/^(URL) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'votphone',		0, qr/^(Phone Number) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ]},
    website =>                  { textname => undef, type_out => 'login', fields => [
	[ 'Site Name',		1, qr/^(Site Name):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'username',		0, qr/^(User Name):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'password',		0, qr/^(Password) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'url',		0, qr/^(URL):? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'webother',		0, qr/^(Other) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'webphone',		0, qr/^(Phone Number) ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
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

=cut
    use open qw(:std :utf8);
    $/ = undef;
    $_ = <>;
=cut
    {
	local $/;
	open my $fh, '<:encoding(utf8)', $file or bail "Unable to open file: $file\n$!";
	$_   = <$fh>;
	close $fh;
    }

    my $n = 1;
    my ($npre_explode, $npost_explode);
    while (s/\A(Category: .+?)\x{0a}{2}((?:Category: .+$)|\Z)/$2/ms) {
	my $cards = $1;
	my ($card_tags, $card_folder);

	# Although categories can be nested in eWallet, there is no way to detect category hierarchy in the text export file.
	if ($cards =~ s/^Category: (.+?)(\x{0a}{2})/$2/ms) {
	    $card_tags = $1;
	    $card_folder = $1;
	    debug 'Category: ', $card_tags;
	}
	else {
	    # Another category immediately follows
	    debug 'Category: ', $cards;
	    next;
	}

	# Pull out and save the card notes for easier and less ambiguous field parsing, which are added back to the card later.
	my $note_index = 1;
	my @saved_notes = ();
	while ($cards =~ s/\x{0a}Card Notes\x{0a}{2}(.+?)(\x{0a}{2}|\Z)/\x{0a}__CARDNOTES__$note_index$2/ms) {
	    push @saved_notes, $1;
	    $note_index++;
	}

	$cards =~ s/^Card Type /__CARDTYPE__ /gms;				# for my own old ewallet data

	# Process each card
	while ($cards =~ s/\A\x{0a}{2}Card (.*?)(\x{0a}{2}Card|\Z)/$2/ms) {
	    my ($cardstr, $orig) = ($1, $1);
	    my ($card_title);

	    if ($cardstr =~ s/^([^\x{0a}]+)(?:\x{0a}|\Z)//ms) {			# card name
		debug "------  Card name: ", $1;
		$card_title = $1;
	    }
	    else {
		bail "Card name is missing in card entry\n", $orig;
	    }

	    my $itype = find_card_type($cardstr);

	    # skip all types not specifically included in a supplied import types list
	    next if defined $imptypes and (! exists $imptypes->{$itype});

	    # From the card input, place it in the converter-normal format.
	    # The card input will have matched fields removed, leaving only unmatched input to be processed later.
	    my $normalized = normalize_card_data($itype, \$cardstr, $card_title, $card_tags, \@saved_notes, $card_folder);

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
    }

    $n--;
    verbose "Imported $n card", pluralize($n) ,
	$npre_explode ? " ($npre_explode card" . pluralize($npre_explode) .  " expanded to $npost_explode cards)" : "";
    return \%Cards;
}

sub do_export {
    add_new_field('bankacct',     '_sortcode',    $Utils::PIF::sn_main,     $Utils::PIF::k_string,    'sort code');
    add_new_field('bankacct',     '_pin2',        $Utils::PIF::sn_main,     $Utils::PIF::k_concealed, 'pin2',		'generate'=>'off');
    add_new_field('membership',   'healthid',     $Utils::PIF::sn_main,     $Utils::PIF::k_string,    'ID number');
    add_new_field('membership',   'healthspon',   $Utils::PIF::sn_main,     $Utils::PIF::k_string,    'plan sponsor');
    add_new_field('membership',   'healthplan',   $Utils::PIF::sn_main,     $Utils::PIF::k_string,    'plan');
    add_new_field('membership',   'idusername',   $Utils::PIF::sn_main,     $Utils::PIF::k_string,    'user name');
    add_new_field('membership',   'insureco',     $Utils::PIF::sn_main,     $Utils::PIF::k_string,    'insurance company');
    add_new_field('membership',   'insurepol',    $Utils::PIF::sn_main,     $Utils::PIF::k_string,    'policy number');
    add_new_field('membership',   'insuretype',   $Utils::PIF::sn_main,     $Utils::PIF::k_string,    'insurance type');
    add_new_field('membership',   'insureagent',  $Utils::PIF::sn_main,     $Utils::PIF::k_string,    'agent');
    add_new_field('login',        'cellphonenum', 'other.Other Information',$Utils::PIF::k_string,    'phone number');
    add_new_field('login',        '_pin',	  'other.Other Information',$Utils::PIF::k_concealed, 'pin',		'generate'=>'off');
    add_new_field('login',        '_provider',	  'other.Other Information',$Utils::PIF::k_string,    'provider');
    add_new_field('login',        '_accessnum',	  'other.Other Information',$Utils::PIF::k_string,    'access number');
    add_new_field('login',        '_cardnum',	  'other.Other Information',$Utils::PIF::k_string,    'card number');
    add_new_field('login',        'cellpassword', 'other.Other Information',$Utils::PIF::k_concealed, 'cell password',	'generate'=>'off');
    add_new_field('login',        'cellseccode',  'other.Other Information',$Utils::PIF::k_concealed, 'security code',	'generate'=>'off');

    create_pif_file(@_);
}

sub find_card_type {
    my $c = shift;
    my $type;

    for $type (sort by_test_order keys %card_field_specs) {
	for my $def (@{$card_field_specs{$type}{'fields'}}) {
	    if (defined $def->[2] and $c =~ /$def->[2]/ms) {
		# type hint
		if ($def->[1]) {
		    debug "\t\ttype detected as '$type'";
		    return $type;
		}
	    }
	}
    }

    if ($c =~ /^User Name:?/ms and $c =~ /^Password /ms) {
	$type = ($c =~ /^System:? /ms or $c =~ /^PIN /ms or $c =~ /^Account Type /ms) ? 'password' : 'login';
    }
    else {
	$type = 'note';
    }

    debug "\t\ttype defaulting to '$type'";
    return $type;
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
    my ($type, $cardstr, $title, $tags, $saved_notes, $folder, $postprocess) = @_;
    my %norm_cards = (
	title	=> $title,
	tags	=> $tags,
	folder	=> [$folder],
    );

    if ($type eq 'note' and $$cardstr !~ /__CARDNOTES__/) {
	$norm_cards{'notes'} = $$cardstr;
	$$cardstr = '';
	goto OUT;
    }
    for my $def (@{$card_field_specs{$type}{'fields'}}) {
	my $h = {};
	if ($$cardstr =~ s/$def->[2]//ms) {
	    next if not defined $2 or $2 eq '';
	    my ($inkey, $value) = ($1, $2);
	    my $origvalue = $value;

	    if (exists $def->[3] and exists $def->[3]{'func'}) {
		#         callback(value, outkey)
		my $ret = ($def->[3]{'func'})->($value, $def->[0]);
		$value = $ret	if defined $ret;
	    }
	    $h->{'inkey'}	= $inkey;
	    $h->{'value'}	= $value;
	    $h->{'valueorig'}	= $origvalue;
	    $h->{'outkey'}	= $def->[0];
	    $h->{'outtype'}	= $def->[3]{'type_out'} || $card_field_specs{$type}{'type_out'} || $type; 
	    $h->{'keep'}	= $def->[3]{'keep'} // 0;
	    $h->{'to_title'}	= ' - ' . $h->{$def->[3]{'to_title'}}	if $def->[3]{'to_title'};
	    push @{$norm_cards{'fields'}}, $h;
	}
    }

    # notes field: tags, all unmapped fields, and card notes
    if ($$cardstr =~ s/^__CARDNOTES__(\d+)(?:\x{0a}|\Z)//ms) {		# the original card's notes
	my $note_index = $1 - 1;
	if (@$saved_notes) {
	    local $_ = $saved_notes->[$note_index];
	    s/\R+/\x{0a}/g;
	    s/\n+$//;
	    debug "\t\tNotes: ", $_;
	    $norm_cards{'notes'} = $_;
	}
    }

    if ($$cardstr ne '') {						# add unmatched stuff to the end of notes
	debug "\t\tUNMAPPED FIELDS: '$$cardstr'";
	defined $norm_cards{'notes'} and $norm_cards{'notes'} .= "\n";
	$norm_cards{'notes'} .= $$cardstr;
	$$cardstr = '';
    }

OUT:
    return \%norm_cards;
}

# sort logins as the last to check
sub by_test_order {
    return  1 if $a eq 'password';
    return -1 if $b eq 'password';
    return  1 if $a eq 'website';
    return -1 if $b eq 'website';
    $a cmp $b;
}

sub bankstrconv {
    return  'savings' 		if $_[0] =~ /sav/i;
    return  'checking'		if $_[0] =~ /check/i;
    return  'loc'		if $_[0] =~ /line|loc|credit/i;
    return  'amt'		if $_[0] =~ /atm/i;
    return  'money_market'	if $_[0] =~ /money|market|mm/i;
    return  'other';
}

# Date converters
# ewallet dates: m/d/yy: 9/1/15
# try to parse dates - date entry in eWallet is weak
# it seems to do some date validation on input
# older ewallets allowed mm/yy entry, but also might be junk text too
sub parse_date_string {
    local $_ = $_[0];
    my $when = $_[1] || 0;					# -1 = past only, 0 = assume this century, 1 = future only, 2 = 50-yr moving window

    if (/^(?<m>\d{1,2})\/(?<y>\d{2})$/ or			# older m/yy
	/^(?<m>\d{1,2})\/(?<d>\d{1,2})\/(?<y>\d{2})$/ or	# m/d/yyyy	7.64win
	/^(?<m>\d{1,2})\/(?<d>\d{1,2})\/(?<y>\d{4})$/) {	# m/d/yy	7.3mac
	my $days_today = Date_to_Days(@today);

	my $m = sprintf "%02d", $+{'m'};
	my $d = sprintf "%02d", $+{'d'} // "1";
	my $y = $+{'y'};
	for my $century (qw/20 19/) {
	    if (length $y eq 2) {
		$y = sprintf "%d%02d", $century, $y;
		$y = Moving_Window($y)	if $when == 2;
	    }
	    if (check_date($y, $m, $d)) {
		next if ($when == -1 and Date_to_Days($y,$m,$d) > $days_today);
		next if ($when ==  1 and Date_to_Days($y,$m,$d) < $days_today);
		return ($y, $m, $+{'d'} ? $d : undef);
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

1;
