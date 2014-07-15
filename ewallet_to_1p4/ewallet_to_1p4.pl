#!/usr/bin/perl

# Converts an eWallet export into either a PIF or CSV format for importing into 1P4
#
# http://learn.agilebits.com/1Password4/Mac/en/KB/import.html#csv--comma-separated-values
# http://discussions.agilebits.com/discussion/comment/114976/#Comment_114976

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

my $version = '2.03';

my ($verbose, $debug);
my $progstr = basename($0);

my $supported_types_csv = 'login creditcard software note';
my $supported_types_pif = 'login creditcard software note socialsecurity passport email bankacct membership';
my %supported_types;
$supported_types{'csv'}{$_}++ for split(/\s+/, $supported_types_csv);
$supported_types{'pif'}{$_}++ for split(/\s+/, $supported_types_pif);

sub Usage {
    my $exitcode = shift;
    say @_ ? join('', @_, "\n") : '',
    <<ENDUSAGE, "\nStopped";
Usage: $progstr <options> <ewallet_export_text_file>
    options:
    --debug           | -d			# enable debug output
    --format	      | -f pif | csv		# output format: pif (default) or csv
    --help	      | -h			# output help and usage text
    --outfile         | -o <converted.csv>	# use file named converted.csv as the output file
    --type            | -t <type list>		# comma separated list of one or more types from list below
    --verbose         | -v			# output operations more verbosely
    --[no]watchtower  | -w			# set each card's creation date to trigger WatchTower checks (default: on)

    supported types:
	- for csv: $supported_types_csv
	- for pif: $supported_types_pif
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
	'debug|d'	 => sub { debug_on() },
	'format|f=s'	 => sub { $opts{$_[0]} = lc $_[1]; $_[1] =~ /^(?:pif|csv)$/i or die "Invalid --format argument '$_[1]'\nStopped" },
	'help|h'	 => sub { Usage(0) },
	'outfile|o=s',
	'type|t=s',
	'verbose|v'	 => sub { verbose_on() },
	'watchtower|w!'  => sub { $opts{$_[0]} = $_[1] },
);

{
local $SIG{__WARN__} = sub { say "\n*** ", $_[0]; };
Getopt::Long::Configure('no_ignore_case');
GetOptions(\%opts, @opt_config) or Usage(1);
}

debug "Command Line: @save_ARGV";
@ARGV == 1 or Usage(1);

$opts{'format'} ||= 'pif';

if (exists $opts{'type'}) {
    my %t;
    for (split /\s*,\s*/, $opts{'type'}) {
	unless (exists $supported_types{$opts{'format'}}{$_}) {
	    Usage 1, "Invalid --type argument '$_'; see supported types.";
	}
	$t{$_}++;
    }
    $opts{'type'} = \%t;
}

(my $file_suffix = $opts{'format'}) =~ s/pif/1pif/;
if ($opts{'outfile'} !~ /\.${file_suffix}$/i) {
    $opts{'outfile'} = join '.', $opts{'outfile'}, $file_suffix;
}

my %typeMap = (
    note =>		'securenotes.SecureNote',
    socialsecurity =>	'wallet.government.SsnUS',
    passport =>		'wallet.government.Passport',
    software =>		'wallet.computer.License',
    creditcard =>	'wallet.financial.CreditCard',
    email =>		'wallet.onlineservices.Email.v2',
    bankacct =>		'wallet.financial.BankAccountUS',
    membership =>	'wallet.membership.Membership',
    login =>		'webforms.WebForm',
);

