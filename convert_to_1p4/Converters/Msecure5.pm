# mSecure 5 CSV export converter
#
# Copyright 2018 Mike Cappella (mike@cappella.us)

package Converters::Msecure5 1.00;

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
use Time::Piece;

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
# mSecure 5 removes some categories and changes the names of some others.  It is not yet clear
# to me if users who upgrade will have both - may need to consolodate the msecure and msecure5 
# converters.  See the msecure converter for the original card_field_specs defs.
#
my %card_field_specs = (
    bankacct =>			{ textname => 'Bank Account', fields => [
	[ 'accountNo',		0, 'Account Number', ],
	[ 'telephonePin',	0, 'PIN', ],
	[ 'owner',		0, 'Name', ],
	[ 'branchAddress',	0, 'Branch', ],
	[ 'routingNo',		0, 'Routing Number', ],
	[ 'accountType',	0, 'Account Type', ],
	[ 'branchPhone',	0, 'Phone No.', ],
    ]},
    callingcards =>		{ textname => 'Calling Card', type_out => 'note', fields => [
	[ '_access_no',		0, 'Access No.', 	{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_string, 'access #' ] } ],
	[ '_pin',		0, 'PIN',		{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_concealed, 'pin', 'generate'=>'off' ] } ],
    ]},
    combination =>		{ textname => 'Combination', type_out => 'note', fields => [
	[ '_code',		0, 'Code', 		{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_concealed, 'code', 'generate'=>'off' ] } ],
    ]},
    creditcard =>		{ textname => 'Credit Card', fields => [
	[ 'ccnum',		0, 'Card No.', ],
	[ 'expiry',		0, 'Expiration Date', 		{ func => sub { return date2monthYear($_[0]) } } ],
	[ 'cvv',		0, 'Security Code', ],
	[ 'cardholder',		0, 'Name', ],
	[ 'pin',		0, 'PIN', ],
	[ 'bank',		0, 'Bank', ],
	[ 'phoneTollFree',	0, 'Phone Number', ],
	[ '_billingaddress',	0, 'Billing Address', ],
    ]},
    email =>			{ textname => 'Email Account', fields => [
	[ 'smtp_username',	0, 'Username', ],
	[ 'smtp_password',	0, 'Password', ],
	[ '_imap_server',	0, 'Incoming Mail Server', ],
	[ '_imap_port',		0, 'Incoming Port', ],
	[ 'smtp_server',	0, 'Outgoing mail Server', ],
	[ 'smtp_port',		0, 'Outgoing Port', ],
	[ 'pop_server',		0, 'POP3 Host', ],
	[ '_smtp_host',		0, 'SMTP Host', ],
    ]},
    frequentflyer =>		{ textname => 'Frequent Flyer', type_out => 'rewards', fields => [
	[ 'membership_no',	0, 'Number', ],
	[ 'website',		0, 'URL', ],
	[ 'member_name',	0, 'Username', ],
	[ 'pin',		0, 'Password', ],
	[ 'mileage',		0, 'Mileage', ],
    ]},
    insurance =>		{ textname => 'Insurance Info', type_out => 'membership', fields => [
	[ 'polid',		0, 'Policy No.',	{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_string, 'policy ID' ] } ],
	[ 'grpid',		0, 'Group No.',		{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_string, 'group ID' ] } ],
	[ 'insured',		0, 'Name',		{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_string, 'insured' ] } ],
	[ 'date',		0, 'Date', ],
	[ 'phone',		0, 'Phone No.', ],
    ]},
    login =>			{ textname => 'Login', fields => [
	[ 'url',		0, 'URL', ],
	[ 'username',		0, 'Username', ],
	[ 'password',		0, 'Password', ],
	[ '_empty1',		0, 'empty1', ],
	[ '_empty2',		0, 'empty2', ],
    ]},
    membership =>		{ textname => 'Membership', fields => [
	[ 'membership_no',	0, 'Account Number', ],
	[ 'member_name',	0, 'Name', ],
	[ 'member_since',	0, 'Start Date', 		{ func => sub { return date2monthYear($_[0]) }, keep => 1 } ],
	[ 'expiry_date',	0, 'Expiration Date', 		{ func => sub { return date2monthYear($_[0]) }, keep => 1 } ],
    ]},
    note =>			{ textname => 'Secure Note', fields => [
    ]},
);

$DB::single = 1;					# triggers breakpoint when debugging

