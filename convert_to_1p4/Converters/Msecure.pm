# mSecure CSV export converter
#
# Copyright 2014 Mike Cappella (mike@cappella.us)

package Converters::Msecure 1.01;

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

#
# The first four columns of mSecure's CSV are assumed and are always:
#	Group, Type, Description, Notes
#
# The number of per-type entries must match the number of columns for the type in mSecure CSV output.
#
# note: the second field, the type hint indicator (e.g. $card_field_specs{$type}[$i][1]}),
# is not used, but remains for code-consisency with other converter modules.
#
my %card_field_specs = (
    bankacct =>			{ textname => 'Bank Accounts', fields => [
	[ 'accountNo',		0, 'Account Number', ],
	[ 'telephonePin',	0, 'PIN', ],
	[ 'owner',		0, 'Name', ],
	[ 'branchAddress',	0, 'Branch', ],
	[ 'branchPhone',	0, 'Phone No.', ],
    ]},
    birthdays => 		{ textname => 'Birthdays', type_out => 'note', fields => [
	[ 'date',		0, 'Date', ],
    ]},
    callingcards =>		{ textname => 'Calling Cards', type_out => 'login', fields => [
	[ 'access_no',		0, 'Access No.', ],
	[ 'password',		0, 'PIN', ],
    ]},
    clothes =>			{ textname => 'Clothes Size', type_out => 'note', fields => [
	[ 'shirt_size',		0, 'Shirt Size', ],
	[ 'pant_size',		0, 'Pant Size', ],
	[ 'shoe_size',		0, 'Shoe Size', ],
	[ 'dress_size',		0, 'Dress Size', ],
    ]},
    combinations =>		{ textname => 'Combinations', type_out => 'login', fields => [
	[ 'password',		0, 'Code', ],
    ]},
    creditcard =>		{ textname => 'Credit Cards', fields => [
	[ 'ccnum',		0, 'Card No.', ],
	[ '_expiry',		0, 'Expiration Date', ],
	[ 'cardholder',		0, 'Name', ],
	[ 'pin',		0, 'PIN', ],
	[ 'bank',		0, 'Bank', ],
	[ 'cvv',		0, 'Security Code', ],
    ]},
    email =>			{ textname => 'Email Accounts', fields => [
	[ 'pop_username',	0, 'Username', ],
	[ 'pop_password',	0, 'Password', ],
	[ 'pop_server',		0, 'POP3 Host', ],
	[ 'smtp_server',	0, 'SMTP Host', ],
    ]},
    frequentflyer =>		{ textname => 'Frequent Flyer', type_out => 'rewards', fields => [
	[ 'membership_no',	0, 'Number', ],
	[ 'website',		0, 'URL', ],
	[ 'member_name',	0, 'Username', ],
	[ 'pin',		0, 'Password', ],
	[ 'mileage',		0, 'Mileage', ],
    ]},
    identity =>			{ textname => 'Identity',  fields => [
	[ 'firstname',		0, 'First Name', ],
	[ 'lastname',		0, 'Last Name', ],
	[ 'nickname',		0, 'Nick Name',		{ custfield => [ $Utils::PIF::sn_identity, $Utils::PIF::k_string, 'nickname' ] }  ],
	[ 'company',		0, 'Company', ],
	[ 'jobtitle',		0, 'Title', ],
	[ 'address',		0, 'Address', ],	# code below assumes position index (5) and order: _street _street2 city state country zip
	[ 'address2',		0, 'Address2', ],
	[ 'city',		0, 'City', ],
	[ 'state',		0, 'State', ],
	[ 'country',		0, 'Country', ],
	[ 'zip',		0, 'Zip', ],
	[ 'homephone',		0, 'Home Phone', ],
	[ 'busphone',		0, 'Office Phone', ],
	[ 'cellphone',		0, 'Mobile Phone', ],
	[ 'email',		0, 'Email', ],
	[ 'email2',		0, 'Email2',		{ custfield => [ $Utils::PIF::sn_internet, $Utils::PIF::k_string, 'email2' ] } ],
	[ 'skype',		0, 'Skype', ],
	[ 'website',		0, 'Website', ],
    ]},
    insurance =>		{ textname => 'Insurance', type_out => 'membership', fields => [
	[ 'polid',		0, 'Policy No.',	{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_string, 'policy ID' ] } ],
	[ 'grpid',		0, 'Group No.',		{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_string, 'group ID' ] } ],
	[ 'insured',		0, 'Name',		{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_string, 'insured' ] } ],
	[ 'date',		0, 'Date', ],
	[ 'phone',		0, 'Phone No.', ],
    ]},
    login =>			{ textname => 'Web Logins', fields => [
	[ 'url',		0, 'URL', ],
	[ 'username',		0, 'Username', ],
	[ 'password',		0, 'Password', ],
    ]},
    membership =>		{ textname => 'Memberships', fields => [
	[ 'membership_no',	0, 'Account Number', ],
	[ 'member_name',	0, 'Name', ],
	[ '_member_since',	0, 'Date', ],		# or expiry_date?
    ]},
    note =>			{ textname => 'Note', fields => [
    ]},
    passport =>			{ textname => 'Passport', fields => [
	[ 'fullname',		0, 'Name', ],
	[ 'number',		0, 'Number', ],
	[ 'type',		0, 'Type', ],
	[ 'issuing_country',	0, 'Issuing Country', ],
	[ 'issuing_authority',	0, 'Issuing Authority', ],
	[ 'nationality',	0, 'Nationality', ],
	[ '_expiry_date',	0, 'Expiration', ],
	[ 'birthplace',		0, 'Place of Birth', ],
    ]},
    prescriptions =>		{ textname => 'Prescriptions', type_out => 'note', fields => [
	[ 'rxnumber',		0, 'RX Number', ],
	[ 'rxname',		0, 'Name', ],
	[ 'rxdoctor',		0, 'Doctor', ],
	[ 'rxpharmacy',		0, 'Pharmacy', ],
	[ 'rxphone',		0, 'Phone No.', ],
    ]},
    registrationcodes =>	{ textname => 'Registration Codes', type_out => 'note', fields => [
	[ 'regnumber',		0, 'Number', ],
	[ 'regdate',		0, 'Date', ],
    ]},
    socialsecurity =>		{ textname => 'Social Security', fields => [
	[ 'name',		0, 'Name', ],
	[ 'number',		0, 'Number', ],
    ]},
    unassigned =>		{ textname => 'Unassigned', type_out => 'note', fields => [
	[ 'field1',		0, 'Field1', ],
	[ 'field2',		0, 'Field2', ],
	[ 'field3',		0, 'Field3', ],
	[ 'field4',		0, 'Field4', ],
	[ 'field5',		0, 'Field5', ],
	[ 'field6',		0, 'Field6', ],
    ]},
    vehicleinfo =>		{ textname => 'Vehicle Info', type_out => 'note', fields => [
	[ 'vehiclelicno',	0, 'License No.', ],
	[ 'vehiclevin',		0, 'VIN', ],
	[ 'vehicledatepurch',	0, 'Date Purchased', ],
	[ 'vehicletiresize',	0, 'Tire Size', ],
    ]},
    voicemail =>		{ textname => 'Voice Mail', type_out => 'login', fields => [
	[ 'vmaccessno',		0, 'Access No.', ],
	[ 'password',		0, 'PIN', ],
    ]},
);