my %card_match_patterns = (
    socialsecurity => [
	[ 'ss_number',		0, 1, qr/^Social Security Number ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'ss_type',		0, 0, qr/^Acount Number ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'name',		0, 0, qr/^Name (?!(?:on Card|Server))([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'username',		0, 0, qr/^User Name ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'password',		0, 0, qr/^Password ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ],
    passport => [
	[ 'pp_type',		0, 0, qr/^Type: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'pp_country',		0, 0, qr/^Code of issuing state: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'pp_number',		0, 1, qr/^Passport Number: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'pp_sex',		0, 0, qr/^Sex: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms, sub{return $_[0] =~ /F/i ? 'female' : 'male'} ],
	[ 'pp_fullname',	0, 0, qr/^Given Names: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'pp_birthdate',	0, 0, qr/^Birth Date: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'pp_birthplace',	0, 0, qr/^Birth place: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'pp_nationality',	0, 1, qr/^Nationality: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'pp_issued',		0, 0, qr/^Issued: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'expires',		0, 0, qr/^Expires: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'pp_authority',	0, 1, qr/^Authority: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ],
    software => [
	[ 'title2',		0, 0, qr/^Title ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'publisher',		8, 0, qr/^Manufacturer: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'version',		2, 1, qr/^Version: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'label',		0, 1, qr/^Name\/Label ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'number',	       13, 0, qr/^Number (?!of Refills)([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'name',		4, 0, qr/^Name: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'key',		3, 1, qr/^Key: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'purchasedate',	0, 0, qr/^Purchase Date: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'purchasefrom',	0, 0, qr/^Purchased From: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'support',	       11, 0, qr/^Support: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'partnum',		0, 0, qr/^Part Number ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'softlocation',	6, 0, qr/^Location ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'URL',		9, 0, qr/^URL ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'username',		5, 0, qr/^User Name ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'password',		0, 0, qr/^Password ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'phonenum',		0, 0, qr/^Phone Number ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'Download Link',	7, 0, undef ],
	[ 'Retail Price',      10, 0, undef ],
	[ 'Purchase Date',     12, 0, undef ],
    ],
    creditcard => [
	[ 'cc_bank',		6, 0, qr/^Card Provider ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'cc_type',		0, 0, qr/^Credit Card Type ([^\x{0a}]+)(?:\x{0a}|\Z)/ms, sub{return lc $_[0]} ],
	[ 'cc_number',		2, 1, qr/^Card Number ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'expires',		0, 0, qr/^Expires: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'pin',		5, 0, qr/^PIN ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'cc_holder',		4, 1, qr/^Name on Card ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'cc_phone',		0, 0, qr/^If card is lost or stolen call: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'startdate',		0, 0, qr/^Start Date ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'cc_cvv',		7, 1, qr/^3-digit CVC# ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'URL',		0, 0, qr/^URL ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'username',		0, 0, qr/^User Name ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'password',		0, 0, qr/^Password ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'Card Expires',	3, 0, undef ],
    ],
    email => [
	[ 'system',		0, 0, qr/^System: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'username',		0, 0, qr/^User Name ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'password',		0, 0, qr/^Password ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'smtpserver',		0, 1, qr/^Outgoing SMTP Server: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'popserver',		0, 1, qr/^Incoming Pop Server: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'accessphone',	0, 0, qr/^Access Phone Number: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'URL',		0, 0, qr/^Support URL: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'supportphone',	0, 0, qr/^Support Phone: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
    ],
    bankacct => [
	[ 'bank',		0, 1, qr/^Bank Name ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'phone',		0, 0, qr/^Telephone ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'accttype',		0, 0, qr/^Account Type ([^\x{0a}]+)(?:\x{0a}|\Z)/ms, sub {return bankstrconv($_[0])} ],
	[ 'acctnum',		0, 0, qr/^Account Number ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'pin',		0, 0, qr/^PIN ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'sortcode',		0, 0, qr/^Sort Code ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'swiftcode',		0, 0, qr/^SWIFT Code ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'abarouting',		0, 0, qr/^ABA\/Routing # ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'pin2',		0, 0, qr/^PIN2 ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'URL',		0, 0, qr/^URL ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'username',		0, 0, qr/^User Name ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'password',		0, 0, qr/^Password ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
     ],
    membership => [
	[ 'organization',	0, 1, qr/^Organization ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'idnum',		0, 0, qr/^ID Number: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'phone',		0, 0, qr/^Telephone: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'expires',		0, 0, qr/^Expires On: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'URL',		0, 0, qr/^URL ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'username',		0, 0, qr/^User Name ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'password',		0, 0, qr/^Password ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'pin',		0, 0, qr/^PIN ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'points',		0, 0, qr/^Points\/Miles to Date ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
     ],
    login => [
	[ 'Site Name',		0, 0, qr/^Site Name: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'URL',		2, 0, qr/^URL:? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'username',		3, 0, qr/^User Name: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'password',		4, 0, qr/^Password ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
     ],
);

my %exp_card_fields;
if ($opts{'format'} eq 'pif') {
    for my $type (keys $supported_types{'pif'}) {
	$exp_card_fields{$type}{$_}++				for qw/title notes tags URL/;
    }
    for my $type (keys %card_match_patterns) {
	$exp_card_fields{$type}{$_->[0]}++			for @{$card_match_patterns{$type}};
    }
}
else {
    for my $type (keys $supported_types{'csv'}) {
	$exp_card_fields{$type}{'title'} = 1;
	$_->[1] and $exp_card_fields{$type}{$_->[0]} = $_->[1]	for @{$card_match_patterns{$type}};
	$exp_card_fields{$type}{'notes'} = 1 + keys $exp_card_fields{$type};
    }
}

my $Cards = import_txt();
export_pif($Cards) if $opts{'format'} eq 'pif';
export_csv($Cards) if $opts{'format'} eq 'csv';

sub import_txt {
    my %Cards;

    # sort logins as the last to check
    sub by_test_order {
	return  1 if $::a eq 'login';
	return -1 if $::b eq 'login';
	$::a cmp $::b;
    }

    sub check_match_and_set {
	my ($type, $c, $card) = @_;
	return 0 unless exists $card_match_patterns{$type};

	my $ret = 0;
	for (@{$card_match_patterns{$type}}) {
	    if (defined $_->[3] and $$card =~ s/$_->[3]//ms) {
		debug "\t\t$_->[0]: ", $1;
		# call the value-specific callback to modify the value if necessary
		$c->{$_->[0]} = $_->[4] ? $_->[4]->($1) : $1;
		$_->[2] and $ret = 1;		# return 1 to indicate it is OK to set the card type
	    }
	}
	return $ret;
    }

    use open qw(:std :utf8);
    $/ = undef;
    $_ = <>;

    my $n = 1;
    while (s/\A(Category: .+?)\x{0a}{2}((?:Category: .+$)|\Z)/$2/ms) {
	my $cards = $1;
	my $category;

	if ($cards =~ s/^Category: (.+?)(\x{0a}{2})/$2/ms) {
	    $category = $1;
	    debug 'Category: ', $category;
	}
	else {
	    # Another category immediately follows
	    debug 'Category: ', $cards;
	    next;
	}
	my $notesnum = 1;
	my @notes = ();
	while ($cards =~ s/\x{0a}Card Notes\x{0a}{2}(.+?)(\x{0a}{2}|\Z)/\x{0a}__CARDNOTES__$notesnum$2/ms) {
	    push @notes, $1;
	    $notesnum++;
	}
	$cards =~ s/^Card Type /__CARDTYPE__ /gms;
	while ($cards =~ s/\A\x{0a}{2}Card (.*?)(\x{0a}{2}Card|\Z)/$2/ms) {
	    my ($card, $orig) = ($1, $1);
	    my %c;
	    my $type;

	    debug "CARD: '$card'";

	    if ($card =~ s/^([^\x{0a}]+)(?:\x{0a}|\Z)//ms) {			# card name
		debug "------  Card name: ", $1;
		$c{'title'} = $1;
	    }
	    else {
		die "Card name is missing in card entry\n", $card;
	    }
=cut
	    if ($card =~ s/^Site Name: ([^\x{0a}]+)\x{0a}//ms) {		# site name, overrides card name when it differs
		if ($1 and $1 ne $c{'title'}) {
		    debug "\t\tSite name: ", $1;
		    $c{'title'} = $1;
		}
	    }
=cut

	    # Check for each card type using the card_match_patterns table
	    for (sort by_test_order keys %card_match_patterns) {
		if (check_match_and_set($_, \%c, \$card)) {
		    $type = $_;
		    last;
		}
	    }
	    if ($type and not exists $supported_types{$opts{'format'}}{$type}) {
		$type = undef;
	    }

	    # When type isn't set already, it is a login if username and password exists;
	    # otherwise, everything else is a note.
	    $type ||= (exists $c{'username'} and exists $c{'password'}) ? 'login' : 'note';
	    debug "\tCard Type: ", $type;

	    # notes field: category, all unmapped fields, and card notes
	    if ($category ne '') {
		if ($opts{'format'} eq 'csv') {
		    push @{$c{'notes'}}, 'Category: ' . $category;		# add the card's category to notes
		}
		else {
		    $c{'tags'} = $category;					# card's category becomes a Tag
		}
	    }
	    if ($card =~ s/^__CARDNOTES__\d+(?:\x{0a}|\Z)//ms) {		# the original card's notes
		if (@notes) {
		    $notes[0] =~ s/\R+/\x{0a}/g;
		    $notes[0] =~ s/\n+$//;
		    debug "\t\tNotes: ", $notes[0];
		    push @{$c{'notes'}}, shift @notes;
		}
	    }

	    # Move to notes any key/value pairs that don't belong in the export type
	    for (keys %c) {
		if (!exists $exp_card_fields{$type}{$_}) {
		    debug "\tPUSHING key/value to notes: $_: $c{$_}";
		    push @{$c{'notes'}}, join ': ', ucfirst $_, $c{$_};
		    delete $c{$_};
		}
	    }

	    if ($card ne '') {							# add unmapped stuff to the end of notes
		debug "\t\tUNMAPPED FIELDS: '", $card, "'";
		exists $c{'notes'} and push @{$c{'notes'}}, "\n";
		push @{$c{'notes'}}, $card;
	    }

	    debug "";

	    push @{$Cards{$type}}, { %c };

	    $debug and print_record(\%c);
	    $n++;
	}
    }

    $n--;
    verbose "Imported $n card", ($n > 1 || $n == 0) ? 's' : '';
    return \%Cards;
}

sub export_pif {
    my $cardlist = shift;

    open my $outfh, ">:encoding(utf8)", $opts{'outfile'} or
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

	    if ($type eq 'socialsecurity') {
		new_section(\%f, 'secureContents', '', '', 
		    field_knta( $card, 'name',      'string',    'name',       'name'),
		    field_knta( $card, 'ss_number', 'concealed', 'number',     'number', 'generate'=>'off'),
		    field_knta( $card, 'username',  'string',    'username',   'username'),
		    field_knta( $card, 'password',  'concealed', 'password',   'password'));
	    }
	    elsif ($type eq 'creditcard') {
		if (exists $card->{'expires'}) {
		    #ewallet: m/d/yy: 9/1/15; -> "expiry_mm":"9", "expiry_yy":"2015",
		    # older ewallets allowed mm/yy entry, but also might be junk text too, in which case
		    # expires goes to notes.
		    if ($card->{'expires'} =~ m!^\d{1,2}/\d{1,2}(?:/\d{2})?$!) {
			my ($m,$d,$y) = split '/', $card->{'expires'};
			if (defined $d) {
			    $y ||= $d;
			    $f{'secureContents'}{'expiry_mm'} = $m;
			    $f{'secureContents'}{'expiry_yy'} = '20' . $y;
			    $card->{'expires'} = sprintf "%d%02d", $y, $f{'secureContents'}{'expiry_yy'}, $m;
			}
		    }
		    else {
			# create dummy entry so that non-date looking expires gets mapped to notes
			$card->{'Expires'} = $card->{'expires'};
		    }
		}
		new_section(\%f, 'secureContents', '', '', 
		    field_knta($card, 'cc_holder', 'string',    'cardholder',     'cardholder name',     'guarded'=>'yes'),
		    field_knta($card, 'cc_type',   'cctype',    'type',           'type',                'guarded'=>'yes'),
		    field_knta($card, 'cc_number', 'string',    'ccnum',          'number',              'guarded'=>'yes', 'clipboardFilter'=>'0123456789'),
		    field_knta($card, 'cc_cvv',    'concealed', 'cvv',            'verification number', 'guarded'=>'yes', 'generate'=>'off'),
		    field_knta($card, 'expires',   'monthYear', 'expiry',         'expiry date',         'guarded'=>'yes'),
		    field_knta($card, 'startdate', 'string',    'startdate',      'start date'));
		new_section(\%f, 'secureContents', 'contactInfo', 'Contact Information',
		    field_knta($card, 'cc_bank',   'string',    'bank',          'issuing bank'),
		    field_knta($card, 'cc_phone',  'phone',     'phoneTollFree', 'phone (toll free)'),
		    field_knta($card, 'URL',       'URL',       'website',       'website'),
		    field_knta($card, 'username',  'string',    'username',      'username'),
		    field_knta($card, 'password',  'concealed', 'password',      'password'));

		new_section(\%f, 'secureContents', 'details', 'Additional Details',
		    field_knta($card, 'pin',       'concealed', 'pin',           'PIN', 'generate'=>'off'));

	    }
	    elsif ($type eq 'passport') {
		new_section(\%f, 'secureContents', '', '',
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'pp_country',     'string', 'issuing_country',   'issuing country'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'pp_number',      'string', 'number',            'number'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'pp_birthplace',  'string', 'birthplace',        'place of birth'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'pp_sex',         'gender', 'sex',               'sex'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'pp_fullname',    'string', 'fullname',          'full name'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'pp_type',        'string', 'type',              'type'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'pp_authority',   'string', 'issuing_authority', 'issuing authority'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'pp_nationality', 'string', 'nationality',       'nationality'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'expires',        'string', 'pp_expires',        'date expires'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'pp_issued',      'string', 'pp_issued',         'date issued'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'pp_birthdate',   'string', 'pp_birthdate',      'birth date'));
	    }
	    elsif ($type eq 'software') {
		new_section(\%f, 'secureContents', '', '',
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'title2',         'string', 'title2',            'software title'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'version',        'string', 'product_version',   'version'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'label',          'string', 'name_label',        'name/label'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'number',         'string', 'number',            'number'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'softlocation',   'string', 'software_loc',      'software location'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'key',            'string', 'reg_code',          'license key'));
		new_section(\%f, 'secureContents', 'customer', 'Customer',
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'name',           'string', 'reg_name',          'licensed to'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'username',       'string', 'username',          'username'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'password',    'concealed', 'password',          'password'));
		new_section(\%f, 'secureContents', 'publisher', 'Publisher',
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'URL',            'URL',    'download_link',     'download page'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'publisher',      'string', 'publisher_name',    'publisher'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'support',        'string', 'support',           'support'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'phonenum',       'string', 'phonenum',          'phone number'));
		new_section(\%f, 'secureContents', 'order', 'Order',
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'partnum',        'string', 'partnum',           'part number'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'purchasedate',   'string', 'purchase_date',     'purchase date'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'purchasefrom',   'string', 'purchase_from',     'purchase from'));
	    }
	    elsif ($type eq 'email') {
		new_section(\%f, 'secureContents', '', '',
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'popserver',      'string', 'pop_server',        'server'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'username',       'string', 'pop_username',      'username'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'password',     'concealed','pop_password',      'password'));
		new_section(\%f, 'secureContents', 'SMTP', 'SMTP',
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'smtpserver',     'string', 'smtp_server',       'SMTP server'));
		new_section(\%f, 'secureContents', 'Contact Information', 'Contact Information',
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'system',         'string', 'provider',          'provider'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'URL',            'URL',    'provider_website', 'provider\'s website'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'accessphone',    'string', 'access_phone',      'access phone'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'supportphone',   'string', 'support_phone',     'support phone'));
	    }
	    elsif ($type eq 'bankacct') {
		new_section(\%f, 'secureContents', '', '',
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'bank',           'string', 'bankName',          'bank name'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'accttype',       'menu',   'accountType',       'type'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'abarouting',     'string', 'routingNo',         'routing number'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'acctnum',        'string', 'accountNo',         'account number'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'swiftcode',      'string', 'swift',             'SWIFT'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'sortcode',       'string', 'sortcode',          'sort code'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'pin',         'concealed', 'telephonePin',      'PIN', 'generate'=>'off'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'pin2',        'concealed', 'pin2',              'pin other', 'generate'=>'off'));

		new_section(\%f, 'secureContents', 'bankWebInfo', 'Website Information',
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'URL',            'URL',    'website',           'website'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'username',       'string', 'username',          'username'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'password',     'concealed','password',          'password'));

		new_section(\%f, 'secureContents', 'branchInfo', 'Branch Information',
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'phone',          'string', 'branchPhone',       'phone'));
	    }
	    elsif ($type eq 'membership') {
		new_section(\%f, 'secureContents', '', '',
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'organization',   'string', 'org_name',          'group'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'URL',            'URL',    'website',           'URL'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'phone',          'string', 'phone',             'telephone'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'expires',        'string', 'expiresstr',        'expires'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'idnum',          'string', 'membership_no',     'member ID'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'pin',         'concealed', 'pinx',              'pin', 'generate'=>'off'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'points',         'string', 'points',            'points'));
		new_section(\%f, 'secureContents', 'memberInfo', 'Other Information',
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'username',       'string', 'username',          'username'),
		    field_knta([ $card, \%{$f{'secureContents'}} ], 'password',     'concealed','password',          'password'));
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
		warn "UNMAPPED FIELD $_\n" if ($_ ne 'Site Name' and $_ ne 'Expires');
		$f{'secureContents'}{'notesPlain'} .= join ': ', "\n" . ucfirst $_, $card->{$_};
	    }

	    ($f{'uuid'} = create_uuid_as_string(UUID::Tiny->UUID_RANDOM(), 'cappella.us')) =~ s/-//g;
	    # set the creaated time to 1/1/2000 to help trigger WatchTower checks, unless --nowatchtower was specified
	    $f{'createdAt'} = 946713600		if $opts{'watchtower'};

	    my $encoded = encode_json \%f;
	    print $outfh $encoded, "\n", '***5642bee8-a5ff-11dc-8314-0800200c9a66***', "\n";
	}
    }
    close $outfh;

}

