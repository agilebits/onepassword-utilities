#!/usr/bin/perl

# Converts a LastPass CSV export into 1PIF format for importing into 1P4
#

use v5.14;
use utf8;
use strict;
use warnings;
use diagnostics;

binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

use Getopt::Long;
use File::Basename;
use Text::CSV;
use JSON::PP;
use UUID::Tiny ':std';
  
#use Data::Dumper;

my $version = '1.01';

my ($verbose, $debug);
my $progstr = basename($0);

# LastPass notes types:
#   bankaccount, creditcard, database=login, driverlicense, email=login, generic, healthinsurance, instantmessanger=login, membership=pass
#   passport, server=login, socialsecurity,softwarelicense, sshkey, wifi=password, insurance

my %typeMap = (
    bankacct =>		'wallet.financial.BankAccountUS',
    creditcard =>	'wallet.financial.CreditCard',
    database =>		'wallet.computer.Database',
    driverslicense =>	'wallet.government.DriversLicense',
    email =>		'wallet.onlineservices.Email.v2',
    membership =>	'wallet.membership.Membership',
    login =>		'webforms.WebForm',
    passport =>		'wallet.government.Passport',
    server =>		'wallet.computer.UnixServer',
    socialsecurity =>	'wallet.government.SsnUS',
    software =>		'wallet.computer.License',
    wireless =>		'wallet.computer.Router',
    note =>		'securenotes.SecureNote',
);

my %supported_types;
$supported_types{$_}++ for keys %typeMap;
my $supported_types = join ' ', sort keys %typeMap;

sub Usage {
    my $exitcode = shift;
    say @_ ? join('', @_, "\n") : '',
    <<ENDUSAGE, "\nStopped";
Usage: $progstr <options> <ewallet_export_text_file>
    options:
    --debug           | -d			# enable debug output
    --help	      | -h			# output help and usage text
    --outfile         | -o <converted.1pif>	# use file named converted.1pif as the output file
    --type            | -t <type list>		# comma separated list of one or more types from list below
    --verbose         | -v			# output operations more verbosely
    --[no]watchtower  | -w			# set each card's creation date to trigger Watchtower checks (default: on)

    supported types:
	- $supported_types
ENDUSAGE
    exit $exitcode;
}

my @save_ARGV = @ARGV;
my %opts = (
    outfile => join('/', $^O eq 'MSWin32' ? $ENV{'HOMEPATH'} : $ENV{'HOME'}, 'Desktop', '1P4_import'),
    watchtower => 1,
); 

sub debug {
    return unless $debug;
    printf "%-20s: %s\n", (split(/::/, (caller(1))[3] || 'main'))[-1], join('', @_);
}

sub verbose {
    return unless $verbose;
    say @_;
}

sub debug_on   { $debug++; }
sub verbose_on { $verbose++; }

my @opt_config = (
	'debug|d'	=> sub { debug_on() },
	'help|h'	=> sub { Usage(0) },
	'outfile|o=s',
	'type|t=s',
	'verbose|v'	=> sub { verbose_on() },
	'watchtower|w!'  => sub { $opts{$_[0]} = $_[1] },
);

{
local $SIG{__WARN__} = sub { say "\n*** ", $_[0]; };
Getopt::Long::Configure('no_ignore_case');
GetOptions(\%opts, @opt_config) or Usage(1);
}

debug "Command Line: @save_ARGV";
@ARGV == 1 or Usage(1);

if (exists $opts{'type'}) {
    my %t;
    for (split /\s*,\s*/, $opts{'type'}) {
	unless (exists $supported_types{$_}) {
	    Usage 1, "Invalid --type argument '$_'; see supported types.";
	}
	$t{$_}++;
    }
    $opts{'type'} = \%t;
}

my $file_suffix = '1pif';
if ($opts{'outfile'} !~ /\.${file_suffix}$/i) {
    $opts{'outfile'} = join '.', $opts{'outfile'}, $file_suffix;
}

