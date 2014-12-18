# SplashID VID export converter
#
# Copyright 2014 Mike Cappella (mike@cappella.us)

package Converters::Splashid 1.02;

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

# note: the second field, the type hint indicator (e.g. $card_field_specs{$type}[$i][1]}),
# is not used, but remains for code-consisency with other converter modules.
#
my %card_field_specs = (
    bankacct =>			{ textname => 'Bank Accounts', fields => [
	[ 'accountNo',		0, 'Account #', ],
	[ 'telephonePin',	0, 'PIN', ],
	[ 'owner',		0, 'Name', ],
	[ 'branchAddress',	0, 'Branch', ],
	[ 'phone',		0, 'Phone #', ],
    ]},
    clothes =>			{ textname => 'Clothes Size', type_out => 'note', fields => [
	[ 'shirt_size',		0, 'Shirt Size', ],
	[ 'pant_size',		0, 'Pant Size', ],
	[ 'shoe_size',		0, 'Shoe Size', ],
	[ 'dress_size',		0, 'Dress Size', ],
	[ 'ring_size',		0, 'Ring Size', ],
    ]},
    combinations =>		{ textname => 'Combinations', type_out => 'login', fields => [
	[ 'password',		0, 'Code', ],
    ]},
    creditcard =>		{ textname => 'Credit Cards', fields => [
	[ 'ccnum',		0, 'Card #', ],
	[ '_expiry',		0, 'Expiry Date', ],
	[ 'cardholder',		0, 'Name', ],
	[ 'pin',		0, 'PIN', ],
	[ 'bank',		0, 'Bank', ],
    ]},
    email =>		       { textname => 'Email Accounts', fields => [
	[ 'pop_username',	0, 'Username', ],
	[ 'pop_password',	0, 'Password', ],
	[ 'pop_server',		0, 'POP3 Host', ],
	[ 'smtp_server',	0, 'SMTP Host', ],
    ]},
    files =>		       { textname => 'Files', type_out => 'note', fields => [
	[ 'filestype',		0, 'Document Type', ],
	[ 'filescreator',	0, 'Creator', ],
	[ 'filesdate',		0, 'Date', ],
    ]},
    frequentflyer =>		{ textname => 'Frequent Flyer', type_out => 'membership', fields => [
	[ 'membership_no',	0, 'Number', ],
	[ 'member_name',	0, 'Name', ],
	[ '_date',		0, 'Date', ],
    ]},
    identification =>		{ textname => 'Identification', type_out => 'membership', fields => [
	[ 'membership_no',	0, 'Number', ],
	[ 'member_name',	0, 'Name', ],
	[ '_date',		0, 'Date', ],
    ]},
    insurance =>		{ textname => 'Insurance', type_out => 'membership', fields => [
	[ 'polid',		0, 'Policy #', ],
	[ 'grpid',		0, 'Group #', ],
	[ 'insured',		0, 'Insured', ],
	[ '_date',		0, 'Date', ],
    ]},
    membership =>		{ textname => 'Memberships', fields => [
	[ 'membership_no',	0, 'Account Number', ],
	[ 'member_name',	0, 'Name', ],
	[ '_date',		0, 'Date', ],
    ]},
    phonenumbers =>		{ textname => 'Phone Numbers', type_out => 'note', fields => [
	[ 'phone',		0, 'Phone #', ],
    ]},
    prescriptions =>		{ textname => 'Prescriptions', type_out => 'note', fields => [
	[ 'rxnumber',		0, 'RX#', ],
	[ 'rxname',		0, 'Name', ],
	[ 'rxdoctor',		0, 'Doctor', ],
	[ 'rxpharmacy',		0, 'Pharmacy', ],
	[ 'rxphone',		0, 'Phone #', ],
    ]},
    serialnum =>		{ textname => 'Serial Numbers', type_out => 'note', fields => [
	[ 'serialnum',		0, 'Serial #', ],
	[ 'serialdate',		0, 'Date', ],
	[ 'serialreseller',	0, 'Reseller', ],
    ]},
    server =>			{ textname => 'Servers', fields => [
	[ 'username',		0, 'Username', ],
	[ 'password',		0, 'Password', ],
	[ 'admin_console_url',	0, 'Address', ],
    ]},
    vehicles =>		        { textname => 'Vehicles', type_out => 'note', fields => [
	[ 'vehiclelicense',	0, 'License Plate #', ],
	[ 'vehiclevin',		0, 'VIN #', ],
	[ 'vehicleinsurance',	0, 'Insurance', ],
	[ 'vehicleyear',	0, 'Year', ],
    ]},
    weblogins =>		{ textname => 'Web Logins', type_out => 'login', fields => [
	[ 'username',		0, 'Username', ],
	[ 'password',		0, 'Password', ],
	[ 'url',		0, 'URL', ],
    ]},
);