$DB::single = 1;					# triggers breakpoint when debugging

sub do_init {
    return {
	'specs'		=> \%card_field_specs,
	'imptypes'  	=> qw/userdefined/,
	'opts'		=> [ [ q{-l or --lang <lang>        # language in use: de es fr it ja ko pl pt ru zh-Hans zh-Hant},
			       'lang|l=s'	=> sub { init_localization_table($_[1]) or Usage(1, "Unknown language type: '$_[1]'") } ],
			   ],
    }
}

sub do_import {
    my ($file, $imptypes) = @_;
    my $eol_seq = $^O eq 'MSWin32' ? "\x{5c}\x{6e}" : "\x{0b}";

    # Map localized card type strings to supported card type keys
    my %ll_typeMap;
    for (keys %card_field_specs) {
	$ll_typeMap{ll($card_field_specs{$_}{'textname'})} = $_;
    }

    # The mSecure/Windows CSV output is horribly broken
    my $csv = Text::CSV->new ({
	    binary => 1,
	    allow_loose_quotes => 1,
	    sep_char => ',',
	    $^O eq 'MSWin32' ? ( eol => "\x{a}", escape_char => undef ) : (  eol => ",\x{a}" )
    });

    # The Windows version of mSecure exports CSV data as latin1 instead of UTF8.  Sigh.
    open my $io, $^O eq 'MSWin32' ? "<:encoding(latin1)" : "<:encoding(utf8)", $file
	or bail "Unable to open CSV file: $file\n$!";

    # The CSV export on the Mac contains the header row 'mSecure CSV export file' - toss it.
    if ($^O eq 'darwin') {
	local $/ = "\x{0a}";
	$_ = <$io>; 
    }

    my %Cards;
    my ($n, $rownum) = (1, 1);

    while (my $row = $csv->getline ($io)) {
	if ($row->[0] eq '' and @$row == 1) {
	    warn "Skipping unexpected empty row: $n";
	    next;
	}
	debug 'ROW: ', $rownum++;
	my ($itype, $otype, %cmeta, @fieldlist);

	# on Windows, need to convert \" into "
	if ($^O eq 'MSWin32') {
	    s/\\"/"/g		for @$row;
	}

	# mSecure CSV field order
	#
	#    group, cardtype, description, notes, ...
	#
	# The number of columns in each row varies by mSecure cardtype.  The %card_field_specs table
	# defines the meaning of each column per cardtype.  Some cardtypes will be remapped to 1P4
	# types.
	#
	$cmeta{'tags'}	 = shift @$row;
	my $msecure_type = shift @$row;
	$cmeta{'title'}	 = shift @$row;
	my $notes	 = shift @$row;

	my @notes_list = ([], [], []);
	push @{$notes_list[2]},	$notes	 if $notes ne '';

	$cmeta{'folder'} = [ $cmeta{'tags'} ];

	# When a user redefines an mSecure type, the card type and the field meanings are unknown.
	# In this case (the type isn't available in %ll_typeMap), force the card type to 'note' and push
	# to notes the values with generic labels prepended.
	#
	if (! exists $ll_typeMap{$msecure_type}) {
	    # skip 'userdefined' type not specifically included in a supplied import types list
	    next if defined $imptypes and (! exists $imptypes->{'userdefined'});

	    verbose "Renamed card type '$msecure_type' is not a default type, and is being mapped to Secure Notes\n";
	    $itype = $otype = 'note';
	    push @{$notes_list[0]}, join ': ', ll('Type'), $msecure_type;
	    my $i;
	    while (@$row) {
		my ($key, $val) = ('Field_' . $i++, shift @$row);
		debug "\tfield: $key => ", $val;
		push @{$notes_list[1]}, join ': ', $key, $val;
	    }
	}
	else {
	    $itype = $ll_typeMap{$msecure_type};
	    $otype = $card_field_specs{$itype}{'type_out'} // $itype;
	    $cmeta{'title'} = join ': ', $msecure_type, $cmeta{'title'}		if $itype ne $otype;

	    # skip all types not specifically included in a supplied import types list
	    next if defined $imptypes and (! exists $imptypes->{$itype});

	    # If the row contains more columns than expected, this may be the mSecure quoting problem with
	    # the notes (fourth) column.  To compensate, join the subsequent columns until the correct number
	    # of columns remains.
	    # broken: win 3.5.4 bld 40918
	    #
	    if (@$row > @{$card_field_specs{$itype}{'fields'}}) {
		verbose "**** Hit mSecure CSV quoting bug: row $n, card description '$cmeta{'title'}' - compensating...\n";

		# When the note leads with a double-quote, getline() leaves an empty string in column 4, and an extraneous
		# double-quote gets added to the final disjoint notes segment, which gets removed below.
		my $double_quote_added;
		if (! @{$notes_list[2]}) {
		    push @{$notes_list[2]}, '"';
		    $double_quote_added++;
		}

		while (@$row > @{$card_field_specs{$itype}{'fields'}}) {
		    $notes_list[2][-1] .= ',' . shift @$row;
		}
		$notes_list[2][-1] =~ s/"$//	if $double_quote_added;		# remove getline() added trailing double-quote
	    }

	    # process field columns beyond column 4 (notes)
	    for my $cfs (@{$card_field_specs{$itype}{'fields'}}) {
		my $val = shift @$row;
		debug "\tfield: $cfs->[CFS_MATCHSTR] => $val";
		push @fieldlist, [ $cfs->[CFS_MATCHSTR] => $val ];
	    }
	}

	# a few cleanups and flatten notes
	s/\Q$eol_seq\E/\n/g	for @{$notes_list[2]};
	$cmeta{'notes'} = myjoin "\n\n", map { myjoin "\n", @$_ } @notes_list;

	# special treatment for identity address ('address' is a $k_address type}
	if ($otype eq 'identity') {
	    my %h;
	    # assumption: fields are at $card_field_specs{'identity'}[5..10] and are in the following
	    # order: address address2 city state country zip
	    my $street_index = 5;
	    for (qw/street street2 city state country zip/) {
		$h{$_} = $fieldlist[$street_index++][1];
	    }
	    $h{'street'} = myjoin ', ', $h{'street'}, $h{'street2'};
	    delete $h{'street2'};
	    splice @fieldlist, 5, 6, [ Address => \%h ];
	}

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

# String localization.  mSecure has localized card types and field names, so these must be mapped
# to the localized versions in the Localizable.strings file for a given language.
# The %localized table will be initialized using the localized name as the key, and the english version
# as the value.
#
my %localized;

sub init_localization_table {
    my $lang = shift;
    main::Usage(1, "Unknown language type: '$lang'")
	unless defined $lang and $lang =~ /^(de|es|fr|it|ja|ko|pl|pt|ru|zh-Hans|zh-Hant)$/;

    if ($lang) {
	my $lstrings_path = '/Applications/mSecure.app/Contents/Resources/XX.lproj/Localizable.strings';
	$lstrings_path =~ s/XX/$lang/;

	local $/ = "\r\n";
	open my $lfh, "<:encoding(utf16)", $lstrings_path
	    or bail "Unable to open localization strings file: $lstrings_path\n$!";
	while (<$lfh>) {
	    chomp;
	    my ($key, $val) = split /" = "/;
	    $key =~ s/^"//;
	    $val =~ s/";$//;
	    #say "Key: $key, Val: $val";
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
