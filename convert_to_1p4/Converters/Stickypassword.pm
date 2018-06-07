# Sticky Password XML export converter
#
# Copyright 2016 Mike Cappella (mike@cappella.us)

package Converters::Stickypassword 1.01;

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
use Time::Local qw(timelocal timegm);
use Time::Piece;
use Encode;
use RTF::Tokenizer;

my %card_field_specs = (
    appaccount =>               { textname => '', type_out => 'login', fields => [
	[ 'username',		0, 'username', ],
	[ 'password',		0, 'password', ],
	[ 'path',		0, 'program path', ],
    ]},
    bookmark =>                 { textname => '', type_out => 'login', fields => [
	[ 'url',		0, 'url', ],
    ]},
    bankacct =>                 { textname => '', fields => [
	[ 'bankName',		0, 'bankName', ],
	[ 'accountNo',		0, 'accountNo', ],
	[ 'accountType',	0, 'accountType', ],
	[ 'routingNo',		0, 'routingNo', ],
	[ 'branch',		0, 'branch', ],
	[ 'branchPhone',	0, 'branchPhone', ],
	[ 'branchAddress',	0, 'branchAddress', ],
	[ 'swift',		0, 'swift', ],
	[ 'owner',		0, 'owner', ],
	[ 'telephonePin',	0, 'telephonePin', ],
    ]},
    creditcard =>               { textname => '', fields => [
	[ 'type',		0, 'type', ],
	[ 'ccnum',		0, 'ccnum', ],
	[ 'cvv',		0, 'cvv', ],
	[ 'expiry',		0, 'expiry', 				{ func => sub { return date2monthYear($_[0]) } } ],
	[ 'validFrom',		0, 'validFrom',				{ func => sub { return date2monthYear($_[0]) } } ],
	[ 'cardholder',		0, 'cardholder', ],
	[ 'bank',		0, 'bank', ],
	[ 'phoneTollFree',	0, 'phoneTollFree', ],
	[ 'phoneIntl',		0, 'phoneIntl', ],
	[ 'pin',		0, 'pin', ],
    ]},
    identity =>                 { textname => '', fields => [
	[ 'firstname',		0, 'firstname', ],
	[ 'lastname',		0, 'lastname', ],
	[ 'sex',		0, 'sex', ],
	[ 'birthdate',		0, 'birthdate',				{ func => sub { return date2epoch($_[0], 'local') } } ],
	[ 'homephone',		0, 'homephone', ],
	[ 'cellphone',		0, 'cellphone', ],
	[ 'website',		0, 'website', ],
	[ 'email',		0, 'email', ],
	[ 'yahoo',		0, 'yahoo', ],
	[ 'msn',		0, 'msn', ],
	[ 'aim',		0, 'aim', ],
	[ 'skype',		0, 'skype', ],
	[ 'icq',		0, 'icq', ],
	[ 'reminderq',		0, 'reminderq', ],
	[ 'remindera',		0, 'remindera', ],
	[ 'company',		0, 'company', ],
	[ 'department',		0, 'department', ],
	[ 'jobtitle',		0, 'jobtitle', ],
	[ 'busphone',		0, 'busphone', ],
	[ 'address',		0, 'address', ],
	[ '_marital_status',	0, 'marital status',			{ func => sub { return maritalstatus($_[0]) } } ],
    ]},
    securememo =>               { textname => '', type_out => 'note', fields => [
    ]},
    webaccount =>               { textname => undef, type_out => 'login', fields => [
	[ 'username',		0, 'username', ],
	[ 'password',		0, 'password', ],
	[ 'url',		0, 'url', ],
	[ '_email',		0, 'email', ],
    ]},
);

