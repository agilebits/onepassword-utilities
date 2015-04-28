# Handy Safe XML export converter
#
# Copyright 2014 Mike Cappella (mike@cappella.us)

package Converters::Handysafe 1.00;

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
    bankacct =>			{ textname => undef, fields => [
	[ 'bankName',		0, qr/\bBank\b/, ],
	[ 'accountNo',          1, qr/^Account$/, ],
	[ 'accountType',	0, qr/Type/, ],
	[ '_branchNumber',	1, qr/Branch number/, ],
	[ 'swift',		1, qr/SWIFT/, ],
	[ 'branchPhone',	0, qr/Phone/, ],
	[ '_other',		0, qr/Other/, ],
    ]},
    creditcard =>		{ textname => undef, fields => [
	[ 'bank',		0, qr/\bBank\b/, ],
	[ '_firstname',		0, qr/First name/, ],	# see post_process_normalized
	[ '_lastname',		0, qr/Last name/, ],	# see post_process_normalized
	[ 'ccnum',		0, qr/Card number/, ],
	[ 'pin',		0, qr/\bPIN\b/, ],
	[ 'cvv',		1, qr/CVC code/, ],
	[ 'expiry',		0, qr/Expires/,		{ func => sub { return date2monthYear($_[0], 2) }, keep => 1 } ],
	[ 'phoneTollFree',	1, qr/If lost, call/, ],
	[ 'type',		0, undef ],		# special case - will never match, used to set card type when possible
    ]},
    driverslicense =>           { textname => undef, icon => 8, fields => [
        [ 'state',      	0, qr/^Location/ ],
        [ 'number',             0, qr/^Number$/ ],
        [ '_drissued',          0, qr/^Issued/ ],
        [ 'expiry_date',        0, qr/^Expires/,	 { func => sub { return date2monthYear($_[0], 2) }, keep => 1 } ],
	[ '_other',		0, qr/Other/, ],
    ]},
    email =>			{ textname => undef, fields => [
        [ 'pop_username',      	0, qr/^Email|Login$/ ],
        [ 'pop_password',      	0, qr/^Password/ ],
        [ 'pop_server',      	1, qr/^POP3$/ ],
        [ 'smtp_server',      	1, qr/^SMTP$/ ],
	[ '_other',		0, qr/Other/, ],
    ]},
    lockcode =>                 { textname => undef, type_out => 'login', fields => [
        [ 'combolocation',      0, qr/^Location/ ],
        [ 'password',           1, qr/^Code$/ ],
        [ 'comboother',         0, qr/Other/ ],
    ]},
    login =>                    { textname => undef, fields => [
        [ 'username',           0, qr/^Login|Yahoo! ID|Live ID|Email|UIN$/, ],
        [ 'password',           0, qr/Password/, ],
        [ 'url',                1, qr/URL/, ],
        [ '_other',             0, qr/Other/, ],
    ]},
    membership =>               { textname => undef, fields => [
        [ 'org_name',           1, qr/^ID|Organization$/, ],
        [ 'phone',              0, qr/Phone/ ],
        [ '_firstname',         0, qr/First name/, ],	# see post_process_normalized
        [ '_lastname',          0, qr/Last name/, ],	# see post_process_normalized
        [ 'membership_no',      0, qr/ID/, ],
        [ 'expiry_date',        0, qr/Expires/,		{ func => sub { return date2monthYear($_[0], 2) }, keep => 1 } ],
        [ '_other',             0, qr/Other/ ],
    ]},
    passport =>                 { textname => undef, fields => [
        [ 'type',               0, qr/Type/, ],
        [ 'number',             0, qr/Number/, ],
        [ '_firstname',         0, qr/First name/, ],	# see post_process_normalized
        [ '_lastname',          0, qr/Last name/, ],	# see post_process_normalized
        [ 'sex',                0, qr/Sex/ ],
        [ 'birthdate',          0, qr/^Birth$/,		{ func => sub { return date2epoch($_[0], 2) } } ],
        [ 'birthplace',         1, qr/^Place$/, ],
        [ 'nationality',        1, qr/Nation/, ],
        [ 'issue_date',         0, qr/Issued/, 		{ func => sub { return date2epoch($_[0], 2) } } ],
        [ 'expiry_date',        0, qr/Expires/, 	{ func => sub { return date2epoch($_[0], 2) } } ],
        [ 'type',               1, qr/Authority/, ],
    ]},
    password =>                 { textname => undef, type_out => 'server', fields => [
        [ 'username',           0, qr/Login/, ],
        [ 'password',           0, qr/Password/, ],
        [ '_access',            1, qr/Access/, ],
        [ '_other',             0, qr/Other/, ],
    ]},
    wireless =>                { textname => undef, fields => [
        [ '_access',           0, qr/Access/, ],
        [ 'wireless_password', 0, qr/Password/, ],
        [ 'network_name',      1, qr/^SSID$/, ],
        [ '_ip',               1, qr/^IP$/, ],
        [ '_dns',              0, qr/^DNS$/, ],
        [ '_other',            0, qr/Other/, ],
    ]},
);

