# SafeWallet XML export converter
#
# Copyright 2014 Mike Cappella (mike@cappella.us)

package Converters::Safewallet 1.00;

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
use XML::XPath;
use XML::XPath::XMLParser;
use Time::Local qw(timelocal);
use Date::Calc qw(check_date Date_to_Days Moving_Window);

my %card_field_specs = (
    address =>			{ textname => undef, type_out => 'identity', fields => [
	[ 'addr_place',		0, qr/^Place$/, ],
	[ 'firstname',		0, qr/^First Name$/, ],
	[ 'lastname',		0, qr/^Last Name$/, ],
	[ 'address',		0, qr/^address$/, ],			# combines original fields: Address #[123]
	[ 'addr1',		1, qr/^Address #1$/, ],
	[ 'addr2',		1, qr/^Address #2$/, ],
	[ 'addr3',		1, qr/^Address #3$/, ],
	[ 'city',		0, qr/^City$/, ],
	[ 'state',		0, qr/^State$/, ],
	[ 'zip',		1, qr/^ZIP$/, ],
	[ 'country',		1, qr/^Country$/, ],
	[ 'homephone',		0, qr/^Phone$/, ],
	[ 'email',		0, qr/^Email$/, ],
    ]},
    bankacct =>			{ textname => undef, fields => [
	[ 'accountNo',          0, qr/^Account #$/, ],
	[ '_branchNumber',	1, qr/^Branch #$/, ],
	[ '_bankNumber',	1, qr/^Bank #$/, ],
	[ 'bankName',		0, qr/^Branch Name$/, ],
	[ 'routingNo',		0, qr/^Routing #$/, ],
	[ 'contact1',		1, qr/^Contact Person 1$/, ],
	[ 'contactphone1',	0, qr/^Phone 1$/, ],
	[ 'contact2',		1, qr/^Contact Person 2$/, ],
	[ 'contactphone2',	0, qr/^Phone 2$/, ],
	[ 'bankhours',		1, qr/^Opening Hours$/, ],
	[ 'accountType',	0, qr/^Type$/, ],
	[ 'telephonePin',	1, qr/^ATM PIN$/, ],
	[ 'swift',		1, qr/^SWIFT$/, ],
	[ 'url',		0, qr/^Web-Site$/,		{ type_out => 'login' } ],
	[ 'username',		0, qr/^Username$/,		{ type_out => 'login' } ],
	[ 'password',		0, qr/^Password$/,		{ type_out => 'login' } ],
    ]},
    callingcard =>		{ textname => undef, type_out => 'note', fields => [
	[ 'callcardprovider',	0, qr/^Provider$/, ],
	[ 'callcardaccessnum',	1, qr/^Access #$/, ],
	[ 'callcardnum',	0, qr/^Card #$/, ],
	[ 'callcardpin',	0, qr/^PIN$/, ],
	[ 'callcardphone',	0, qr/^If Lost$/, ],
	[ 'callcardusage',	1, qr/^Usage$/, ],
    ]},
    carinfo =>			{ textname => undef, type_out => 'note', fields => [
	[ 'carinfomodel',	1, qr/^Model$/, ],
	[ 'carinfomake',	1, qr/^Make$/, ],
	[ 'carinfoyear',	1, qr/^Year$/, ],
	[ 'carinfolicense',	1, qr/^License$/, ],
	[ 'carinfoexpires',	0, qr/^Expires$/, ],
	[ 'carinfovin',		1, qr/^Vehicle Identification Number \(VIN\)$/, ],
	[ 'carinfoinsurance',	1, qr/^Insurance$/, ],
	[ 'carinfopolicy',	0, qr/^Policy #$/, ],
	[ 'carinfophone',	0, qr/^Phone$/, ],
    ]},
    clothing =>			{ textname => undef, type_out => 'note', fields => [
	[ 'clothingfor',	1, qr/^Size For$/, ],
	[ 'clothingsuit',	1, qr/^Suit$/, ],
	[ 'clothingshoes',	1, qr/^Shoes$/, ],
	[ 'clothingshirt',	1, qr/^Shirt$/, ],
	[ 'clothingwaist',	1, qr/^Waist$/, ],
	[ 'clothingpants',	1, qr/^Pants$/, ],
	[ 'clothingneck',	1, qr/^Neck$/, ],
	[ 'clothinginseam',	1, qr/^Inseam$/, ],
	[ 'clothingskirt',	1, qr/^Skirt$/, ],
	[ 'clothingglove',	1, qr/^Glove$/, ],
    ]},
    contact =>			{ textname => undef, type_out => 'note', fields => [
	[ 'contact',		0, qr/^First Name$/, ],
	[ 'contact',		0, qr/^Last Name$/, ],
	[ 'contact',		0, qr/^Company$/, ],
	[ 'contact',		1, qr/^Mobile Phone$/, ],
	[ 'contact',		1, qr/^Home Phone$/, ],
	[ 'contact',		1, qr/^Business Phone$/, ],
	[ 'contact',		0, qr/^Email$/, ],
    ]},
    creditcard =>		{ textname => undef, fields => [
	[ 'type',		0, qr/^Type$/, ],
	[ 'bank',		0, qr/^Bank$/, ],
	[ '_firstname',		0, qr/^First Name$/, ],		# see post_process_normalized
	[ '_lastname',		0, qr/^Last Name$/, ],		# see post_process_normalized
	[ 'ccnum',		0, qr/^Card #$/, ],
	[ 'expiry',		0, qr/^Expires$/,		{ func => sub { return date2monthYear($_[0], 2) }, keep => 1 } ],
	[ 'cvv',		1, qr/^CVV2$/, ],
	[ 'pin',		0, qr/^PIN$/, ],
	[ 'phoneTollFree',	1, qr/^If Lost$/, ],
	[ 'type',		0, undef ],			# special case - will never match, used to set card type when possible
    ]},
    driverslicense =>           { textname => undef, fields => [
	[ 'number',		0, qr/^Number$/, ],
	[ 'dllocation',		1, qr/^Location$/, ],
	[ 'issued_on',		1, qr/^Issued On$/,		{ func => sub { return date2monthYear($_[0], 2) }, keep => 1 } ],
	[ 'expiry_date',	0, qr/^Expires$/, 		{ func => sub { return date2monthYear($_[0], 2) }, keep => 1 } ],
    ]},
    email =>			{ textname => undef, fields => [
	[ 'pop_username',      	0, qr/^Username$/ ],
	[ 'pop_password',      	0, qr/^Password/ ],
	[ 'pop_server',      	1, qr/^POP3 Server$/ ],
	[ 'smtp_server',      	1, qr/^SMTP Server$/ ],
	[ 'smtp_username',     	0, qr/^SMTP Username$/ ],
	[ 'smtp_password',     	0, qr/^SMTP Password$/ ],
	[ 'emailstorager',     	1, qr/^Storage Space \(mb\)$/ ],
    ]},
    emergency =>		{ textname => undef, type_out => 'note', fields => [
	[ 'emergencyfire',     	1, qr/^Fire$/ ],
	[ 'emergencyambulance',	1, qr/^Ambulance$/ ],
	[ 'emergencypolice',	1, qr/^Police$/ ],
	[ 'emergencydoctor',	0, qr/^Doctor$/ ],
    ]},
    frequentflyer =>		{ textname => undef, type_out => 'rewards', fields => [
	[ 'company_name',     	1, qr/^Airline$/ ],
	[ 'membership_no',     	0, qr/^Account #$/ ],
	[ 'pin',     		0, qr/^PIN$/ ],
	[ 'ffstatus',     	1, qr/^Status$/ ],
	[ '_phone1',     	1, qr/^Phone #1$/ ],
	[ '_phone2',     	1, qr/^Phone #2$/ ],
	[ 'url',     		0, qr/^Web-Site$/,		{ type_out => 'login' } ],
	[ 'username',     	0, qr/^Username$/,		{ type_out => 'login' } ],
	[ 'password',     	0, qr/^Password$/,		{ type_out => 'login' } ],
    ]},
    healthinsurance =>		{ textname => undef, type_out => 'membership', fields => [
	[ 'polid',     		0, qr/^ID$/ ],
	[ 'grpid',     		1, qr/^Group$/ ],
	[ 'plan',     		1, qr/^Plan$/ ],
	[ 'phone',     		0, qr/^Phone$/ ],
	[ 'sponsor',     	1, qr/^Sponsor$/ ],
    ]},
    idcard =>			{ textname => undef, type_out => 'membership', fields => [
	[ 'idtitle',		1, qr/^Title$/ ],
	[ 'org_name',		1, qr/^Organization$/ ],
	[ '_firstname',		0, qr/^First Name$/ ],		# see post_process_normalized
	[ '_lastname',		0, qr/^Last Name$/ ],		# see post_process_normalized
	[ 'membership_no',	0, qr/^ID$/ ],
    ]},
    irc =>			{ textname => undef, type_out => 'server', fields => [
	[ 'url',		1, qr/^BNC Server$/ ],
	[ 'username',		1, qr/^User\/Ident$/ ],
	[ 'password',		1, qr/^Password$/ ],
	[ 'ircport',		0, qr/^Port$/ ],
    ]},
    insurance =>		{ textname => undef, type_out => 'membership', fields => [
	[ 'org_name',		0, qr/^Company$/ ],
	[ 'polid',     		0, qr/^Policy #$/ ],
	[ 'poltype',   		0, qr/^Type$/ ],
	[ 'expiry_date',     	0, qr/^Expires$/,		{ func => sub { return date2monthYear($_[0], 2) }, keep => 1 } ],
	[ 'phone',     		0, qr/^Phone$/ ],
    ]},
    internet =>                 { textname => undef, type_out => 'email', fields => [
	[ 'provider',		0, qr/^Provider$/, ],
	[ 'ispemail',		0, qr/^Email$/, ],
	[ 'isplogin',		0, qr/^Login$/, ],
	[ 'isppassword',	0, qr/^Password$/, ],
	[ 'phone_local',	1, qr/^Dialup$/, ],
	[ 'ispdns1',		1, qr/^Primary DNS$/, ],
	[ 'ispdns2',		1, qr/^Alternate DNS$/, ],
	[ 'pop_server',		1, qr/^POP3$/, ],
	[ 'smtp_server',	1, qr/^SMTP$/, ],
	[ 'smtp_username',	0, qr/^SMTP Username$/, ],
	[ 'smtp_password',	0, qr/^SMTP Password$/, ],
	[ 'ispnntp_server',	1, qr/^NNTP$/, ],
    ]},
    lens =>                 	{ textname => undef, type_out => 'note', fields => [
	[ 'lenstype',		0, qr/^Type$/, ],
	[ 'lensright',		1, qr/^Right \(OD\)$/, ],
	[ 'lenslleft',		1, qr/^Left \(OS\)$/, ],
	[ 'lensdoctor',		0, qr/^Doctor$/, ],
	[ 'lensphone',		0, qr/^Phone Number$/, ],
    ]},
    librarycard =>		{ textname => undef, type_out => 'membership', fields => [
	[ 'org_name',		1, qr/^Library$/ ],
	[ 'membership_no',	0, qr/^Card #$/ ],
    ]},
    login =>                    { textname => undef, fields => [
	[ 'username',		0, qr/^Login$/, ],
	[ 'password',		0, qr/^Password$/, ],
	[ 'url',		1, qr/^URL$/, ],
    ]},
    note =>                    { textname => undef, fields => [
    ]},
    passport =>                 { textname => undef, fields => [
	[ 'type',		0, qr/^Type$/, ],
	[ 'number',		0, qr/^Number$/, ],
	[ '_firstname',		0, qr/^First Name$/, ],		# see post_process_normalized
	[ '_lastname',		0, qr/^Last Name$/, ],		# see post_process_normalized
	[ 'birthdate',		0, qr/^Birth Date$/,		{ func => sub { return date2epoch($_[0], 2) } } ],
	[ 'birthplace',		1, qr/^Place$/, ],
	[ 'nationality',	1, qr/^National$/, ],
	[ 'issue_date',		0, qr/^Issued$/, 		{ func => sub { return date2epoch($_[0], 2) } } ],
	[ 'expiry_date',	0, qr/^Expires$/, 		{ func => sub { return date2epoch($_[0], 2) } } ],
	[ 'issuing_authority',	1, qr/Authority/, ],
    ]},
    password =>                 { textname => undef, type_out => 'server', fields => [
	[ 'pwsystem',		1, qr/^System$/, 		{ to_title => 'value' } ],
	[ 'username',		0, qr/^Login$/, ],
	[ 'password',		0, qr/^Password$/, ],
	[ 'pwaccess',		1, qr/^Access$/, ],
    ]},
    prescription =>             { textname => undef, type_out => 'note', fields => [
	[ 'rxdrug',		1, qr/^Drug$/ ],
	[ 'rxamount',		1, qr/^Amount$/ ],
	[ 'rxdosage',		1, qr/^Take$/ ],
	[ 'rxbrand',		0, qr/^Brand$/ ],
	[ 'rxpurchasedate',	0, qr/^Purchased$/ ],
	[ 'rxpharmacy',		1, qr/^Pharmacy$/ ],
	[ 'rxdoctor',		0, qr/^Doctor$/ ],
	[ 'rxphone',		0, qr/^Phone$/ ],
    ]},
    serialnumber =>             { textname => undef, type_out => 'note', fields => [
	[ 'snproduct',		1, qr/^Product$/ ],
	[ 'snbrand',		0, qr/^Brand$/ ],
	[ 'snnum',		1, qr/^Serial #$/ ],
	[ 'snmodel',		1, qr/^Model #$/ ],
	[ 'snversion',		1, qr/^Version$/ ],
	[ 'snpurchasedate',	1, qr/^Purchase Date$/ ],
	[ 'snwebsite',		0, qr/^Web-Site$/ ],
    ]},
    server =>			{ textname => undef, type_out => 'server', fields => [
	[ 'url',		1, qr/^IP$/ ],
	[ 'ircport',		0, qr/^Port$/ ],
	[ 'username',		1, qr/^RCON$/ ],
    ]},
    socialsecurity =>           { textname => undef, fields => [
	[ '_firstname',		0, qr/^First Name$/ ],		 # see post_process_normalized
	[ '_lastname',		0, qr/^Last Name$/ ],		 # see post_process_normalized
	[ 'number',		0, qr/^Number$/ ],
    ]},
    website =>                  { textname => undef, type_out => 'login', fields => [
	[ 'url',		1, qr/^URL$/, ],
	[ 'username',		0, qr/^Login$/, ],
	[ 'password',		0, qr/^Password$/, ],
    ]},
);

$DB::single = 1;					# triggers breakpoint when debugging

my @today = Date::Calc::Today();			# for date comparisons

sub do_init {

    return {
	'specs'		=> \%card_field_specs,
	'imptypes'  	=> undef,
	'opts'		=> [],
    };
}

sub do_import {
    my ($file, $imptypes) = @_;
    my %Cards;

    {
	local $/ = undef;
	open my $fh, '<', $file or bail "Unable to open file: $file\n$!";
	$_ = <$fh>;
	close $fh;
    }

    my $n = 1;
    my ($npre_explode, $npost_explode);

    my $xp = XML::XPath->new(xml => $_);

    my $cardnodes = $xp->findnodes('//Card[@Caption] | //T4[@Caption]');
    foreach my $cardnode (@$cardnodes) {
	my (@card_tags, @groups);

	for (my $node = $cardnode->getParentNode(); $node->getName() =~ /^Folder|T3$/; $node = $node->getParentNode()) {
	    my $v = $node->getAttribute("Caption");
	    unshift @groups, $v   unless $v eq '';
	}
	if (@groups) {
	    push @card_tags, join '::', @groups;
	    debug 'Group: ', $card_tags[-1];
	}

	my (%c, @card_notes, @fieldlist);
	my $card_title = $xp->findvalue('@Caption', $cardnode)->value;
	debug "\tCard: ", $card_title;

	my $iconnum = $xp->findvalue('@Icon', $cardnode)->value;
	debug "\t\ticon # : ", $iconnum;

	my $fav = $xp->findvalue('@Favorite', $cardnode)->value;
	if ($fav eq 'true') {
	    debug "\t\tfavorite: true";
	    push @card_tags, 'Favorite'
	}

	if (my $fieldnodes = $xp->findnodes('*', $cardnode)) {
	    my $fieldindex = 1;;
	    foreach my $fieldnode (@$fieldnodes) {
		next if $fieldnode->getName() !~ /^Property|T\d+$/;
		# handle blank field labels;  type Note has none by default, but labels can be blanked by the user
		my $f = $fieldnode->getAttribute("Caption") || 'Field_' . $fieldindex;
		my $t = $fieldnode->getAttribute("Type") || $fieldnode->getName();
		my $v = $fieldnode->string_value;
		debug "\t\tfield: $f($t) -> $v";
		if ($t =~ /^Note|T267$/) {
		    if ($v ne '') {
			push @card_notes, $f eq 'Note' ? $v : join ': ', $f, $v;
		    }
		}
		else {
		    push @fieldlist, [ $f => $v ];			# maintain the field order, in case destination is notes
		    $fieldindex++;
		}
	    }
	}

	my $itype = find_card_type(\@fieldlist, $iconnum);

	# skip all types not specifically included in a supplied import types list
	next if defined $imptypes and (! exists $imptypes->{$itype});

	if ($itype eq 'address') {
	    my (%addr, @newfieldlist);
	    for (@fieldlist) {
		if ($_->[0] =~ /^City|State|Country|ZIP$/) {
		    $addr{lc $_->[0]} = $_->[1];
		}
		elsif ($_->[0] =~ /^Address #[123]$/) {
		    $addr{'street'} = myjoin ', ', $addr{'street'}, $_->[1];
		}
		else {
		    push @newfieldlist, $_;
		}
	    }
	    @fieldlist = @newfieldlist;
	    push @fieldlist, [ 'address' => \%addr ]		if keys %addr;
	}

	# From the card input, place it in the converter-normal format.
	# The card input will have matched fields removed, leaving only unmatched input to be processed later.
	my $normalized = normalize_card_data($itype, \@fieldlist, $card_title, \@card_tags, \@card_notes, \@groups, \&post_process_normalized);

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

    $n--;
    verbose "Imported $n card", pluralize($n) ,
	$npre_explode ? " ($npre_explode card" . pluralize($npre_explode) .  " expanded to $npost_explode cards)" : "";
    return \%Cards;
}

sub do_export {
    add_new_field('bankacct',       '_branchNumber',	$Utils::PIF::sn_branchInfo,	$Utils::PIF::k_string,    'branch number');
    add_new_field('bankacct',       '_bankNumber',	$Utils::PIF::sn_branchInfo,	$Utils::PIF::k_string,    'bank number');

    add_new_field('driverslicense', 'issued_on',	$Utils::PIF::sn_main,		$Utils::PIF::k_monthYear, 'issue date');

    add_new_field('membership',     'polid',		$Utils::PIF::sn_main,		$Utils::PIF::k_string,    'policy ID');
    add_new_field('membership',     'grpid',		$Utils::PIF::sn_main,		$Utils::PIF::k_string,    'group ID');
    add_new_field('membership',     'plan',		$Utils::PIF::sn_main,		$Utils::PIF::k_string,    'plan');
    add_new_field('membership',     'sponsor',		$Utils::PIF::sn_main,		$Utils::PIF::k_string,    'sponsor');
    add_new_field('membership',     'poltype',		$Utils::PIF::sn_main,		$Utils::PIF::k_string,    'policy type');

    add_new_field('email',	    'ispemail',		$Utils::PIF::sn_main,		$Utils::PIF::k_string,    'email');
    add_new_field('email',	    'isplogin',		$Utils::PIF::sn_main,		$Utils::PIF::k_string,    'isp login');
    add_new_field('email',	    'isppassword',	$Utils::PIF::sn_main,		$Utils::PIF::k_concealed, 'isp password');

    create_pif_file(@_);
}

sub find_card_type {
    my $fieldlist = shift;
    my $iconnum = shift;
    my $type = 'note';

    for $type (sort by_test_order keys %card_field_specs) {
	for my $def (@{$card_field_specs{$type}{'fields'}}) {
	    next unless $def->[1] and defined $def->[2];
	    for (@$fieldlist) {
		# type hint
		if ($_->[0] =~ $def->[2]) {
		    debug "\t\ttype detected as '$type' (key='$_->[0]')";
		    return $type;
		}
	    }
	}
    }

    if (grep($_->[0] =~ /^Company|Policy #|Type$/, @$fieldlist) >= 2) {
	debug "\t\ttype detected as 'insurance'";
	return 'insurance';
    }

    # socialsecurity fields are ambiguous with those of passport
    if (grep($_->[0] =~ /^First Name|Last Name|Number$/, @$fieldlist) == 3 and
        ! grep($_->[0] =~ /^Type|Authority|Issued|Expires|Place$/, @$fieldlist)) {
	debug "\t\ttype detected as 'socialsecurity'";
	return 'socialsecurity';
    }

    $type = grep($_->[0] eq 'Password', @$fieldlist) ? 'login' : 'note';

    debug "\t\ttype defaulting to '$type'";
    return $type;
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
	notes	=> $notesref,
	tags	=> $tags,
	folder	=> $folder,
    );

    for my $def (@{$card_field_specs{$type}{'fields'}}) {
	my $h = {};
	for (my $i = 0; $i < @$fieldlist; $i++) {
	    my ($inkey, $value) = @{$fieldlist->[$i]};
	    next if not defined $value or $value eq '';

	    if (!defined $def->[2] or $inkey =~ $def->[2]) {
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
    for (@$fieldlist) {
	next if $_->[1] eq '';
	push @{$norm_cards{'notes'}}, join ': ', @$_;
    }

    $postprocess and ($postprocess)->($type, \%norm_cards);
    return \%norm_cards;
}

# special fix up function for certain type fields
sub post_process_normalized {
    my ($type, $norm_cards) = @_;

    sub join_firstlast {
	my ($outkey, $type, $norm_cards) = @_;

	my (@l, $first, $last);
	$first = $l[0]	if @l = grep { '_firstname' eq $_->{'outkey'} } @{$norm_cards->{'fields'}};
	$last  = $l[0]	if @l = grep { '_lastname'  eq $_->{'outkey'} } @{$norm_cards->{'fields'}};
	if ($first or $last) {
	    my %h = (
		inkey	  => myjoin(' + ', $first->{'inkey'}, $last->{'inkey'}),
		valueorig => 'N/A',
		value	  => myjoin(' ',   $first->{'value'}, $last->{'value'}),
		outkey	  => $outkey,
		outtype	  => $type,
		keep	  => 0,
	    );

	    push @{$norm_cards->{'fields'}}, \%h;
	}
    }

    if ($type eq 'creditcard') {
	join_firstlast('cardholder', $type, $norm_cards);
    }
    elsif ($type eq 'idcard') {
	join_firstlast('member_name', 'membership', $norm_cards);
    }
    elsif ($type eq 'passport') {
	join_firstlast('fullname', $type, $norm_cards);
    }
    elsif ($type eq 'socialsecurity') {
	join_firstlast('name', $type, $norm_cards);
    }
}

# sort logins as the last to check
sub by_test_order {
    return  1 if $a eq 'login';
    return -1 if $b eq 'login';
    $a cmp $b;
}

# Date converters
# Safewallet validates date input on Date types
#    SafeWallet 2:	 yyyy-mm-dd hh:mm:ss
#    SafeWallet 3:	 yyyymmddhhmmss
sub parse_date_string {
    local $_ = $_[0];
    my $when = $_[1] || 0;					# -1 = past only, 0 = assume this century, 1 = future only, 2 = 50-yr moving window

    if (/^(?<y>\d{4})-?(?<m>\d{2})-?(?<d>\d{2})(?:\s|\d)/) {	# yyyy-mm-dd or yyyymmdd
	my $m = sprintf "%02d", $+{'m'};
	my $d = sprintf "%02d", $+{'d'};
	if (check_date($+{'y'}, $m, $d)) {
	    return ($+{'y'}, $m, $d);
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
    return defined $y ? timelocal(0, 0, 0, $d, $m - 1, $y): $_[0];
}

1;
