# Passwords Plus CSV export converter
#
# Copyright 2016 Mike Cappella (mike@cappella.us)

package Converters::Passwordsplus 1.01;

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
    bankacct =>		        { textname => 'Bank Account', fields => [
	[ 'url',		0, qr/^URL$/,			{ type_out => 'login' } ],
	[ 'usernmae',		0, qr/^Username$/, 		{ type_out => 'login' } ],
	[ 'password',		0, qr/^Password$/, 		{ type_out => 'login' } ],
	[ 'accountNo',		1, qr/^Checking Account$/, ],
	[ 'routingNo',		1, qr/^Routing Number$/, ],
	[ '_savingsAccountNo',	1, qr/^Savings Account$/, 	{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_string, 'savings account number' ] } ],
	[ 'telephonePin',	0, qr/^PIN$/, ],
    ]},
    clothes =>			{ textname => 'Clothing Size', type_out => 'note', fields => [
	[ 'shirt_size',		1, qr/^Shirt$/ ],
	[ 'pant_size',		1, qr/^Pants$/ ],
	[ 'shoe_size',		1, qr/^Shoe$/ ],
	[ 'dress_size',		1, qr/^Dress$/ ],
	[ 'hat_size',		1, qr/^Hat$/ ],
	[ 'suit_size',		1, qr/^Suit$/ ],
    ]},
    combination =>		{ textname => 'Combination', type_out => 'note', fields => [
	[ 'combination',	1, qr/^Combination$/,		{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_concealed, 'combination', 'generate'=>'off' ] }  ],
    ]},
    creditcard =>		{ textname => 'Credit Card', fields => [
	[ 'ccnum',		1, qr/^Card Number$/, ],
	[ '_expiry',		1, qr/^Expiration Date$/, ],
	[ 'cardholder',		1, qr/^Name on Card$/, ],
	[ 'cvv',		1, qr/^CVV\/Security Code$/, ],
	[ 'pin',		0, qr/^PIN$/, ],
	[ 'phoneLocal',		0, qr/^Phone Number$/, ],
	[ 'url',		0, qr/^URL$/,			{ type_out => 'login' } ],
	[ 'usernmae',		0, qr/^Username$/, 		{ type_out => 'login' } ],
	[ 'password',		0, qr/^Password$/, 		{ type_out => 'login' } ],
    ]},
    email =>		        { textname => 'E-Mail Account', fields => [
	[ 'smtp_username',	1, qr/^E-Mail Address$/, ],
	[ 'smtp_password',	0, qr/^Password$/, ],
	[ 'pop_server',		1, qr/^POP3 Server$/, ],
	[ 'smtp_server',	1, qr/^SMTP Server$/, ],
	[ '_exchange_server',	1, qr/^Exchange Server$/, ],
    ]},
    emergencyinfo =>		{ textname => 'Emergency Info', type_out => 'note', fields => [
	[ 'ei_policeph',	0, qr/^Police Phone$/, ],
	[ 'ei_fireph',		0, qr/^Fire Phone$/, ],
	[ 'ei_ambulanceph',	0, qr/^Ambulance Phone$/, ],
	[ 'ei_posionctlph',	0, qr/^Poison Control$/, ],
    ]},
    frequentflyer =>		{ textname => 'Frequent Flyer', type_out => 'membership', fields => [
	[ 'membership_no',	1, qr/^Account Number$/, ],
	[ '_date',		1, qr/^Date$/, ],
	[ '_points',		1, qr/^Points$/, ],
	[ '_phonenum',		0, qr/^Phone Number$/, ],
	[ 'url',		0, qr/^URL$/,			{ type_out => 'login' } ],
	[ 'usernmae',		0, qr/^Username$/, 		{ type_out => 'login' } ],
	[ 'password',		0, qr/^Password$/, 		{ type_out => 'login' } ],
    ]},
    healthinsurance =>		{ textname => 'Health Insurance Policy', type_out => 'membership', fields => [
	[ 'org_name',		1, qr/^Company Name$/, ],
	[ '_hi_polid',		0, qr/^Policy Number$/,		{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_string, 'policy #' ] } ],
	[ '_hi_grpid',		1, qr/^Group ID$/,		{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_string, 'group #' ] } ],
	[ '_hi_address',	0, qr/^Address$/,		{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_string, 'address' ] } ],
	[ '_hi_phone',		0, qr/^Phone Number$/,		{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_string, 'phone' ] } ],
	[ '_hi_agent',		1, qr/^Agent$/,			{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_string, 'agent' ] } ],
	[ '_hi_agentph',	1, qr/^Agent Phone$/,		{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_string, 'agent phone' ] } ],
	[ '_hi_claimph',	1, qr/^Claim Phone No\.$/,	{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_string, 'claim phone' ] } ],
    ]},
    homesecurity =>		{ textname => 'Home Security', type_out => 'note', fields => [
	[ '_hs_pin',		0, qr/^PIN$/, 			{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_concealed, 'pin', 'generate'=>'off' ] } ],
	[ '_hs_challengepw',	1, qr/^Challenge Password$/, 	{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_concealed, 'challenge password', 'generate'=>'off' ] } ],
	[ '_hs_phonenum',	0, qr/^Phone Number$/, ],
	[ '_hs_securityco',	1, qr/^Security Company$/, ],
	[ '_hs_policeph',	1, qr/^Police Number$/, ],
	[ '_hs_fireph',		1, qr/^Fire Number$/, ],
    ]},
    identification =>		{ textname => 'Identification', fields => [
	[ 'number',		1, qr/^Social Security Number$/, 	{ type_out => 'socialsecurity' } ],
	[ 'number',		1, qr/^Driver's License Number$/,	{ type_out => 'driverslicense' } ],
	[ 'number',		1, qr/^Passport Number$/,		{ type_out => 'passport' }],
	[ '_expiry_date',	1, qr/^Passport Expiration Date$/,	{ type_out => 'passport' } ],
    ]},
    membership =>		{ textname => 'Memberships', fields => [
	[ 'membership_no',	1, qr/^Membership Number$/, ],
	[ 'pin',		0, qr/^PIN$/, ],
	[ '_member_since',	1, qr/^Start Date$/, ],
	[ '_expiry_date',	1, qr/^Exp\. Date$/, ],
	[ 'phone',		0, qr/^Phone$/, ],
    ]},
    prescription =>		{ textname => 'Prescriptions', type_out => 'note', fields => [
	[ '_rx_number',		1, qr/^Prescripion Number$/, ],
	[ '_rx_brand',		1, qr/^Brand$/, ],
	[ '_rx_doctor',		1, qr/^Doctor$/, ],
	[ '_rx_pharmacy',	1, qr/^Pharmacy$/, ],
	[ '_rx_phone',		0, qr/^Phone Number$/, ],
	[ '_rx_phonepharm',	1, qr/^Pharmacy Phone$/, ],
	[ '_rx_purchdate',	1, qr/^Purchase Date$/, ],
    ]},
    productinfo =>		{ textname => 'Product Information', type_out => 'note', fields => [
	[ '_sn_description',	1, qr/^Description$/, ],
	[ '_sn_serialnum',	1, qr/^Serial Number$/, ],
	[ '_sn_company',	1, qr/^Company$/, ],
	[ '_sn_phone',		0, qr/^Phone Number$/, ],
    ]},
    vehicle =>		        { textname => 'Vehicle', type_out => 'note', fields => [
	[ '_vh_make',		1, qr/^Make$/, ],
	[ '_vh_model',		1, qr/^Model$/, ],
	[ '_vh_make',		1, qr/^Year$/, ],
	[ '_vh_license',	1, qr/^License Plate$/, ],
	[ '_vh_vin',		1, qr/^VIN$/, ],
	[ '_vh_insuranceco',	1, qr/^Insurance Company$/, ],
	[ '_vh_insurancepol',	0, qr/^Policy Number$/, ],
	[ '_vh_agentph',	1, qr/^Agent Phone Number$/, ],
    ]},
    voicemail =>		{ textname => 'Voice Mail', type_out => 'note', fields => [
	[ '_vm_accessno',	1, qr/^Access No\.$/,	{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_string, 'access #' ] } ],
	[ '_vm_pin',		1, qr/^PIN$/, 		{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_concealed, 'pin', 'generate'=>'off' ] } ],
    ]},
    website =>			{ textname => 'Website', type_out => 'login', fields => [
	[ 'username',		0, 'Username', ],
	[ 'password',		0, 'Password', ],
	[ 'url',		0, 'URL', ],
	[ '_web_security_q',	1, 'Security Question', { custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_string, 'security question' ] } ],
	[ '_web_security_a',	1, 'Security Answer',	{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_concealed, 'security answer', 'generate'=>'off' ] } ],
    ]},
);