my %card_match_patterns = (
    bankacct => [
	[ 'cardtype',		qr/^NoteType:(Bank Account)(?:\x{0a}|\Z)/ms ],
	[ 'bank',		qr/^Bank Name:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'accttype',		qr/^Account Type:([^\x{0a}]+)(?:\x{0a}|\Z)/ms, sub {return bankstrconv($_[0])} ],
	[ 'abarouting',		qr/^Routing Number:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'acctnum',		qr/^Account Number:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'swiftcode',		qr/^SWIFT Code:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'pin',		qr/^Pin:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'phone',		qr/^Branch Phone:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
     ],
    creditcard => [
	[ 'cardtype',		qr/^NoteType:(Credit Card)(?:\x{0a}|\Z)/ms ],
	[ 'cc_holder',		qr/^Name on Card:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'cc_type',		qr/^Type:([^\x{0a}]+)(?:\x{0a}|\Z)/ms, sub{return lc $_[0]} ],
	[ 'cc_number',		qr/^Number:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'cc_cvv',		qr/^Security Code:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ],
    database => [
	[ 'cardtype',		qr/^NoteType:(Database)(?:\x{0a}|\Z)/ms ],
	[ 'type',		qr/^Type:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'server',		qr/^Hostname:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'port',		qr/^Port:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'database',		qr/^Database:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'username',		qr/^Username:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'password',		qr/^Password:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'sid',		qr/^SID:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'alias',		qr/^Alias:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ],
    driverslicense => [
	[ 'cardtype',		qr/^NoteType:(Driver's License)(?:\x{0a}|\Z)/ms ],
	[ 'number',		qr/^Number:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'class',		qr/^License Class:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'name',		qr/^Name:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'address',		qr/^Address:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'state',		qr/^State:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'country',		qr/^Country:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'sex',		qr/^Sex:([^\x{0a}]+)(?:\x{0a}|\Z)/ms, sub{return $_[0] =~ /F/i ? 'female' : 'male'} ],
	[ 'height',		qr/^Height:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ],
    email => [
	[ 'cardtype',		qr/^NoteType:(Email Account)(?:\x{0a}|\Z)/ms ],
	[ 'username',		qr/^Username:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'password',		qr/^Password:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'popserver',		qr/^Server:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'smtpserver',		qr/^SMTP Server:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ],
    membership => [
	[ 'cardtype',		qr/^NoteType:(Membership|Health Insurance|Insurance)(?:\x{0a}|\Z)/ms ],
	[ 'organization',	qr/^(?:Organization|Company):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'memid',		qr/^(?:Membership Number|Member ID):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'polid',		qr/^Policy Number:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'grpid',		qr/^Group ID:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'membername',		qr/^Member Name:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'URL',		qr/^Website:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'phone',		qr/^(?:Telephone|Company Phone|Agent Phone):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'password',		qr/^Password:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ],
    login => [
	[ 'cardtype',		qr/^NoteType:(Instant Messenger)(?:\x{0a}|\Z)/ms ],
	[ 'username',		qr/^Username:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'password',		qr/^Password:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'URL',		qr/^(?:Hostname|Server):([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ],
    passport => [
	[ 'cardtype',		qr/^NoteType:(Passport)(?:\x{0a}|\Z)/ms ],
	[ 'pp_type',		qr/^Type:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'pp_fullname',	qr/^Name:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'pp_country',		qr/^Country:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'pp_number',		qr/^Number:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'pp_sex',		qr/^Sex:([^\x{0a}]+)(?:\x{0a}|\Z)/ms, sub{return $_[0] =~ /F/i ? 'female' : 'male'} ],
	[ 'pp_nationality',	qr/^Nationality:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'pp_authority',	qr/^Issuing Authority:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ],
    server => [
	[ 'cardtype',		qr/^NoteType:(Server)(?:\x{0a}|\Z)/ms ],
	[ 'hostname',		qr/^Hostname:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'username',		qr/^Username:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'password',		qr/^Password:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ],
    socialsecurity => [
	[ 'cardtype',		qr/^NoteType:(Social Security)(?:\x{0a}|\Z)/ms ],
	[ 'name',		qr/^Name:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'ss_number',		qr/^Number:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ],
    software => [
	[ 'cardtype',		qr/^NoteType:(Software License)(?:\x{0a}|\Z)/ms ],
	[ 'key',		qr/^License Key:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'version',		qr/^Version:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'publisher',		qr/^Publisher:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'support',		qr/^Support Email:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'URL',		qr/^Website:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'retail_price',	qr/^Price:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'order_number',	qr/^Order Number:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'order_total',	qr/^Order Total:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ],
    wireless => [
	[ 'cardtype',		qr/^NoteType:(Wi-Fi Password)(?:\x{0a}|\Z)/ms ],
	[ 'network_name',	qr/^SSID:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'wifi_password',	qr/^Password:([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ],
);

my %exp_card_fields;
for my $type (keys %supported_types) {
    $exp_card_fields{$type}{$_}++			for qw/title notes tags URL/;
}
for my $type (keys %card_match_patterns) {
    $exp_card_fields{$type}{$_->[0]}++			for @{$card_match_patterns{$type}};
}

my $Cards = import_csv($ARGV[0]);
export_pif($Cards);

sub import_csv {
    my $file = shift;
    my %Cards;

    sub pull_fields_from_note {
	my ($c, $notes) = @_;

	my $cardtype;
	for $cardtype (keys %card_match_patterns) {
	    my $card = $card_match_patterns{$cardtype};
	    if ($notes =~ s/$card->[0][1]//ms) {
		for (@{$card}[1..$#$card]) {
		    if ($notes =~ s/$_->[1]//ms) {
			# call the value-specific callback to modify the value if necessary
			$c->{$_->[0]} = $_->[2] ? $_->[2]->($1) : $1;
		    }
		}
		push @{$c->{'notes'}}, $notes;

		return $cardtype;
	    }
	}

	push @{$c->{'notes'}}, $notes;
	return 'note';
    }

    my $csv = Text::CSV->new ({ binary => 1, eol => "\x{a}", sep_char => ',', auto_diag => 1 });

    open my $io, "<:encoding(utf8)", $file or die "Failed to open CSV file: $file: $!\nStopped";

    # toss the header row
    {
	local $/ = "\x{0a}";
	my $header = <$io>; 
    }
    my $n = 1;
    while (my $row = $csv->getline ($io)) {
	if ($row->[0] eq '' and @$row == 1) {
	    warn "Skipping unexpected empty row: $n";
	    next;
	}

	my %card;
	debug 'ROW: ', $n;

	# Lastpass CSV field order
	#
	# URL, Username, Password, Extra, Name, Grouping, Favorite
	#
	# LastPass has two types: Site and Secure Note
	#
	# Extra contains lines of specific secure notes label:value pairs
	# Secure notes types will have URL = "http://sn"


	$card{'username'} = $row->[1]	if $row->[1] ne '';
	$card{'password'} = $row->[2]	if $row->[2] ne '';
	my $notes         = $row->[3]	if $row->[3] ne '';
	$card{'title'}    = $row->[4]	if $row->[4] ne '';
	$card{'tags'}     = $row->[5]	if $row->[5] ne '(none)';
	$card{'favorite'} = 'Yes'	if $row->[6] == 1;

	my $cardtype = $row->[0] eq 'http://sn' ? 'note' : 'login';
	if ($cardtype eq 'login') {
	    $card{'URL'}	  = $row->[0]	if $row->[0] ne '';
	    $card{'notes'}	  = $notes	if defined $notes;
	}
	else {
	    $cardtype = pull_fields_from_note(\%card, $notes);
	}

	push @{$Cards{$cardtype}}, \%card;
	$n++;
    }
    if (! $csv->eof()) {
	warn "Unexpected failure parsing CSV: row $n";
    }

    $n--;
    verbose "Imported $n card", ($n > 1 || $n == 0) ? 's' : '';

    return \%Cards;
}

sub export_pif {
    my $cardlist = shift;

    #open my $outfh, ">:encoding(utf8)", $opts{'outfile'} or
    open my $outfh, ">", $opts{'outfile'} or
	die "Cannot create 1pif output file: $opts{'outfile'}\n$!\nStopped";

    # href, key, k, n, t, v, a
    sub field_knta {
	my $h = shift, my $k = shift;
	my $sc;
	if (ref $h eq 'ARRAY') {
	    $sc = $h->[1]; $h = $h->[0];
	}
	return undef unless exists $h->{$k};

	my $href = { 'k' => shift, 'n' => shift, 't' => shift, 'v' => $h->{$k} };
	$href->{'a'} = { @_ }	if @_;
	$sc->{$href->{'n'}} = $h->{$k}	if defined $sc;
	delete $h->{$k};
	return $href;
    }
    sub new_section {
	my ($var, $key, $name, $title) = (shift, shift, shift, shift);
	my @a;
	for (@_) {
	    push @a, $_ if defined $_;
	}
	scalar @a and push @{$var->{$key}{'sections'}}, { name => $name, title => $title, fields => [ @a ] };
    }

    for my $type (keys %$cardlist) {
	next if exists $opts{'type'} and not exists $opts{'type'}{lc $type};
	my $n = scalar @{$cardlist->{$type}};
	verbose "Exporting $n $type item", ($n > 1 || $n == 0) ? 's' : '';

	for my $card (@{$cardlist->{$type}}) {
	    my (%f, $ret);
	    $f{'typeName'} = $typeMap{$type} // $typeMap{'note'};

	    if (exists $card->{'title'}) { $f{'title'} = $card->{'title'}; delete $card->{'title'}; }
	    if (exists $card->{'tags'}) { push @{$f{'openContents'}{'tags'}}, $card->{'tags'}; delete $card->{'tags'}; }

	    if ($type eq 'bankacct') {
		new_section(\%f, 'secureContents', '', '',
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'bank',           'string', 'bankName',          'bank name'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'accttype',       'menu',   'accountType',       'type'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'abarouting',     'string', 'routingNo',         'routing number'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'acctnum',        'string', 'accountNo',         'account number'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'swiftcode',      'string', 'swift',             'SWIFT'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'pin',         'concealed', 'telephonePin',      'PIN', 'generate'=>'off'));
		new_section(\%f, 'secureContents', 'branchInfo', 'Branch Information',
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'phone',          'string', 'branchPhone',       'phone'));
	    }
	    elsif ($type eq 'creditcard') {
		new_section(\%f, 'secureContents', '', '', 
		    field_knta($card, 'cc_holder', 'string',    'cardholder',     'cardholder name',     'guarded'=>'yes'),
		    field_knta($card, 'cc_type',   'cctype',    'type',           'type',                'guarded'=>'yes'),
		    field_knta($card, 'cc_number', 'string',    'ccnum',          'number',              'guarded'=>'yes', 'clipboardFilter'=>'0123456789'),
		    field_knta($card, 'cc_cvv',    'concealed', 'cvv',            'verification number', 'guarded'=>'yes', 'generate'=>'off'));
	    }
	    elsif ($type eq 'database') {
		new_section(\%f, 'secureContents', '', '', 
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'type',      'string',    'dbtype',   'database type'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'server',    'string',    'hostname', 'server'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'port',      'string',    'port',     'port'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'database',  'string',    'database', 'database'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'username',  'string',    'username', 'username'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'password',  'concealed', 'password', 'password'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'sid',       'string',    'sid',      'SID'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'alias',     'string',    'alias',    'alias'));
	    }
	    elsif ($type eq 'driverslicense') {
		new_section(\%f, 'secureContents', '', '', 
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'name',      'string',    'fullname',   'full name'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'address',   'string',    'address',    'address'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'sex',       'gender',    'sex',        'sex'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'height',    'string',    'height',     'height'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'number',    'string',    'number',     'number'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'class',     'string',    'class',      'license class'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'state',     'string',    'state',      'state'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'country',   'string',    'country',    'country'));
	    }
	    elsif ($type eq 'email') {
		new_section(\%f, 'secureContents', '', '',
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'popserver',      'string', 'pop_server',        'server'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'username',       'string', 'pop_username',      'username'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'password',     'concealed','pop_password',      'password'));
		new_section(\%f, 'secureContents', 'SMTP', 'SMTP',
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'smtpserver',     'string', 'smtp_server',       'SMTP server'));
	    }
	    elsif ($type eq 'membership') {
		new_section(\%f, 'secureContents', '', '',
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'organization',   'string', 'org_name',          'group'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'URL',            'URL',    'website',           'URL'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'phone',          'string', 'phone',             'telephone'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'membername',     'string', 'member_name',       'member name'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'memid',          'string', 'membership_no',     'member ID'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'polid',          'string', 'policy_id',         'policy ID'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'grpid',          'string', 'group_id',          'group ID'));
		new_section(\%f, 'secureContents', 'memberInfo', 'Other Information',
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'username',       'string', 'username',          'username'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'password',     'concealed','password',          'password'));
	    }
	    elsif ($type eq 'passport') {
		new_section(\%f, 'secureContents', '', '',
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'pp_country',     'string', 'issuing_country',   'issuing country'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'pp_number',      'string', 'number',            'number'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'pp_sex',         'gender', 'sex',               'sex'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'pp_fullname',    'string', 'fullname',          'full name'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'pp_type',        'string', 'type',              'type'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'pp_authority',   'string', 'issuing_authority', 'issuing authority'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'pp_nationality', 'string', 'nationality',       'nationality'));
	    }
	    elsif ($type eq 'server') {
		new_section(\%f, 'secureContents', '', '',
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'hostname',       'string', 'url',               'url'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'username',       'string', 'username',          'username'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'password',     'concealed','password',          'password'));
	    }
	    elsif ($type eq 'socialsecurity') {
		new_section(\%f, 'secureContents', '', '', 
		    field_knta( $card, 'name',      'string',    'name',       'name'),
		    field_knta( $card, 'ss_number', 'concealed', 'number',     'number', 'generate'=>'off'));
	    }
	    elsif ($type eq 'software') {
		new_section(\%f, 'secureContents', '', '',
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'version',        'string', 'product_version',   'version'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'label',          'string', 'name_label',        'name/label'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'number',         'string', 'number',            'number'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'key',            'string', 'reg_code',          'license key'));
		new_section(\%f, 'secureContents', 'publisher', 'Publisher',
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'URL',            'URL',    'download_link',     'download page'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'publisher',      'string', 'publisher_name',    'publisher'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'support',        'string', 'support',           'support'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'retail_price',   'string', 'retail_price',      'retail price'));
		new_section(\%f, 'secureContents', 'order', 'Order',
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'order_number',   'string', 'order_number',      'order number'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'purchasedate',   'string', 'purchase_date',     'purchase date'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'order_total',    'string', 'order_total',       'order total'));
	    }
	    elsif ($type eq 'wireless') {
		new_section(\%f, 'secureContents', '', '',
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'network_name',   'string', 'network_name',      'network name'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'wifi_password','concealed','password',          'wireless network password'));
	    }

	    # logins and notes have a different format, and this works as a nice catch all
	    if (exists $card->{'username'}) {
		push @{$f{'secureContents'}{'fields'}}, { designation => 'username', name => 'Username', type => 'T', value => $card->{'username'} };
		delete $card->{'username'};
	    }
	    if (exists $card->{'password'}) {
		push @{$f{'secureContents'}{'fields'}}, { designation => 'password', name => 'Password', type => 'P', value => $card->{'password'} };
		delete $card->{'password'};
	    }
	    if (exists $card->{'URL'}) {
		$f{'location'} = $card->{'URL'};
		push @{$f{'secureContents'}{'URLs'}}, { label => 'website', url => $card->{'URL'} };
		delete $card->{'URL'};
	    }

	    if (exists $card->{'notes'}) {
		$f{'secureContents'}{'notesPlain'} = ref($card->{'notes'}) eq 'ARRAY' ? join("\n", @{$card->{'notes'}}) : $card->{'notes'};
		delete $card->{'notes'};
	    }
	    for (keys %$card) {
		warn "Unmapped card field pushed to Notes: $_\n" if $_ ne 'favorite';
		$f{'secureContents'}{'notesPlain'} .= join ': ', "\n" . ucfirst $_, $card->{$_};
	    }

	    ($f{'uuid'} = create_uuid_as_string(UUID::Tiny->UUID_RANDOM(), 'cappella.us')) =~ s/-//g;
	    # set the creaated time to 1/1/2000 to help trigger Watchtower checks, unless --nowatchtower was specified
	    $f{'createdAt'} = 946713600		if $opts{'watchtower'};

	    my $encoded = encode_json \%f;
	    print $outfh $encoded, "\n", '***5642bee8-a5ff-11dc-8314-0800200c9a66***', "\n";
	}
    }
    close $outfh;

}

sub bankstrconv {
    local $_ = shift;
    return  'savings' 		if /sav/i;
    return  'checking'		if /check/i;
    return  'loc'		if /line|loc|credit/i;
    return  'amt'		if /atm/i;
    return  'money_market'	if /money|market|mm/i;
    return  'other';
}

sub print_record {
    my $h = shift;

    for my $key (keys $h) {
	print "\t$key: ";
	print "$_\n"  for (ref($h->{$key}) eq 'ARRAY' ? @{$h->{$key}} : $h->{$key});
    }
}

sub unfold_and_chop {
    local $_ = shift;

    return undef if not defined $_;
    s/\R/<CR>/g;
    my $len = length $_;
    return $_ ? (substr($_, 0, 77) . ($len > 77 ? '...' : '')) : '';
}

# For a given string parameter, returns a string which shows
# whether the utf8 flag is enabled and a byte-by-byte view
# of the internal representation.
#
sub hexdump
{
    use Encode qw/is_utf8/;
    my $str = shift;
    my $flag = Encode::is_utf8($str) ? 1 : 0;
    use bytes; # this tells unpack to deal with raw bytes
    my @internal_rep_bytes = unpack('C*', $str);
    return
        $flag
        . '('
        . join(' ', map { sprintf("%02x", $_) } @internal_rep_bytes)
        . ')';
}

# parts from module: Data::Uniqid;
use Math::BigInt;
use Sys::Hostname;
use Time::HiRes qw( gettimeofday usleep );

sub base62() { ################################################### Base62 #####
  my($s)=@_;
  my(@c)=('0'..'9','a'..'z','A'..'Z');
  my(@p,$u,$v,$i,$n);
  my($m)=20;
  $p[0]=1;  
  for $i (1..$m) {
    $p[$i]=Math::BigInt->new($p[$i-1]);
    $p[$i]=$p[$i]->bmul(62);
  }

  $v=Math::BigInt->new($s);
  for ($i=$m;$i>=0;$i--) {
    $v=Math::BigInt->new($v);
    ($n,$v)=$v->bdiv($p[$i]);
    $u.=$c[$n];
  }
  $u=~s/^0+//;
  
  return($u);
}

sub unique_id {
    my ($s,$us) = gettimeofday(); usleep(1);
    my ($ia,$ib,$ic,$id) = unpack("C4", (gethostbyname(hostname()))[4]);
    my ($v) = sprintf("%06d%10d%06d%03d%03d%03d%03d", $us,$s,$$,$ia,$ib,$ic,$id);
    return (&base62($v));
}

1;