$DB::single = 1;					# triggers breakpoint when debugging

my @today = Date::Calc::Today();			# for date comparisons

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
    my $groupnodes = $xp->find('//Folder[@name]');

    foreach my $groupnode ($groupnodes->get_nodelist) {
	my (@groups, $card_tags);
	for (my $node = $groupnode; my $parent = $node->getParentNode(); $node = $parent) {
	    my $v = $xp->findvalue('@name', $node)->value();
	    unshift @groups, $v   unless $v eq '';
	}
	$card_tags = join '::', @groups;
	debug 'Group: ', $card_tags;

	my $cardnodes = $xp->findnodes('Card[@name]', $groupnode);
	foreach my $cardnode (@$cardnodes) {
	    my (%c, $card_notes, @fieldlist);
	    my $card_title = $xp->findvalue('@name', $cardnode)->value;
	    debug "\tCard: ", $card_title;

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
		# XXX should be only one note entry
		warn "Multiple notes entries(card '$card_title') - please report"	if defined $card_notes;
		if ($notenode->string_value ne '') {
		    $card_notes = $notenode->string_value;
		    debug "\t\tnote: ", $card_notes;
		}
	    }

	    my $itype = find_card_type(\@fieldlist, $iconnum);

	    # skip all types not specifically included in a supplied import types list
	    next if defined $imptypes and (! exists $imptypes->{$itype});

	    # special case: set a credit cards 'type' from the icon number if possible
	    if ($itype eq 'creditcard') {
		push @fieldlist, [ type => $icons{$iconnum} ]		if exists $icons{$iconnum};
	    }

	    # From the card input, place it in the converter-normal format.
	    # The card input will have matched fields removed, leaving only unmatched input to be processed later.
	    my $normalized = normalize_card_data($itype, \@fieldlist, $card_title, $card_tags, \$card_notes, \@groups, \&post_process_normalized);

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
    }

    $n--;
    verbose "Imported $n card", pluralize($n) ,
	$npre_explode ? " ($npre_explode card" . pluralize($npre_explode) .  " expanded to $npost_explode cards)" : "";
    return \%Cards;
}

sub do_export {
    add_new_field('bankacct',     '_branchNumber',	$Utils::PIF::sn_branchInfo,	$Utils::PIF::k_string,    'branch number');

    create_pif_file(@_);
}

sub find_card_type {
    my $fieldlist = shift;
    my $iconnum = shift;
    my $type;

    for $type (sort by_test_order keys %card_field_specs) {
	for my $def (@{$card_field_specs{$type}{'fields'}}) {
	    next unless $def->[1] and defined $def->[2];
	    for (@$fieldlist) {
		# type hint
		if ($_->[0] =~ $def->[2]) {
		    debug "type detected as '$type' (key='$_->[0]')";
		    return $type;
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
	notes	=> $$notesref,
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
    $norm_cards{'notes'} .= "\n"	if defined $norm_cards{'notes'} and length $norm_cards{'notes'} > 0 and @$fieldlist;
    for (@$fieldlist) {
	next if $_->[1] eq '';
	$norm_cards{'notes'} .= "\n"	if defined $norm_cards{'notes'} and length $norm_cards{'notes'} > 0;
	$norm_cards{'notes'} .= join ': ', @$_;
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
    elsif ($type eq 'membership') {
	join_firstlast('member_name', $type, $norm_cards);
    }
    elsif ($type eq 'passport') {
	join_firstlast('fullname', $type, $norm_cards);
    }
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
    return defined $y ? timelocal(0, 0, 0, $d, $m - 1, $y): $_[0];
}

1;