$DB::single = 1;					# triggers breakpoint when debugging

my $custom_field_num = 1;

sub do_init {
    return {
	'specs'		=> \%card_field_specs,
	'imptypes'  	=> undef,
	'opts'		=> [ ],
    }
}

sub do_import {
    my ($file, $imptypes) = @_;

    open my $io, "<:encoding(UTF-8)", $file
	or bail "Unable to open CSV file: $file\n$!";

    # remove BOM
    my $bom;
    (my $nb = read($io, $bom, 1) == 1 and $bom eq "\x{FEFF}") or
	bail "Failed to read BOM from CSV file: $file\n$!";

    # the first two rows of the export file use 0xa as the line separator, whereas the CSV data uses 0xd 0xa
    my $csv = Text::CSV->new ({
	    binary => 1,
	    allow_loose_quotes => 0,
	    sep_char => ',',
	    eol => "\x{a}",
	    quote_char => '"',
    });

    my $row = $csv->getline ($io);		# get the export version info
    # Verify export version
    join(' ', @$row[0..2]) eq 'Dataviz Passwords Plus Export  Version 1' or
	bail 'Unepexpected Passwords Plus export: ', join(' ', $row);

    my $field_keys = $csv->getline ($io);		# get the field semantics

    # accomodate the change in line endings
    $csv = Text::CSV->new ({
	    binary => 1,
	    allow_loose_quotes => 0,
	    sep_char => ',',
	    eol => "\x{d}\x{a}",
	    quote_char => '"',
    });

    my %Cards;
    my ($n, $rownum) = (1, 1);

    my %categories;
    while (my $row = $csv->getline ($io)) {
	if ($row->[0] eq '' and @$row == 1) {
	    warn "Skipping unexpected empty row: $n";
	    next;
	}
	debug 'ROW: ', $rownum++, ' -----------';

	my (@fieldlist, %cmeta, @notes, $category);

	# a template definition
	if (shift @$row == 1) {
	    $category = shift @$row;
	    shift @$row;			# eliminate the Category cell
	    pop @$row;				# eliminate the Notes cell

	    debug "\treading category defintions: ", $category;
	    while (@$row) {
		debug "\t    field: ", $row->[0];
		push @{$categories{$category}}, shift @$row;
		shift @$row; shift @$row;		# shfit out the Value and Hidden cells
	    }
	}

	# a standard (non-template) entry data
	else {
	    $cmeta{'title'} = shift @$row;
	    $cmeta{'notes'} = pop @$row;	# notes are always the last entry
	    if (($category = shift @$row) ne 'Unfiled') {
		$cmeta{'tags'}   =   $category;
		$cmeta{'folder'} = [ $category ];
	    }
	    debug "\ttitle: ", $cmeta{'title'};
	    while (@$row) {
		my ($label, $value, undef) = (shift @$row, shift @$row, shift @$row);
		debug "\tfield: $label => $value";
		push @fieldlist, [ $label => $value ]
	    }
	}

	my $itype = find_card_type(\@fieldlist);

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
    my $f = shift;

    for my $type (sort by_test_order keys %card_field_specs) {
	for my $cfs (@{$card_field_specs{$type}{'fields'}}) {
	    for (@$f) {
		if ($cfs->[CFS_TYPEHINT] and $_->[0] =~ $cfs->[CFS_MATCHSTR]) {
		    debug "type detected as '$type' (key='$_->[0]')";
		    return $type;
		}
	    }
	}
    }

    if (grep { $_->[0] =~ /^URL|Username|Password$/ } @$f ) {
	debug "type detected as 'login'";
	return 'login';
    }

    debug "\t\ttype defaulting to 'note'";
    return 'note';
}

# sort logins as the last to check
sub by_test_order {
    return  1 if $a eq 'login';
    return -1 if $b eq 'login';
    $a cmp $b;
}

1;
