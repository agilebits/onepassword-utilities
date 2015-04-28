# Ascendo DataVault CSV export converter
#
# Copyright 2015 Mike Cappella (mike@cappella.us)

package Converters::Datavault 1.00;

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
	[ '_subscriber_num',	1, qr/^Subscriber #$/, ],
	[ '_group_num',		1, qr/^Group #$/, ],
	[ 'membership_no',	0, qr/^Member #$/, ],
	[ '_plan',		1, qr/^Plan$/, ],
	[ 'phone',		0, qr/^Telephone$/, ],
	[ '_physician',		1, qr/^Primary Physician$/, ],
	[ '_physicianphone',	0, qr/^Telephone$/, ],
    ]},
    login =>			{ textname => '', fields => [
	[ 'url',		0, qr/^Address$/, ],
	[ 'username',		0, qr/^Username$/, ],
	[ 'password',		0, qr/^Password$/, ],
	[ 'email',		0, qr/^email$/, ],
    ]},
    membership =>		{ textname => '', fields => [
	[ 'org_name',		0, qr/^Type$/, ],
	[ 'membership_no',	1, qr/^Member #$/, ],		# field also present in insurance, but find_card_type() test 'membership' hits late
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
	    allow_loose_quotes => 1,
	    escape_char => undef, 
	    sep_char => ",",
    });

    open my $io, $^O eq 'MSWin32' ? "<:encoding(latin1)" : "<:encoding(utf8)", $file
	or bail "Unable to open CSV file: $file\n$!";

    # The DataVault export, record line endings are 0a (OS X) and 0d 0a (Windows), so we need to convert
    # intrafield line endings to not conflict with record line endings, for csv->getline():
    #   OS X:      0d 0a  --> 0d
    #   Windows 0d 0d 0a  --> 0d
    {
	local $/ = undef;
	my $data = <$io>;
	if ($^O eq 'darwin') {
	    $data =~ s/\x{0d}\x{0a}/\x{0d}/gs;
	}
	else {
	    $data =~ s/\x{0d}\x{0a}/\x{0d}/gs;
	}
	close $io;
	open $io,  "<:encoding(utf8)", \$data or
	    bail "Unable to reopen IO handle as a variable";
    }

    my %Cards;
    my ($n, $rownum) = (1, 1);
    my ($npre_explode, $npost_explode);

    while (my $row = $csv->getline($io)) {
	debug 'ROW: ', $rownum++;

	my $card_title = shift @$row;
	my $card_notes = pop   @$row;

	if (@$row ne 20) {
	    say "Skipping uncorrectable DataVault CSV quoting problem: record '$card_title'.  You will need to manually add this record to 1Password.";
	    next;
	}
	# Everything that remains in the row is the the field data
	my (@fieldlist, @labels);
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

	my $normalized = normalize_card_data($itype, \@fieldlist, 
	    { title	=> $card_title,
	      notes	=> $card_notes });

	# Returns list of 1 or more card/type hashes; one input card may explode into multiple output cards
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
    add_new_field('membership',      '_subscriber_num',		$Utils::PIF::sn_main,	$Utils::PIF::k_string,    'subscriber #');
    add_new_field('membership',      '_group_num',		$Utils::PIF::sn_main,	$Utils::PIF::k_string,    'group #');
    add_new_field('membership',      '_plan',			$Utils::PIF::sn_main,	$Utils::PIF::k_string,    'plan');

    create_pif_file(@_);
}

# Places card data into a normalized internal form.
#
# Basic card data passed as $norm_cards hash ref:
#    title
#    notes
#    tags
#    folder
#    modified
# Per-field data hash {
#    inkey	=> imported field name
#    value	=> field value after callback processing
#    valueorig	=> original field value
#    outkey	=> exported field name
#    outtype	=> field's output type (may be different than card's output type)
#    keep	=> keep inkey:valueorig pair can be placed in notes
#    to_title	=> append title with a value from the narmalized card
# }
sub normalize_card_data {
    my ($type, $fieldlist, $norm_cards) = @_;

    for my $def (@{$card_field_specs{$type}{'fields'}}) {
	my $h = {};
	for (my $i = 0; $i < @$fieldlist; $i++) {
	    my ($inkey, $value) = @{$fieldlist->[$i]};
	    next if not defined $value or $value eq '';

	    if ($inkey =~ $def->[2]) {
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
		push @{$norm_cards->{'fields'}}, $h;
		splice @$fieldlist, $i, 1;	# delete matched so undetected are pushed to notes below
		last;
	    }
	}
    }

    # map remaining keys to notes
    $norm_cards->{'notes'} .= "\n"	if defined $norm_cards->{'notes'} and length $norm_cards->{'notes'} > 0 and @$fieldlist;
    for (@$fieldlist) {
	next if $_->[1] eq '';
	$norm_cards->{'notes'} .= "\n"	if defined $norm_cards->{'notes'} and length $norm_cards->{'notes'} > 0;
	$norm_cards->{'notes'} .= join ': ', @$_;
    }

    return $norm_cards;
}

sub find_card_type {
    my $labels = shift;

    for my $type (sort by_test_order keys %card_field_specs) {
	for my $def (@{$card_field_specs{$type}{'fields'}}) {
	    for (@$labels) {
		# type hint
		if ($def->[1] and $_ =~ $def->[2]) {
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