$DB::single = 1;					# triggers breakpoint when debugging

sub do_init {
    return {
	'specs'		=> \%card_field_specs,
	'imptypes'  	=> undef,
	'opts'		=> [],
    }
}

# Defines location and range values of columns in the vID for a given version; the table contains only values where there
# are differences amongst versions, and these values are after shifting out the first two columns in the row.
my %vid_table = (
    '3.0' => { num_f_cols => 23, labels_cust_col => [11..19], tags_col => 21, notes_col => 22 },
    '4.0' => { num_f_cols => 26, labels_cust_col => [14..22], tags_col => 24, notes_col => 25, attach_filename_col => 10 },
);

sub do_import {
    my ($file, $imptypes) = @_;
    my $vid_version;
    my $eol = $^O eq 'MSWin32' ? "\n" : "\x{0d}";

    # Map localized card type strings to supported card type keys
    my %ll_typeMap;
    for (keys %card_field_specs) {
	# not localized yet
	#$ll_typeMap{ll($card_field_specs{$_}{'textname'})} = $_;
	$ll_typeMap{$card_field_specs{$_}{'textname'}} = $_;
    }

    my $csv = Text::CSV->new ({
	    binary => 1,
	    allow_loose_quotes => 0,
	    sep_char => ',',
	    eol => $eol,
	    quote_char => '"',
    });


    # Encoding is done using the MacRoman encoding scheme, even on Windows.  Neither the SplashID Windows app as of
    # version 7.2.4 (April 2014), nor the Web App, shows the correct decoding; the Windows app botches the characters,
    # and the web app seems to suppress output altogether.  Furthermore, it seems encoding switches on a row-by-row basis.
    #
    # XXX: yuck - see https://discussions.agilebits.com/discussion/comment/153882/#Comment_153882
    #open my $io, "<:encoding(macroman)", $file
    open my $io, "<:encoding(UTF-8)", $file
	or bail "Unable to open VID file: $file\n$!";

    # Verify (CSV hybrid) VID 3.0 or 4.0 from the first line for the export file
    #    SplashID vID File -v3.0
    #    F
    {
	local $/ = $eol;
	$_ = <$io>;
	/^SplashID vID File -v([34]\.0)/ or bail 'File is not a version 3.0 or 4.0 VID file: ', $file;
	$vid_version = $1;
	$_ = <$io>; 	# toss the single char 'F' row.
    }

    my %Cards;
    my ($n, $rownum) = (1, 1);
    my ($npre_explode, $npost_explode);
    my (@labels, @values, @labels_cust);
    my ($card_type, $card_title, $card_tags, @card_notes);

    while (my $row = $csv->getline ($io)) {
	if ($row->[0] eq '' and @$row == 1) {
	    warn "Skipping unexpected empty row: $n";
	    next;
	}
	debug 'ROW: ', $rownum++;

	my ($itype, @fieldlist);

	# SplashID vID 3 overview
	#
	# Column  1 indicates the row type (T=text labels, F=field values).
	# Column  2 is a reference number indicating the card's icon - it is ignored by the converter.
	# Column  3 for T rows is the card's type.
	#  *** to make the description easier, the following text assumes the T row has been left-shifted by one:
	#    T, #, type, description, ...	<--- left shift by one
	#    F, #, description, ...
	# Columns 3 - 11 are the card field labels (T rows) and values (F rows), with column 3 being 'Description' for
	#   all stock types except Vehicles and for custom types or possibly customized cards.
	# Column  12 is the card's modified date
	# Column  13 is a bit field value indicating which of the fields 1 through 9 are hidden (masked).
	# Columns 14 - 22 are the card's customized field labels, overriding values in the T row above.
	# Column  24 is the card's category.
	# Column  25 contains the card's notes.
	#
	my $row_type = shift @$row;
	my $imageid = shift @$row;					# currently unused
	if ($row_type eq 'T') {
	    if (@$row == 3 and $row->[0] eq 'Unfiled') {		# Uncustomized category == Unfiled contains sparse labels - normalize them
		splice @$row, 1, 0, map { 'Field ' . $_ } 1..10
	    }

	    @$row == 13	or bail "Unexpected number of labels: ", scalar @$row;

	    @labels = ();
	    ($card_type, @labels) = @$row[0,1..11];
	    debug "\ttype: $card_type, @labels";
	    next;
	}
	else {
	    debug "\tvalues: @$row";
	    @$row == $vid_table{$vid_version}{'num_f_cols'} or
		bail "Unexpected number of fields: ", scalar @$row;

	    @values = (); @labels_cust = ();
	    $card_notes[0] = ();
	    $card_notes[1] = ();
	    ($card_tags, $card_notes[2][0]) = @$row[@{$vid_table{$vid_version}}{'tags_col','notes_col'}];
	    @values 	 = @$row[0..10];
	    @labels_cust = @$row[(@{$vid_table{$vid_version}{'labels_cust_col'}})];
	    push @labels_cust, '';		# adds an empty 10th label, which is where Date Mod is in Labels

	    # The last item in @labels and @values is a bit field value indicating which fields 1 to 10 are masked.
	    # Ignore it for now.
	    pop @labels		if @labels ne 10;
	    pop @values;

	    # vID 4.0 file includes the attachment's original filename, encryption key, and attachment's file name
	    if ($vid_version eq '4.0') {
		if ($row->[$vid_table{$vid_version}{'attach_filename_col'}] ne '') {
		    push @{$card_notes[1]}, join ': ', 'Original file name', $row->[$vid_table{$vid_version}{'attach_filename_col'}]
		}
	    }
	}


	$card_title = '';
	# When a user redefines a card type, the card type and the field semantics are unknown.
	# In this case (the type isn't available in %ll_typeMap), force the card type to 'note' and push
	# to notes the label:value pairs.
	#
	if (exists $ll_typeMap{$card_type}) {
	    $itype = $ll_typeMap{$card_type};

	    # skip all types not specifically included in a supplied import types list
	    next if defined $imptypes and (! exists $imptypes->{$itype});

	    # pair up the standard or card-specific labels with the values
	    for (my $i = 0; $i <= 9; $i++) {
		my ($label, $val) = ($labels_cust[$i] ne '' ? $labels_cust[$i] : $labels[$i], $values[$i]);
		next if $val eq '';
		if ($label eq 'Description') {
		    $card_title = $val;
		}
		else {
		    # @fieldlist maintains card's field order
		    push @fieldlist, [ $label => $val ]
		}

		# The Vehicles card uses "Make/Model" as the Description, so default to using the standard
		# column 3 when $card_title is not set.
		$card_title ||= $values[0] || '';
	    }
	}
	else {
	    debug "Card type '$card_type' is not a default type, and is being mapped to Secure Notes";
	    $itype = 'note';
	    my $i;
	    for (my $i = 0; $i <= 9; $i++) {
		my ($label, $val) = ($labels_cust[$i] ne '' ? $labels_cust[$i] : $labels[$i], $values[$i]);
		debug "\tfield: $label => ", $val;
		if ($label eq 'Description') {
		    $card_title = $val;
		}
		else {
		    push @{$card_notes[1]}, join ': ', $label, $val		if $val ne '';
		}

		# The Vehicles card uses "Make/Model" as the Description, so default to using the standard
		# first field value when $card_title is not set.
		$card_title ||= $values[0] || '';
	    }

	    $card_title = join ': ', $card_type, $card_title;
	}

	# a few cleanups and flatten notes
	my $card_notes = myjoin "\n\n", map { myjoin "\n", @$_ } @card_notes;

	# From the card input, place it in the converter-normal format.
	# The card input will have matched fields removed, leaving only unmatched input to be processed later.
	my $normalized = normalize_card_data($itype, \@fieldlist, $card_title, $card_tags, \$card_notes);

	# Returns list of 1 or more card/type hashes;possible one input card explodes to multiple output cards
	# common function used by all converters?
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
    add_new_field('bankacct',     'phone',	$Utils::PIF::sn_branchInfo,	$Utils::PIF::k_string,    'phone');
    add_new_field('membership',   'polid',	$Utils::PIF::sn_main,		$Utils::PIF::k_string,    'policy #');
    add_new_field('membership',   'grpid',	$Utils::PIF::sn_main,		$Utils::PIF::k_string,    'group #');
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
    my ($type, $fieldlist, $title, $tags, $notesref, $postprocess) = @_;
    my %norm_cards = (
	title	=> $title,
	notes	=> $$notesref,
	tags	=> $tags,
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

1;