my %rvid_to_key = (
# identity role values
    1 => "person title",
    2 => "firstname",
    3 => "middle name",
    4 => "lastname",
    5 => "sex",
    6 => "birthdate",
    7 => "place of birth",
    8 => "homephone",
    9 => "cellphone",
    10 => "fax",
    11 => "website",
    12 => "email",
    13 => "check hide email",
    14 => " receive newsletter",
    15 => "yahoo",
    16 => "msn",
    17 => "aim",
    18 => "skype",
    19 => "icq",
    20 => "preferred login",
    21 => "reminderq",
    22 => "remindera",
    23 => "_country",
    24 => "city",
    25 => "(id 25)",	#  ?
    26 => "zip",
    27 => "addr_line_1",
    28 => "addr_line_2",
    29 => "language",
    30 => "timezone (hrs from UTC)",
    31 => "currency",
    32 => "company",
    33 => "department",
    34 => "jobtitle",
    35 => "busphone",
    36 => "company website",

# credit card role values
    37 => "type",		# Visa,MasterCard,American Express,Diners Club,Discover,JCB,Carte Bancaire,Carte Blanche,Delta,Solo,Switch,Maestro,UATP
    38 => "ccnum",
    39 => "cvv",
    40 => "expiry",
    41 => "validFrom",
    42 => "cardholder",
    43 => "bank",
    44 => "phoneTollFree",
    45 => "phoneIntl",
    46 => "pin",

# bank account role values
    47 => "bankName",
    48 => "accountNo",
    49 => "accountType",	# 0=unspecified, 1=checking, 2=savings, 3=money manager
    50 => "routingNo",
    51 => "branch",
    52 => "branchPhone",
    53 => "branchAddress",
    54 => "swift",
    55 => "owner",
    56 => "telephonePin",

# identity role values, continued
    57 => "payment method",
    58 => "marital status",
    59 => "vat number",
    60 => "company id",
    61 => "bank account",
);


$DB::single = 1;					# triggers breakpoint when debugging

my %groupid_map;

sub do_init {
    return {
	'specs'		=> \%card_field_specs,
	'imptypes'  	=> undef,
    };
}