sub export_csv {
    my $cardlist = shift;

    for my $type (keys %$cardlist) {
	next if exists $opts{'type'} and not exists $opts{'type'}{lc $type};

	my @sorted;
	push @sorted, 'title';
	for (@{$card_match_patterns{$type}}) {
	    $sorted[$_->[1] - 1] = $_->[0]	if $_->[1];
	}
	push @sorted, 'notes';

	my $n = scalar @{$cardlist->{$type}};
	verbose "Exporting $n $type item", ($n > 1 || $n == 0) ? 's' : '';

	my $csv = Text::CSV->new ( { binary => 1, sep_char => ',' } );

	(my $file = $opts{'outfile'}) =~ s/\.csv$/_$type.csv/;
	open my $outfh, ">:encoding(utf8)", $file or die "Cannot create output file: $file\n$!\nStopped";
	for my $card (@{$cardlist->{$type}}) {
	    my @row;
	    for my $col (@sorted) {
		push @row, !exists $card->{$col} ? ''
			      : ref($card->{$col}) eq 'ARRAY'
			      ? join("\n", @{$card->{$col}}) : $card->{$col};
	    }
	    $csv->combine(@row) or die "Failed to combine card fields into a CSV string\nStopped";
	    print $outfh $csv->string(), "\r\n";
	    debug $csv->string();
	}
	close $outfh;
    }
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
