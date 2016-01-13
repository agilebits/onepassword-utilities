# Ascendo DataVault CSV export converter
#
# Copyright 2015 Mike Cappella (mike@cappella.us)

package Converters::Datavault 1.01;

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

# Some stock templates are essentially duplicated and indistinguishable in the CSV export, and are mapped as follows:
#
# bank account, checking account     --> bankacct
# business contact, personal contact --> contact
# credit card, mastercard, visa      --> creditcard
# business, financial                --> business

my %card_field_specs = (
    bankacct =>			{ textname => '', fields => [
	[ 'bankName',		0, qr/^Bank$/, ],
	[ 'accountNo',		1, qr/^Account Number$/, ],
	[ 'telephonePin',	0, qr/^PIN$/, ],
	[ 'swift',		1, qr/^SWIFT Number$/, ],
	[ 'routingNo',		1, qr/^Routing Number$/, ],
	[ 'iban',		1, qr/^IBAN Number$/, ],
	[ '_svcphone',		0, qr/^Customer Service$/, ],
    ]},
    business =>			{ textname => '', type_out => 'note', fields => [
	[ '_type',		0, qr/^Type$/, ],
	[ '_code1',		1, qr/^Code1$/, ],
	[ '_code2',		1, qr/^Code2$/, ],
    ]},
    contact =>			{ textname => '', type_out => 'note', fields => [
	[ '_name',		0, qr/^Name$/, ],
	[ '_phone',		1, qr/^Telephone Number$/, ],
	[ '_email',		1, qr/^Email$/, ],
    ]},
    callingcard =>		{ textname => '', type_out => 'note', fields => [
	[ '_accessphone',	0, qr/^Access #$/, ],
	[ '_pin',		0, qr/^PIN$/, ],
	[ '_rechargepin',	1, qr/^Recharge PIN$/, ],
    ]},
    creditcard =>		{ textname => '', fields => [
	[ 'bank',		0, qr/^Bank$/, ],
	[ 'ccnum',		0, qr/^Number$/, ],
	[ '_expiry',		0, qr/^Expires|Expiration Date$/, ],
	[ 'pin',		0, qr/^PIN$/, ],
	[ 'cvv',		1, qr/^(?:Security|CVC) Code$/, ],
	[ 'cardholder',		1, qr/^Credit Card ID$/, ],
	[ 'phoneTollFree',	0, qr/^(?:Customer Service|If Lost)$/, ],
	[ '_type',		0, qr/^Type$/, ],
    ]},
    driverslicense =>		{ textname => '', fields => [
	[ 'state',		1, qr/^State$/, ],
	[ 'number',		0, qr/^Number$/, ],
	[ '_expiry_date',	0, qr/^Expires$/, ],
	[ 'class',		1, qr/^Class$/, ],
	[ '_dmvphone',		1, qr/^DMV Telephone #$/, ],
    ]},
    email =>			{ textname => '', fields => [
	[ '_email',		0, qr/^Address$/, ],
	[ 'pop_username',	0, qr/^Username$/, ],
	[ 'pop_password',	0, qr/^Password$/, ],
	[ 'pop_server',		1, qr/^Incoming mail \(POP3\)$/, ],
	[ 'smtp_server',	1, qr/^Outgoing mail \(SMTP\)$/, ],
    ]},
    event =>			{ textname => '', type_out => 'note', fields => [
	[ '_eventtype',		0, qr/^Type$/, ],
	[ '_eventname',		0, qr/^Name$/, ],
	[ '_eventdate',		1, qr/^Date$/, ],
    ]},
    frequentflyer =>		{ textname => '', type_out => 'rewards', fields => [
	[ 'company_name',	1, qr/^Airline$/, ],
	[ 'membership_no',	1, qr/^Membership #$/, ],
	[ 'url',		0, qr/^Web Site$/,		{ type_out => 'login' } ],
	[ 'username',		0, qr/^Username$/,		{ type_out => 'login' } ],
	[ 'password',		0, qr/^Password$/,		{ type_out => 'login' } ],
	[ 'customer_service_phone', 0, qr/^Customer Service$/, ],
    ]},
    healthinfo =>		{ textname => '', type_out => 'note', fields => [
	[ '_bloodtype',		1, qr/^Blood Type$/, ],
	[ '_allergies',		1, qr/^Allergies$/, ],
	[ '_vaccinations',	1, qr/^Vaccinations$/, ],
	[ '_height',		1, qr/^Height$/, ],
	[ '_weight',		1, qr/^Weight$/, ],
	[ '_bloodpressure',	1, qr/^Blood Pressure$/, ],
	[ '_physician',		1, qr/^Physician$/, ],
	[ '_telephone',		0, qr/^Telephone$/, ],
    ]},
    homeinfo =>			{ textname => '', type_out => 'note', fields => [
	[ '_alarmcompany',	1, qr/^Alarm Company$/, ],
	[ '_alarmphone',	1, qr/^Alarm Telephone$/, ],
	[ '_alarmpass',		1, qr/^Alarm Password$/, ],
	[ '_insurance',		1, qr/^Home Insurance$/, ],
	[ '_insurancephone',	1, qr/^Insurance Telephone$/, ],
	[ '_insurancepolicy',	1, qr/^Insurance Policy #$/, ],
    ]},
    insurance =>		{ textname => '', type_out => 'membership', fields => [
	[ 'org_name',		0, qr/^Company$/, ],
	[ '_subscriber_num',	1, qr/^Subscriber #$/,	{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_string, 'subscriber #' ] } ],
	[ '_group_num',		1, qr/^Group #$/,	{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_string, 'group #' ] } ],
	[ 'membership_no',	0, qr/^Member #$/, ],
	[ '_plan',		1, qr/^Plan$/,		{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_string, 'plan' ] } ],
	[ 'phone',		0, qr/^Telephone$/, ],
	[ '_physician',		1, qr/^Primary Physician$/, ],
	[ '_physicianphone',	0, qr/^Physicans Telephone$/, ],	# special magic - label modified below to make it unique
    ]},
    login =>			{ textname => '', fields => [
	[ 'url',		0, qr/^Address$/, ],
	[ 'username',		0, qr/^Username$/, ],
	[ 'password',		0, qr/^Password$/, ],
	[ 'email',		0, qr/^email$/, ],
    ]},
    membership =>		{ textname => '', fields => [
	[ 'org_name',		0, qr/^Type$/, ],
	[ 'membership_no',	1, qr/^Member #$/, ],		# field also present in insurance, but find_card_type() tests 'membership' hits late
	[ '_expiry_date',	0, qr/^Expiration Date$/, ],
	[ 'phone',		0, qr/^Phone$/, ],
    ]},
    note =>			{ textname => '', fields => [
	[ '_subject',		1, qr/^Subject$/, ],
    ]},
    prescription =>		{ textname => '', type_out => 'note', fields => [
	[ '_doctor',		1, qr/^Doctor$/, ],
	[ '_rxname',		0, qr/^Name$/, ],
	[ '_rxnum',		1, qr/^Rx #$/, ],
	[ '_rxpharmacy',	1, qr/^Pharmacy$/, ],
	[ '_rxphone',		0, qr/^Telephone$/, ],
    ]},
    registrationkey =>		{ textname => '', type_out => 'software', fields => [
	[ '_product',		1, qr/^Product$/, { to_title => 'value' } ],
	[ '_serialnum',		1, qr/^Serial Number$/, ],
	[ 'reg_code',		1, qr/^Key$/, ],
	[ 'reg_name',		0, qr/^Name$/, ],
	[ 'publisher_name',	0, qr/^Company$/, ],
    ]},
    travelclub =>		{ textname => '', type_out => 'rewards', fields => [
	[ '_type',		0, qr/^Type$/, ],
	[ 'member_name',	0, qr/^Name$/, ],
	[ 'membership_no',	1, qr/^Membership Number$/, ],
	[ 'pin',		0, qr/^Code$/, ],
	[ '_points',		1, qr/^Points$/, ],
	[ 'customer_service_phone',0, qr/^Telephone$/, ],
    ]},
    voicemail =>		{ textname => '', type_out => 'note', fields => [
	# fields below present in callingcard, but find_card_type() test 'voicemail' hits late
	[ '_accessnum',		1, qr/^Access #$/, ],
	[ '_pin',		0, qr/^PIN$/, ],
    ]},
    vehicleinfo =>		{ textname => '', type_out => 'note', fields => [
	[ '_accessnum',		0, qr/^Type$/, ],
	[ '_accessnum',		1, qr/^License Plate #$/, ],
	[ '_accessnum',		1, qr/^VIB$/, ],
	[ '_accessnum',		1, qr/^Insurance Type$/, ],
	[ '_accessnum',		1, qr/^Registration #$/, ],
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
	    sep_char => ",",
	    eol => 		  $^O eq 'MSWin32' ? "\x{0d}\x{0a}" : "\n",
	    # Quoting is correct on DataVault for Windows but not for OS X
	    allow_loose_quotes => $^O eq 'MSWin32' ? 0 : 1,
	    escape_char => 	  $^O eq 'MSWin32' ? '"' : undef,
    });

    my $data = slurp_file($file, ':raw');

    # In the DataVault export, record line endings are 0a (OS X) and 0d 0a (Windows).  And
    # the intra-field line endings (e.g. for notes) will cause csv->getline() to misdetect
    # record boundaries.  So convert intra-field line endings to 0d and patch them later.
    #
    if ($^O eq 'darwin') {
	$data =~ s/\x{0d}\x{0a}/\x{0d}/gs;	# 0d 0a		--> 0d
    }
    else {
	$data =~ s/\x{0d}{2}\x{0a}/\x{0d}/gs;	# 0d 0d 0a	--> 0d
	utf8::encode($data);			# convert latin1 to utf8
    }

    open my $io,  "<:encoding(utf8)", \$data or
	bail "Unable to reopen IO handle as a variable";

    my %Cards;
    my ($n, $rownum) = (1, 1);

    while (my $row = $csv->getline($io)) {
	debug 'ROW: ', $rownum++;

	my %cmeta;
	$cmeta{'title'} = shift @$row;
	$cmeta{'notes'} = pop   @$row;

	# Incorrect quoting alert on DataVault for OS X:
	#   "mylogin","Address","example.com","Username","joe@example.com","Password",",""secret""stuff""","", ... "","Watch for quoted password"
	# The password is: ,"secret"stuff"
	#   correct csv:    ",""secret""stuff"""
	#   correct win:    ",""secret""stuff"""
	#   incorrect mac:  ","secret"stuff""

	if (@$row ne 20) {
	    say "** Skipped entry (uncorrectable CSV quoting problem, ncols=", scalar @$row, ").  Add this record to 1Password manually: '$cmeta{'title'}'";
	    next;
	}

	# Everything that remains in the row is the the field data
	my (@fieldlist, @labels);
	if ($row->[10] eq 'Telephone' and $row->[14] eq 'Telephone') {
	    $row->[14] =~ s/Telephone/Physicans Telephone/
	}
	for (my $i = 0; $i < 10; $i++) {
	    my $label = shift @$row;
	    my $value = shift @$row;
	    next if $label eq '';
	    debug "\tfield: $label => $value";
	    push @fieldlist, [ $label => $value ];
	    push @labels, $label;
	}

	my $itype = find_card_type(\@labels);

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
    close $io;

    summarize_import('item', $n - 1);
    return \%Cards;
}

sub do_export {
    add_custom_fields(\%card_field_specs);
    create_pif_file(@_);
}

sub find_card_type {
    my $labels = shift;

    for my $type (sort by_test_order keys %card_field_specs) {
	for my $cfs (@{$card_field_specs{$type}{'fields'}}) {
	    for (@$labels) {
		if ($cfs->[CFS_TYPEHINT] and $_ =~ $cfs->[CFS_MATCHSTR]) {
		    debug "type detected as '$type' (key='$_')";
		    return $type;
		}
	    }
	}
    }

    my $type = grep($_ =~ /^Address|Username|Password$/, @$labels) ? 'login' : 'note';
    debug "\t\ttype defaulting to '$type'";
    return $type;
}

# sort logins as the last to check
sub by_test_order {
    return  1 if $a eq 'login';
    return -1 if $b eq 'login';
    return  1 if $a eq 'membership';
    return -1 if $b eq 'membership';
    return  1 if $a eq 'voicemail';
    return -1 if $b eq 'voicemail';
    $a cmp $b;
}

1;