sub do_import {
    my ($file, $imptypes) = @_;
    my %Cards;

    #$^O = 'MSWin32';			# enable for testing Windows exports on OS X

    $_ = slurp_file($file, $^O eq 'MSWin32' ? 'UTF-16LE' : 'UTF-8');

    # the file has already been slurped, and is in UTF-8 Perl internal form now,
    # so change the encoding in the XML declaration to match.
    s/UTF-16/UTF-8/;

    my $n = 1;

    my $xp = XML::XPath->new(xml => $_);

    my @entries = get_all_entries($xp);
    while (my $e = shift @entries) {
	my $itype	= $e->{'itype'};
	my @fieldlist	= exists $e->{'fieldlist'} ? @{$e->{'fieldlist'}} : ();
	my %cmeta	= %{$e->{'cmeta'}};

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

sub get_all_entries {
    my ($xp) = @_;

    my (@entries, %groups, %logins, $nodes);

    $nodes = $xp->findnodes('//Groups/Group | //SecureMemoGroups/Group');
    foreach my $node (@$nodes) {
	$groups{$node->getAttribute('ID')} = $node->getAttribute('Name');
	debug "\tprocessed group: ", $groups{$node->getAttribute('ID')};
    }

    # Memos
    $nodes = $xp->findnodes('//SecureMemos/SecureMemo');
    foreach my $node (@$nodes) {
	my %e;
	$e{'itype'} = 'securememo';
	set_common_attributes($node, \%e, \%groups);

	my $rtfnote = decode('UTF-16LE', pack('H*', $node->string_value));
	$e{'cmeta'}{'notes'} = rtf_decode($rtfnote);

	push @entries, \%e;
	debug "\tprocessed secure memo: ", $e{'cmeta'}{'title'};
    }

    # Logins
    $nodes = $xp->findnodes('//Logins/Login');
    foreach my $node (@$nodes) {
	my $reallogin   = $node->getAttribute('RealLogin');
	my $description = $node->getAttribute('Name');
	my $username = (not defined $reallogin or $reallogin eq '') ? $description : $reallogin;
	$logins{$node->getAttribute('ID')} = [ $username, $node->getAttribute('Password'), 
	    (defined $reallogin and $reallogin ne '') ? $description : undef ];
	debug "\tprocessed login: ", $logins{$node->getAttribute('ID')}[0];
    }

    # Accounts
    $nodes = $xp->findnodes('//Accounts/Account');
    foreach my $node (@$nodes) {
	my %e;
	set_common_attributes($node, \%e, \%groups);
	my $url   =  $node->getAttribute('Link');
	my $notes = $node->getAttribute('Comments');
	$notes =~ s/\/n/\n/g	if defined $notes;

	my $loginnodes = $xp->findnodes('./LoginLinks/Login', $node);

	# bookmarks
	if ($loginnodes->size == 0) {
	    $e{'itype'} = 'bookmark';
	    push @{$e{'fieldlist'}}, [ 'url', $url ];
	    push @entries, \%e;
	    debug "\tprocessed bookmark: ", $e{'cmeta'}{'title'};
	    next;
	}

	# web logins, app accounts
	foreach my $loginnode (@$loginnodes) {
	    my %ee;

	    %{$ee{'cmeta'}} = %{$e{'cmeta'}};
	    @{$ee{'fieldlist'}} = exists $e{'fieldlist'} ? @{$e{'fieldlist'}} : ();
	    $ee{'cmeta'}{'notes'} = $notes;

	    if ($node->getAttribute('LinkDriveSerialNumber')) {		# app accounts
		$ee{'itype'} = 'appaccount';
		push @{$ee{'fieldlist'}}, [ 'program path', $url ];
	    }
	    else {							# web accounts
		$ee{'itype'} = 'webaccount';
		push @{$ee{'fieldlist'}}, [ 'url', $url ];
	    }

	    if (my $loginID = $loginnode->getAttribute('SourceLoginID')) {
		$ee{'cmeta'}{'title'} .= sprintf " (%s)", $logins{$loginID}[2] // $logins{$loginID}[0];
		push @{$ee{'fieldlist'}}, [ 'username' => $logins{$loginID}[0] ];
		push @{$ee{'fieldlist'}}, [ 'password' => $logins{$loginID}[1] ];
		debug "\tprocessed login($ee{'cmeta'}{'title'}): ", $logins{$loginID}[0];
	    }
	    push @entries, \%ee;
	}
    }

    # Identities, Credit Cards and Bank Accounts
    #
    $nodes = $xp->findnodes('//Identities/Identity');
    foreach my $node (@$nodes) {

	# -------------------- Identity -------------------- 
	my %e;
	$e{'itype'} = 'identity';
	set_common_attributes($node, \%e, \%groups);

	my $identity_title = $e{'cmeta'}{'title'};		# save the identity group's title to add to sub-entries

	# RoleValues (essentially a 1Password 'identity')
	my $rvnodes = $xp->findnodes('./RoleValues/RoleValue', $node);
	foreach my $rv (@$rvnodes) {
	    my ($key, $value) = ($rvid_to_key{$rv->getAttribute('RoleType')}, $rv->getAttribute('Name'));

	    # some fixups
	    if ($key eq 'payment method') {
		$value = paymentmethod($value)
	    }
	    elsif ($key eq 'person title') {
		$e{'cmeta'}{'title'} = sprintf "%s (%s)", $value, $identity_title;
		next;
	    }

	    push @{$e{'fieldlist'}}, [ $key => $value ];
	}

	# Fixup: combines address
	my (%addr, @newfieldlist);
	for (@{$e{'fieldlist'}}) {
	    if ($_->[0] =~ /^city|zip$/) {
		$addr{lc $_->[0]} = $_->[1];
	    }
	    elsif ($_->[0] =~ /^addr_line_[12]$/) {
		$addr{'street'} = myjoin ', ', $addr{'street'}, $_->[1];
	    }
	    else {
		push @newfieldlist, $_;
	    }
	}
	push @newfieldlist, [ 'address' => \%addr ]		if keys %addr;
	@{$e{'fieldlist'}} = @newfieldlist;
	push @entries, \%e;

	# -------------------- Credit Cards stored within the identity -------------------- 
	my $ccnodes = $xp->findnodes('./CreditCards/CreditCard', $node);
	foreach my $ccnode (@$ccnodes) {
	    my %ec;
	    $ec{'itype'} = 'creditcard';
	    $ec{'cmeta'}{'title'} = sprintf "%s (%s)", $ccnode->getAttribute('Name'), $identity_title;
	    my $rvnodes = $xp->findnodes('./RoleValues/RoleValue', $ccnode);
	    foreach my $rv (@$rvnodes) {
		my ($key, $value) = ($rvid_to_key{$rv->getAttribute('RoleType')}, $rv->getAttribute('Name'));

		push @{$ec{'fieldlist'}}, [ $key => $value ];
	    }
	    push @entries, \%ec;
	}

	# -------------------- Bank Accounts stored within the identity -------------------- 
	my $banodes = $xp->findnodes('./BankAccounts/BankAccount', $node);
	foreach my $banode (@$banodes) {
	    my %eb;
	    $eb{'itype'} = 'bankacct';
	    $eb{'cmeta'}{'title'} = sprintf "%s (%s)", $banode->getAttribute('Name'), $identity_title;
	    my $rvnodes = $xp->findnodes('./RoleValues/RoleValue', $banode);
	    foreach my $rv (@$rvnodes) {
		my ($key, $value) = ($rvid_to_key{$rv->getAttribute('RoleType')}, $rv->getAttribute('Name'));

		push @{$eb{'fieldlist'}}, [ $key => $value ];
	    }
	    push @entries, \%eb;
	}
    }

    return @entries;
}

sub set_common_attributes {
    my ($node, $e, $groups) = @_;

    $e->{'cmeta'}{'title'} = $node->getAttribute('Name');

    my $mdate = $node->getAttribute('ModifiedDate');
    my $cdate = $node->getAttribute('CreatedDate');
    if (defined $mdate and $mdate ne '') {
	if ($main::opts{'notimestamps'}) {
	    push @{$e->{'fieldlist'}}, [ 'Date Modified', $mdate ];
	}
	else {
	    $e->{'cmeta'}{'modified'} = date2epoch($mdate, 0);
	}
    }
    if (defined $cdate and $cdate ne '') {
	if ($main::opts{'notimestamps'}) {
	    push @{$e->{'fieldlist'}}, [ 'Date Created', $cdate ];
	}
	else {
	    $e->{'cmeta'}{'created'} = date2epoch($cdate, 0);
	}
    }

    if (my $groupid = $node->getAttribute('ParentID')) {
	if ($groupid > 0) {
	    $e->{'cmeta'}{'tags'}   =   $groups->{$groupid};
	    $e->{'cmeta'}{'folder'} = [ $groups->{$groupid} ];
	    #debug 'Group: ', $e->{'cmeta'}{'tags'};
	}
    }

}

sub do_export {
    add_custom_fields(\%card_field_specs);
    create_pif_file(@_);
}

# Date converters
#     yyyyMMDD									identity birthdate
#     yyyy-MM-DDThh:mm:ss.mss[-]zh:zm		2016-01-25T02:54:41.064-08:00	record timestamps
sub parse_date_string {
    local $_ = $_[0];

    if (/^\d{8}$/) {
	if (my $t = Time::Piece->strptime($_, "%Y%m%d")) {	# yyyyMMDD
	    return $t;
	}
    }
    else {
	s/\.\d{3}[+-]?\d{2}:\d{2}$//;					# eliminate the milliseconds and zone info
	if (my $t = Time::Piece->strptime($_, "%Y-%m-%dT%H:%M:%S")) {	# yyyy-MM-DDThh:mm:ss
	    return $t;
	}
    }

    return undef;
}

sub date2epoch {
    my $t = parse_date_string $_[0];
    return undef if not defined $t;

    # for birthdates
    if ($_[1] eq 'local') {
	return defined $t->year ? 0 + timelocal($t->sec, $t->minute, $t->hour, $t->mday, $t->mon - 1, $t->year): $_[0];
    }

    # for record timestamps
    return defined $t->year ? 0 + timegm($t->sec, $t->minute, $t->hour, $t->mday, $t->mon - 1, $t->year): $_[0];
}

sub date2monthYear {
    $_[0] =~ /(\d{2})(\d{4})/;
    return defined $2 ? $2 . $1	: $_[0];
}

# cheap RTF to Text converter.
#
sub rtf_decode {
    return $_[0] unless $_[0] =~ /^{\\rtf1\\/;			# some notes are not in RTF format

    my $tokenizer = RTF::Tokenizer->new('note_escapes' => 1);
    $tokenizer->read_string($_[0]);
    my @tokens = $tokenizer->get_all_tokens();

    my $ret;
    my $paragraph;
    while (@tokens) {
	my $token = shift @tokens;

	if ($paragraph) {
	    if ($token->[0] eq 'control' and $token->[1] eq 'par') {
		$ret .= "\n";
		next;
	    }
	    elsif ($token->[0] eq 'text') {
		$ret .= $token->[1];
	    }
	    elsif ($token->[0] eq 'escape') {
		if ($token->[1] eq "'") {
		    my $char = encode('UTF-8', pack('H*', $token->[2]));
		    Encode::_utf8_on($char);
		    $ret .= $char;
		}
	    }
	    elsif ($token->[0] eq 'control') {
		if ($token->[1] eq "u") {
		    $ret .= pack('U', $token->[2]);
		    # a Unicode number will have a terminating '?', which may be combined with subsequent text
		    if ($tokens[0][0] eq 'text' and $tokens[0][1] =~ /^[?](.*)$/) {
			$ret .= $1;
			shift @tokens;
		    }
		}
	    }
	}

	if ($token->[0] eq 'control' and $token->[1] eq 'pard') {
	    $paragraph++;
	    next;
	}
    }
    return $ret;
}

sub maritalstatus {
    my %status = (
	0 => 'unspecified',
	1 => 'single',
	2 => 'married',
	3 => 'divorced',
	4 => 'window/widower',
    );
    return $status{$_[0]};
}

sub paymentmethod {
    my %method = (
	0 => 'unspecified',
	1 => 'cash',
	2 => 'wire transfer',
	3 => 'check',
	4 => 'credit card',
	4 => 'paypal',
    );
    return $method{$_[0]};
}

1;
