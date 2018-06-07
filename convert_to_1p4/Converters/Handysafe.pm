# Handy Safe XML export converter
#
# Copyright 2014 Mike Cappella (mike@cappella.us)

package Converters::Handysafe 1.02;

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
use Date::Calc qw(check_date Date_to_Days Moving_Window);
use File::Spec;

my %card_field_specs = (
    bankacct =>			{ textname => undef, fields => [
	[ 'bankName',		0, 'Bank', ],
	[ 'accountNo',          1, 'Account', ],
	[ 'accountType',	0, 'Type', ],
	[ '_branchNumber',	1, 'Branch number',	{ custfield => [ $Utils::PIF::sn_branchInfo, $Utils::PIF::k_string, 'branch number' ] } ],
	[ 'swift',		1, 'SWIFT', ],
	[ 'branchPhone',	0, 'Phone', ],
	[ '_other',		0, 'Other', ],
    ]},
    carinfo =>		        { textname => undef, type_out => 'note', fields => [
	[ '_model',		1, 'Model', ],
	[ '_made',		1, 'Made', ],
	[ '_year',		1, 'Year', ],
	[ '_license',		1, 'License', ],
	[ '_expires',		0, 'Expires', ],
	[ '_vin',		1, 'VIN', ],
	[ '_Insurance',		1, 'Insurance', ],
	[ '_policynum',		0, 'Policy number', ],
	[ '_phone',		0, 'Phone', ],
	[ '_insexpires',	0, 'Expires 2', ],	# see 'Fixup: disambiguation'
    ]},
    creditcard =>		{ textname => undef, fields => [
	[ 'bank',		0, 'Bank', ],
	[ '_firstname',		0, 'First name', ],	# see 'Fixup: combine names'
	[ '_lastname',		0, 'Last name', ],	# see 'Fixup: combine names'
        [ 'cardholder',         0, 'First + Last', ],	# see 'Fixup: combine names'; input never matches
	[ 'ccnum',		0, 'Card number', ],
	[ 'pin',		0, 'PIN', ],
	[ 'cvv',		1, 'CVC code', ],
	[ 'expiry',		0, 'Expires',		{ func => sub { return date2monthYear($_[0], 2) }, keep => 1 } ],
	[ 'phoneTollFree',	1, 'If lost, call', ],
	[ 'type',		0, 'Card Type' ],	# see 'Fixup: credit card type'; input never matches
    ]},
    driverslicense =>           { textname => undef, icon => 8, fields => [
        [ 'state',      	0, 'Location' ],
        [ 'number',             0, 'Number' ],
        [ '_drissued',          0, 'Issued' ],
        [ 'expiry_date',        0, 'Expires',	 	{ func => sub { return date2monthYear($_[0], 2) }, keep => 1 } ],
	[ '_other',		0, 'Other', ],
    ]},
    email =>			{ textname => undef, fields => [
        [ 'pop_username',      	0, 'Email' ],
        [ 'pop_username',      	0, 'Login' ],
        [ 'pop_password',      	0, 'Password' ],
        [ 'pop_server',      	1, 'POP3' ],
        [ 'smtp_server',      	1, 'SMTP' ],
	[ '_other',		0, 'Other', ],
    ]},
    idcard =>                   { textname => undef, type_out => 'membership', fields => [
        [ 'org_name',           2, 'Organization', ],
        [ '_firstname',         0, 'First name', ],	# see 'Fixup: combine names'
        [ '_lastname',          0, 'Last name', ],	# see 'Fixup: combine names'
        [ 'member_name',        0, 'First + Last', ],	# see 'Fixup: combine names'; input never matches
        [ 'membership_no',      2, 'ID', ],
    ]},
    lockcode =>                 { textname => undef, type_out => 'note', fields => [
        [ 'combolocation',      0, 'Location' ],
        [ '_code',          	1, 'Code',		{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_concealed, 'password', 'generate'=>'off' ] } ],
        [ 'comboother',         0, 'Other' ],
    ]},
    login =>                    { textname => undef, fields => [
        [ 'username',           0, 'Login', ],
        [ 'username',           0, 'Yahoo! ID', ],
        [ 'username',           0, 'Live ID', ],
        [ 'username',           0, 'Email', ],
        [ 'username',           0, 'UID', ],
        [ 'password',           0, 'Password', ],
        [ 'url',                1, 'URL', ],
        [ '_other',             0, 'Other', ],
    ]},
    membership =>               { textname => undef, fields => [
        [ 'org_name',           2, 'ID', ],
        [ 'phone',              0, 'Phone' ],
        [ 'expiry_date',        2, 'Expires',		{ func => sub { return date2monthYear($_[0], 2) }, keep => 1 } ],
        [ '_other',             0, 'Other' ],
    ]},
    passport =>                 { textname => undef, fields => [
        [ 'type',               0, 'Type', ],
        [ 'number',             0, 'Number', ],
        [ '_firstname',         0, 'First name', ],	# see 'Fixup: combine names'
        [ '_lastname',          0, 'Last name', ],	# see 'Fixup: combine names'
        [ 'fullname',           0, 'First + Last', ],	# see 'Fixup: combine names'; input never matche
        [ 'sex',                0, 'Sex' ],
        [ 'birthdate',          0, 'Birth',		{ func => sub { return date2epoch($_[0], 2) } } ],
        [ 'birthplace',         0, 'Place', ],
        [ 'nationality',        1, 'Nation', ],
        [ 'issue_date',         0, 'Issued', 		{ func => sub { return date2epoch($_[0], 2) } } ],
        [ 'expiry_date',        0, 'Expires', 		{ func => sub { return date2epoch($_[0], 2) } } ],
        [ 'type',               1, 'Authority', ],
    ]},
    password =>                 { textname => undef, type_out => 'server', fields => [
        [ 'username',           0, 'Login', ],
        [ 'password',           0, 'Password', ],
        [ '_access',            1, 'Access', ],
        [ '_other',             0, 'Other', ],
    ]},
    wireless =>                 { textname => undef, fields => [
        [ '_access',            0, 'Access', ],
        [ 'wireless_password',  0, 'Password', ],
        [ 'network_name',       1, 'SSID', ],
        [ '_ip',                1, 'IP', ],
        [ '_dns',               0, 'DNS', ],
        [ '_other',             0, 'Other', ],
    ]},
);