sub do_init {
    return {
	'specs'		=> \%card_field_specs,
	'imptypes'  	=> qw/userdefined/,
	'opts'		=> [ 
	      		     [ q{      --sepchar <char>     # set the CSV separator character to char },
			       'sepchar=s' ],
	      		     [ q{      --dumpcats           # print the export's categories and field quantities },
			       'dumpcats' ],
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

    my $sep_char = $main::opts{'sepchar'} // ',';

    length $sep_char == 1 or
	bail "The separator character should only be a single character - you've specified \"$sep_char\" which is ", length $sep_char, " characters.";

    # The mSecure/Windows CSV output is horribly broken
    my $csv = Text::CSV->new ({
	    binary => 1,
	    allow_loose_quotes => 1,
	    sep_char => $sep_char,
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

    my %cat_field_tally;
    my %Cards;
    my ($n, $rownum) = (1, 1);

    while (my $row = $csv->getline ($io)) {
	if ($row->[0] eq '' and @$row == 1) {
	    warn "Skipping unexpected empty row: $n";
	    next;
	}

	@$row >= 4 or
	    bail 'Only detected ', scalar @$row, pluralize(' column', scalar @$row), " in row $rownum.\n",
	    "The CSV separator \"$sep_char\" may be incorrect (use --sepchar), or perhaps you've edited the CSV mSecure export?";

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
	push @{$cmeta{'tags'}}, shift @$row;
	my $msecure_type = shift @$row;
	$cmeta{'title'}	 = shift @$row;
	my $notes	 = shift @$row;

	if ($main::opts{'dumpcats'}) {
	    $cat_field_tally{$msecure_type}{scalar @$row}++;
	    next;
	}

	my @notes_list = ([], [], []);
	push @{$notes_list[2]},	$notes	 if $notes ne '';

	$cmeta{'folder'} = [ $cmeta{'tags'}[0] ];
	push @{$cmeta{'tags'}}, join '::', 'mSecure', $msecure_type;

	# When a user redefines an mSecure type, the card type and the field meanings are unknown.
	# In this case (the type isn't available in %ll_typeMap), force the card type to 'note' and push
	# to notes the values with generic labels prepended.
	#
	if (! exists $ll_typeMap{$msecure_type}) {
	    # skip 'userdefined' type not specifically included in a supplied import types list
	    next if defined $imptypes and (! exists $imptypes->{'userdefined'});

	    verbose "Renamed card type '$msecure_type' is not a default type, and is being mapped to Secure Notes\n";
	    $itype = $otype = 'note';
	    #push @{$notes_list[0]}, join ': ', ll('Type'), $msecure_type;
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

		# msecure 5 replaces simple ASCII double quotes in some fields with unicode right and left quotes
		# during entry or upon export to CSV.
		$val =~ s/\x{201C}|\x{201D}/"/g;

		debug "\tfield: $cfs->[CFS_MATCHSTR] => $val";
		push @fieldlist, [ $cfs->[CFS_MATCHSTR] => $val ];
	    }
	}

	# a few cleanups and flatten notes
	s/\Q$eol_seq\E/\n/g	for @{$notes_list[2]};
	$cmeta{'notes'} = myjoin "\n\n", map { myjoin "\n", @$_ } @notes_list;

	$cmeta{'notes'} =~ s/\x{201C}|\x{201D}/"/g;		# replace unicode left and right quotes

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

    if ($main::opts{'dumpcats'}) {
	printf "%25s %10s   %s\n", 'Categories', 'Known?', 'Field Count(s)';
	for my $catname (sort keys %cat_field_tally) {
	    printf "%25s %8s         %s\n", $catname,
		    ( grep { $card_field_specs{$_}{'textname'} eq $catname  } keys %card_field_specs ) ? 'yes' : 'NO',
		    join(", ", map { $_ + 4 } keys %{$cat_field_tally{$catname}});
	}

	return undef;
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
# Version 5 appear to not ship with languges files, so lets look in our local Languages directory.
#
my %localized;

sub init_localization_table {
    my $lang = shift;
    main::Usage(1, "Unknown language type: '$lang'")
	unless defined $lang and $lang =~ /^(de|es|fr|it|ja|ko|pl|pt|ru|zh-Hans|zh-Hant)$/;

    if ($lang) {
	my $lstrings_base = 'XX.lproj/Localizable.strings';
	$lstrings_base =~ s/XX/$lang/;
	my $lstrings_path = join '/', '/Applications/mSecure.app/Contents/Resources', $lstrings_base;
	if (! -e $lstrings_path) {
	    $lstrings_path = join '/', 'Languages/mSecure', $lstrings_base;
	}

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

# mm/yyyy
# mm/dd/yyyy
sub parse_date_string {
    local $_ = $_[0];

    if (/^(\d{2})\/(\d{4})$/) {
	if (my $t = Time::Piece->strptime($_, "%m/%Y")) {
	    return $t;
	}
    }
    elsif (/^(\d{2})\/(\d{2})\/(\d{4})$/) {
	if (my $t = Time::Piece->strptime($_, "%m/%d/%Y")) {
	    return $t;
	}
    }

    return undef;
}

sub date2monthYear {
    my $t = parse_date_string @_;

    return defined $t->year ? sprintf("%d%02d", $t->year, $t->mon) : $_[0];
}

1;
