# mSecure CSV export converter
#
# Copyright 2014 Mike Cappella (mike@cappella.us)

package Converters::Msecure 1.00;

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
	[ 'member_name',	0, 'URL', ],
	[ 'pin',		0, 'Password', ],
	[ 'mileage',		0, 'Mileage', ],
    ]},
    identity =>			{ textname => 'Identity',  fields => [
	[ 'firstname',		0, 'First Name', ],
	[ 'lastname',		0, 'Last Name', ],
	[ 'nickname',		0, 'Nick Name', ],
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
	[ 'email2',		0, 'Email2', ],
	[ 'skype',		0, 'Skype', ],
	[ 'website',		0, 'Website', ],
    ]},
    insurance =>		{ textname => 'Insurance', type_out => 'membership', fields => [
	[ 'polid',		0, 'Policy No.', ],
	[ 'grpid',		0, 'Group No.', ],
	[ 'insured',		0, 'Name', ],
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

    my $csv = Text::CSV->new ({
	    binary => 1,
	    allow_loose_quotes => 1,
	    sep_char => ',',
	    $^O eq 'MSWin32' ? ( eol => "\x{a}", escape_char => undef ) : (  eol => ",\x{a}" )
    });

    # The Windows version of mSecure incorrectly exports data in CSV as latin1 instead of UTF8.  Sigh.
    open my $io, $^O eq 'MSWin32' ? "<:encoding(latin1)" : "<:encoding(utf8)", $file
	or bail "Unable to open CSV file: $file\n$!";

    # The CSV export on the Mac contains the header row 'mSecure CSV export file' - toss it.
    if ($^O eq 'darwin') {
	local $/ = "\x{0a}";
	$_ = <$io>; 
    }

    my %Cards;
    my ($n, $rownum) = (1, 1);
    my ($npre_explode, $npost_explode);

    while (my $row = $csv->getline ($io)) {
	if ($row->[0] eq '' and @$row == 1) {
	    warn "Skipping unexpected empty row: $n";
	    next;
	}
	debug 'ROW: ', $rownum++;
	my ($itype, $otype, @fieldlist);

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
	my $card_tags	 = shift @$row;
	my $msecure_type = shift @$row;
	my $card_title	 = shift @$row;
	my $notes	 = shift @$row;
	my @card_notes = ([], [], []);
	push @{$card_notes[2]},	$notes	 if $notes ne '';

	my $card_folder = [ $card_tags ];

	# When a user redefines an mSecure type, the card type and the field meanings are unknown.
	# In this case (the type isn't available in %ll_typeMap), force the card type to 'note' and push
	# to notes the values with generic labels prepended.
	#
	if (! exists $ll_typeMap{$msecure_type}) {
	    # skip 'userdefined' type not specifically included in a supplied import types list
	    # XXX why?
	    next if defined $imptypes and (! exists $imptypes->{'userdefined'});

	    verbose "Renamed card type '$msecure_type' is not a default type, and is being mapped to Secure Notes\n";
	    $itype = $otype = 'note';
	    push @{$card_notes[0]}, join ': ', ll('Type'), $msecure_type;
	    my $i;
	    while (@$row) {
		my ($key, $val) = ('Field_' . $i++, shift @$row);
		debug "\tfield: $key => ", $val;
		push @{$card_notes[1]}, join ': ', $key, $val;
	    }
	}
	else {
	    $itype = $ll_typeMap{$msecure_type};
	    $otype = $card_field_specs{$itype}{'type_out'} // $itype;
	    $card_title = join ': ', $msecure_type, $card_title		if $itype ne $otype;

	    # skip all types not specifically included in a supplied import types list
	    next if defined $imptypes and (! exists $imptypes->{$itype});

	    # If the row contains more columns than expected, this may be the mSecure quoting problem with
	    # the notes (fourth) column.  To compensate, join the subsequent columns until the correct number
	    # of columns remains.  # This bug is fixed in mSecure 3.5.4
	    #
	    if (@$row > @{$card_field_specs{$itype}{'fields'}}) {
		verbose "**** Hit mSecure CSV quoting bug: row $n, card description '$card_title' - compensating...\n";

		# When the note leads with a double-quote, getline() leaves an empty string in column 4, and an extraneous
		# double-quote gets added to the final disjoint notes segment, which gets removed below.
		my $double_quote_added;
		if (! @{$card_notes[2]}) {
		    push @{$card_notes[2]}, '"';
		    $double_quote_added++;
		}

		while (@$row > @{$card_field_specs{$itype}{'fields'}}) {
		    $card_notes[2][-1] .= ',' . shift @$row;
		}
		$card_notes[2][-1] =~ s/"$//	if $double_quote_added;		# remove getline() added trailing double-quote
	    }

	    # process field columns beyond column 4 (notes)
	    for my $def (@{$card_field_specs{$itype}{'fields'}}) {
		my $val = shift @$row;
		debug "\tfield: $def->[2] => $val";
		push @fieldlist, [ $def->[2] => $val ];			# retain field order
	    }
	}

	# a few cleanups and flatten notes
	s/\Q$eol_seq\E/\n/g	for @{$card_notes[2]};
	my $card_notes = myjoin "\n\n", map { myjoin "\n", @$_ } @card_notes;

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

	# From the card input, place it in the converter-normal format.
	# The card input will have matched fields removed, leaving only unmatched input to be processed later.
	my $normalized = normalize_card_data($itype, \@fieldlist, $card_title, $card_tags, \$card_notes, $card_folder);

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
    add_new_field('identity',     'email2',	$Utils::PIF::sn_internet,	$Utils::PIF::k_string,    'email2');
    add_new_field('identity',     'nickname',	$Utils::PIF::sn_identity,	$Utils::PIF::k_string,    'nickname');
    add_new_field('membership',   'polid',	$Utils::PIF::sn_main,		$Utils::PIF::k_string,    'policy ID');
    add_new_field('membership',   'grpid',	$Utils::PIF::sn_main,		$Utils::PIF::k_string,    'group ID');
    add_new_field('membership',   'insured',	$Utils::PIF::sn_main,		$Utils::PIF::k_string,    'insured');

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
    my ($type, $fieldlist, $title, $tags, $notesref, $folder, $postprocess) = @_;
    my %norm_cards = (
	title	=> $title,
	notes	=> $$notesref,
	tags	=> $tags,
	folder	=> $folder,
    );

    for my $def (@{$card_field_specs{$type}{'fields'}}) {
	my $h = {};
	for (my $i = 0; $i < @$fieldlist; $i++) {
	    my ($inkey, $value) = @{$fieldlist->[$i]};
	    next if not defined $value or $value eq '';

	    if ($inkey eq $def->[2]) {
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