$DB::single = 1;					# triggers breakpoint when debugging

my @today = Date::Calc::Today();			# for date comparisons
my %localized;

# Icon number to type mapping, to help find_card_type determine card type.
# See also Utils::PIF::kind_conversions for credit card name patterns.
my %icons = (
    27=>'amex',
    28=>'diners club',
    29=>'discover',
    34=>'maestro',
    32=>'mastercard',
    33=>'visa'
);

sub do_init {
    # grab any additional icon numbers from card_field_specs
    for (keys %card_field_specs) {
	$icons{$card_field_specs{$_}{'icon'}} = $_		if exists $card_field_specs{$_}{'icon'};
    }

    return {
	'specs'		=> \%card_field_specs,
	'imptypes'  	=> undef,
	'opts'		=> [ [ q{-l or --lang <lang>        # language in use: nl-nl },
			       'lang|l=s'	=> sub { init_localization_table($_[1]) or Usage(1, "Unknown language type: '$_[1]'") } ],
			   ],
    };
}

sub do_import {
    my ($file, $imptypes) = @_;
    my %Cards;

    $_ = slurp_file($file);

    # Localize the %card_field_specs table
    if (scalar %localized) {
	for my $key (keys %card_field_specs) {
	    for my $cfs (@{$card_field_specs{$key}{'fields'}}) {
		$cfs->[CFS_OPTS]{'i18n'} = ll($cfs->[CFS_MATCHSTR]);
	    }
	}
    }

    my $n = 1;

    my $xp = XML::XPath->new(xml => $_);
    my $cardnodes = $xp->find('//Card[@name]');
    foreach my $cardnode (@$cardnodes) {
	my @groups;

	for (my $node = $cardnode->getParentNode(); my $parent = $node->getParentNode(); $node = $parent) {
	    my $v = $xp->findvalue('@name', $node)->value();
	    unshift @groups, $v   unless $v eq '';
	}

	my (%c, @fieldlist, %cmeta);
	$cmeta{'title'} = $xp->findvalue('@name', $cardnode)->value;
	$cmeta{'tags'} = join '::', @groups;
	$cmeta{'folder'} = [ @groups];
	debug "\tCard: ", $cmeta{'title'};

	my $iconnum = $xp->findvalue('@icon', $cardnode)->value;
	debug "\t\ticon # : ", $iconnum;

	if (my $fieldnodes = $xp->findnodes('Field', $cardnode)) {
	    my $fieldindex = 1;;
	    foreach my $fieldnode (@$fieldnodes) {
		# handle blank field labels;  type Note has none by default, but labels can be blanked by the user
		my $f = $fieldnode->getAttribute("name") || 'Field_' . $fieldindex;
		my $v = $fieldnode->string_value;
		debug "\t\tfield: $f -> $v";
		push @fieldlist, [ $f => $v ];			# maintain the field order, in case destination is notes
		$fieldindex++;
	    }
	}

	my $notenodes = $xp->findnodes('Note', $cardnode);
	foreach my $notenode (@$notenodes) {
	    warn "Multiple notes entries(card '$cmeta{'title'}') - please report"	if exists $cmeta{'notes'};
	    if ($notenode->string_value ne '') {
		$cmeta{'notes'} = $notenode->string_value;
		debug "\t\tnote: ", $cmeta{'notes'};
	    }
	}

	my $itype = find_card_type(\@fieldlist, $iconnum);

	# skip all types not specifically included in a supplied import types list
	next if defined $imptypes and (! exists $imptypes->{$itype});

	# Fixup: disambiguation
	if ($itype eq 'carinfo' and (my @found = grep(ll('Expires') eq $_->[0], @fieldlist)) == 2) {
	    $found[1][0] = 'Expires 2';
	}

	# Fixup: combine names
	if ($itype =~ /^idcard|creditcard|passport$/) {
	    my @found = grep { $_->[0] eq ll('First name') or $_->[0] eq ll('Last name') } @fieldlist;
	    if (@found == 2) {
		push @fieldlist, [ 'First + Last' =>  myjoin(' ',  $found[0][1], $found[1][1]) ];
		debug "\t\tfield added: $fieldlist[-1][0] -> $fieldlist[-1][1]";
	    }
	}

	# Fixup: credit card type - set a credit card's 'type' key from the icon number if possible
	if ($itype eq 'creditcard') {
	    push @fieldlist, [ 'Card Type' => $icons{$iconnum} ]		if exists $icons{$iconnum};
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
    my $type;

    for $type (sort by_test_order keys %card_field_specs) {
	my ($nfound, @found);
	for my $cfs (@{$card_field_specs{$type}{'fields'}}) {
	    next unless $cfs->[CFS_TYPEHINT] and defined $cfs->[CFS_MATCHSTR];
	    for (@$fieldlist) {
		# type hint, requires matching the specified number of fields
		if ($_->[0] eq ($cfs->[CFS_OPTS]{'i18n'} // $cfs->[CFS_MATCHSTR])) {
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

    # Use icon numbers as a hint at the card type, since it is the only other
    # information available to suggest card type
    if (exists $icons{$iconnum}) {
	debug "\t\ttype detected as '$icons{$iconnum}' icon number = $iconnum";
	return $icons{$iconnum};
    }

    $type = grep($_->[0] eq ll('Password'), @$fieldlist) ? 'login' : 'note';

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

# Date converters
# Handy Safe dates:
#	OS X:	 m/d/yy:   9/1/15
#	Windows: m/d/yyyy: 9/1/2015
sub parse_date_string {
    local $_ = $_[0];
    my $when = $_[1] || 0;					# -1 = past only, 0 = assume this century, 1 = future only, 2 = 50-yr moving window

    if (/^(?<m>\d{1,2})\/(?<d>\d{1,2})\/(?<y>\d{4})$/) {	# Windows:  m/d/yyyy
	my $m = sprintf "%02d", $+{'m'};
	my $d = sprintf "%02d", $+{'d'};
	if (check_date($+{'y'}, $m, $d)) {
	    return ($+{'y'}, $m, $d);
	}
    }
    elsif (/^(?<m>\d{1,2})\/(?<d>\d{1,2})\/(?<y>\d{2})$/) {	# OS X:  m/d/yy
	my $days_today = Date_to_Days(@today);

	my $m = sprintf "%02d", $+{'m'};
	my $d = sprintf "%02d", $+{'d'};
	for my $century (qw/20 19/) {
	    my $y = sprintf "%d%02d", $century, $+{'y'};
	    $y = Moving_Window($y)	if $when == 2;
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
    return defined $y ? timelocal(0, 0, 3, $d, $m - 1, $y): $_[0];
}

# String localization.
# The %localized table will be initialized using the localized name as the key, and the english version
# as the value.
#
sub init_localization_table {
    my $lang = shift;
    main::Usage(1, "Unknown language type: '$lang'")
	unless defined $lang and $lang =~ /^(nl-nl)$/;

    if ($lang) {
	my $lstrings_path = join '.', File::Spec->catfile('Languages', 'handysafe'), $lang, 'txt';

	local $/ = "\n";
	#open my $lfh, "<:encoding(utf16)", $lstrings_path
	open my $lfh, "<", $lstrings_path
	    or bail "Unable to open localization strings file: $lstrings_path\n$!";
	while (<$lfh>) {
	    chomp;
	    my ($key, $val) = split /" = "/;
	    $key =~ s/^"//;
	    $val =~ s/"$//;
	    #say "Key: $key, Val: $val";
	    if ($val =~ s#^/(.+)/$#$1#) {
		$val = qr/$val/;
	    }
	    $localized{$key} = $val;
	}
    }
    1;
}

# Lookup the localized string and return its english string value.
sub ll {
    local $_ = shift;

    return $localized{$_} // $_;
}

1;
