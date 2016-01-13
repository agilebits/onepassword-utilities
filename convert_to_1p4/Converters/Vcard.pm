# Apple Contacts's vCard export converter
#
# Copyright 2015 Mike Cappella (mike@cappella.us)

package Converters::Vcard 1.01;

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

use Time::Local qw(timelocal);
use Time::Piece;
use Text::vFile::asData;
use MIME::Base64;

# properties to be ignored
my @ignored = qw/UID X-ABUID MAILER PROFILE CLASS X-ACTIVITY-ALERT/;

my %card_field_specs = (
    vcard =>			{ textname => '', type_out => 'identity', fields => [
	[ 'firstname',		0, qr/^First Name$/, ],
	[ 'lastname',		0, qr/^Last Name$/, ],
	[ '_nickname',		0, qr/^NICKNAME$/, ],
	[ 'address',		0, qr/^ADR$/,		{ func => \&convert_address } ],
	[ 'birthdate',		0, qr/^Birthday$/,	{ func => \&date2epoch } ],
	[ 'company',		0, qr/^ORG$/, 		{ func => sub { 1; return (split(/;/, $_[0]))[0] } } ],
	[ '_title',		0, qr/^TITLE$/, ],
	[ 'defphone',		0, qr/^TEL$/, ],
	[ 'homephone',		0, qr/^TEL HOME$/, ],
	[ 'cellphone',		0, qr/^TEL CELL$/, ],
	[ 'busphone',		0, qr/^TEL WORK$/, ],
	[ 'email',		0, qr/^EMAIL$/, ],
	[ 'website',		0, qr/^URL$/, ],
	[ 'icq',		0, qr/^X-ICQ$/, ],
	[ 'skype',		0, qr/^Skype$/, ],
	[ 'aim',		0, qr/^AIM$/, ],
	[ 'yahoo',		0, qr/^YAHOO$/, ],
	[ 'msn',		0, qr/^MSN$/, ],
    ]},
    # allows for placing vCard contact data into Secure Notes instead of Identity
    note =>			{ textname => '', fields => [
	[ 'firstname',		0, qr/^First Name$/,	{ custfield => clone_pif_field('identity','firstname') } ],
	[ 'lastname',		0, qr/^Last Name$/,	{ custfield => clone_pif_field('identity','lastname') } ],
	[ '_nickname',		0, qr/^NICKNAME$/, 	{ custfield => [ $Utils::PIF::sn_identity, $Utils::PIF::k_string, 'nickname' ] } ],
	[ 'address',		0, qr/^ADR$/,		{ custfield => clone_pif_field('identity','address'),   func => \&convert_address } ],
	[ 'birthdate',		0, qr/^Birthday$/,	{ custfield => clone_pif_field('identity','birthdate'), func => \&date2epoch } ],
	[ 'company',		0, qr/^ORG$/, 		{ custfield => clone_pif_field('identity','company'),   func => sub { 1; return (split(/;/, $_[0]))[0] } } ],
	[ '_title',		0, qr/^TITLE$/, 	{ custfield => [ $Utils::PIF::sn_identity, $Utils::PIF::k_string, 'title' ] } ],
	[ 'defphone',		0, qr/^TEL$/, 		{ custfield => clone_pif_field('identity','defphone') } ],
	[ 'homephone',		0, qr/^TEL HOME$/,	{ custfield => clone_pif_field('identity','homephone') } ],
	[ 'cellphone',		0, qr/^TEL CELL$/,	{ custfield => clone_pif_field('identity','cellphone') } ],
	[ 'busphone',		0, qr/^TEL WORK$/,	{ custfield => clone_pif_field('identity','busphone') } ],
	[ 'email',		0, qr/^EMAIL$/,		{ custfield => clone_pif_field('identity','email') } ],
	[ 'website',		0, qr/^URL$/,		{ custfield => clone_pif_field('identity','website') } ],
	[ 'icq',		0, qr/^X-ICQ$/,		{ custfield => clone_pif_field('identity','icq') } ],
	[ 'skype',		0, qr/^Skype$/,		{ custfield => clone_pif_field('identity','skype') } ],
	[ 'aim',		0, qr/^AIM$/,		{ custfield => clone_pif_field('identity','aim') } ],
	[ 'yahoo',		0, qr/^YAHOO$/,		{ custfield => clone_pif_field('identity','yahoo') } ],
	[ 'msn',		0, qr/^MSN$/,		{ custfield => clone_pif_field('identity','msn') } ],
    ]},
);

$DB::single = 1;					# triggers breakpoint when debugging

sub do_init {
    return {
	'specs'		=> \%card_field_specs,
	'imptypes'  	=> undef,
	'opts'		=> [],
	'opts'		=> [ [ q{      --icon               # import vCard icons },
			       'icon' ],
			     [ q{-m or --modified           # set item's last modified date },
			       'modified|m' ],
			     [ q{      --securenote         # place vCard data into a Secure Note instead of Idenity},
			       'securenote' ],
			   ],
    }
}

sub do_import {
    my ($file, $imptypes) = @_;

    open my $io, "<:encoding(utf8)", $file
	or bail "Unable to open vCard file: $file\n$!";

    my $asData = Text::vFile::asData->new;
    $asData->preserve_params(1);
    my $vdata = $asData->parse($io);
    close($io);

    my %Cards;
    my $n = 1;

    my $i;
    for my $vcard (@{$vdata->{'objects'}}) {
	debug '*** ENTRY ', $i++;
	my $itype = lc $vcard->{'type'};
	if ($itype ne 'vcard') {
	    say "Skipping non-VCARD type: ", $vcard->{'type'};
	    next;
	}

	# When the 'securenote' option is set, data goes into Secure Notes.
	$itype = 'note'		if exists $main::opts{'securenote'};

	next if defined $imptypes and (! exists $imptypes->{$itype});

	my (%cmeta, @fieldlist, $v, $l);

	my $p = $vcard->{'properties'};
	
	delete $p->{$_}		for @ignored;				# delete any properties on the ignored list

	# Simplify the returned data structure by flattening unnecessary levels and decoding
	# some value escapes.
	for my $key (sort keys %$p) {
	    if (@{$p->{$key}} == 1 and !exists $p->{$key}[0]{'param'}) {
		$p->{$key} = $p->{$key}[0]{'value'};
		$p->{$key} =~ s/^_\$!<(.+)>!\$_/$1/;
		$p->{$key} =~ s/\\,/,/g;
		$p->{$key} =~ s/\\n/\n/g	if $key eq 'NOTE';	# lines separated by two char sequence '\' 'n' 
		next;
	    }
	    for (@{$p->{$key}}) {
		if (! exists $_->{'param'}) {
		    next;
		}
		delete $_->{'param'};
		for my $param (@{$_->{'params'}}) {
		    for my $pkey (keys %{$param}) {
			push @{$_->{'_params'}{$pkey}}, $param->{$pkey};
		    }
		}
		delete $_->{'params'};
	    }
	}

	# Handle the vCard groups ('group'.'name'; i.e. 'item1.EMAIL' and 'item1.X-ABLabel').
	# Hash by 'group' and then by 'name' keys.
	my %groups;
	map { my @x = split /\./; $groups{$x[0]}{$x[1]}++ } grep { /^[-a-z\d]+\.[-a-z\d]+/i } keys %$p;
	for my $g (sort keys %groups) {
	    my ($oname, $olabel, $type);

	    $type = (split /\./, (grep {!/\.(?:X-ABLabel|X-ABADR)$/i} grep {/^$g\.[-a-zA-Z\d]+/ } keys %$p)[0])[1];
	    bail "Unexpected handing of group '$g' in vcard"	unless exists $groups{$g}{$type};

	    $oname  = join '.', $g, $type;
	    my @labels = grep { $_ ne $type } keys %{$groups{$g}};
	    if (@labels == 1) {
		$olabel = join '.', $g, $labels[0];
	    }
	    else {
		$olabel = join('.', $g, grep(/^X-ABLabel$/, @labels) ? 'X-ABLabel' : join(' ', @labels))
	    }

	    if (ref($p->{$oname}) eq 'ARRAY') {
		bail "Unepexcted quantity in group entry '$g': please report" if @{$p->{$oname}} > 1;
		$p->{$oname}[0]{'label'} = $p->{$olabel};
		push @{$p->{$type}}, $p->{$oname}[0];
	    }
	    else {
		my $val = $p->{$oname};
		$p->{$oname} = { value => $val, label => $p->{$olabel} };
		push @{$p->{$type}}, $p->{$oname};
	    }
	    for my $k (keys %{$groups{$g}}) {
		delete $p->{join '.', $g, $k};
	    }
	}


	if (($v = get_prop_value($p, 'VERSION')) ne '3.0') {
	    say "Skipping unsupported VCARD version: ", $v;
	    next;
	}
	if (($v = get_prop_value($p, 'PRODID')) !~ m(//Apple Inc\.//)) {
	    say "Skipping unsupported VCARD implementation: ", $v;
	    next;
	}

	# Grab the standard items: title, notes
	$cmeta{'title'} = get_prop_value($p, 'FN') // 'Unnamed';		# FN: Full Name
	$cmeta{'notes'} = get_prop_value($p, 'NOTE');

	# Grab the image, and use it if --icon is enabled (and a required graphics library is available).
	if ($v = get_prop_value($p, 'PHOTO')) {
	    if ($main::opts{'icon'}) {
		$cmeta{'icon'} = prepare_icon($v->{'type'}{'TYPE'}[0], decode_base64($v->{'value'}));
	    }
	}

	for my $prop (sort keys %$p) {
	    debug "Property: $prop";
	    if ($prop =~ /^(?:BDAY|ORG|N|NICKNAME|TITLE|X-MS-TEL)$/) {					# get simple items
		if ($v = get_prop_value($p, $prop)) {
		    if ($prop eq 'N') {
			my @data = split(/;/, $v);
			push @fieldlist, [ 'Last Name' => shift @data ];
			push @fieldlist, [ 'First Name' => join ' ', @data ];
		    }
		    else {
			if ($prop eq 'BDAY') {
			    $prop = 'Birthday';
			    if (ref $v eq 'HASH') {
				my $vv = $v->{'value'};
				# When date has no year value, Apple sets the year to 1604 and adds the attribute X-APPLE-OMIT-YEAR
				$vv =~ s/^\d{4}-//		if exists $v->{'type'}{'X-APPLE-OMIT-YEAR'};
				$v = $vv;
			    }
			}
			push @fieldlist, [ $prop => $v ];
		    }
		}
	    }

	    elsif ($prop =~ /^(?:X-(YAHOO|AIM|MSN))$/) {
		my $propname = $1;;
		if ($v = get_prop_value($p, $prop, 'type=pref')) {
		    push @fieldlist, [ $propname => $v->{'value'} ];
		}
		while (exists $p->{$prop}) {
		    if ($v = get_prop_value($p, $prop)) {
			$l = lc sprintf "%s(%s)", $propname, myjoin(' ', $v->{'label'}, $v->{'type'}{'type'}->[0]);
			push @fieldlist, [ $l => $v->{'value'} ];
		    }
		}
	    }

	    elsif ($prop eq 'ADR') {
		if ($v = get_prop_value($p, $prop, 'type=pref')) {		# get preferred items
		    push @fieldlist, [ $prop => $v->{'value'} ];
		}
		while (exists $p->{$prop}) {
		    if ($v = get_prop_value($p, $prop)) {
			$l = lc sprintf "address(%s)", $v->{'type'} ? join(' ', @{$v->{'type'}{'type'}}) : $v->{'label'};
			$v->{'value'} =~ s/^;+//;
			push @fieldlist, [ $l => $v->{'value'} ];
		    }
		}
	    }

	    elsif ($prop eq 'EMAIL') {
		if ($v = get_prop_value($p, $prop, 'type=pref')) {		# get preferred items
		    push @fieldlist, [ $prop => $v->{'value'} ];
		}
		while (exists $p->{$prop}) {
		    if ($v = get_prop_value($p, $prop, 'type=*')) {
			$l = lc sprintf "%s(%s)", $prop, $v->{'label'} // join(' ', grep(!/^INTERNET$/, @{$v->{'type'}}));
			push @fieldlist, [ $l => $v->{'value'} ];
		    }
		}
	    }

	    elsif ($prop eq 'TEL') {
		if ($v = get_prop_value($p, $prop, 'type=pref')) {		# get preferred items
		    push @fieldlist, [ $prop => $v->{'value'} ];
		}
		# get specific phone items
		for (qw/HOME WORK CELL/) {
		    if ($v = get_prop_value($p, $prop, "type=$_")) {
			push @fieldlist, [ "$prop $_" => $v->{'value'} ];
		    }
		}
		while (exists $p->{$prop}) {
		    if ($v = get_prop_value($p, $prop, 'type=*')) {
			$l = lc sprintf "%s(%s)", $prop, $v->{'label'} // join(' ', grep(!/^VOICE$/, @{$v->{'type'}}));
			push @fieldlist, [ $l => $v->{'value'} ];
		    }
		}
	    }

	    elsif ($prop eq 'X-SOCIALPROFILE') {
		while (exists $p->{$prop}) {
		    if ($v = get_prop_value($p, $prop)) {
			$l = lc myjoin(' ', @{$v->{'type'}{'type'}}, $v->{'label'} // '');
			my $v = exists $v->{'type'}{'x-user'} ? join(' ', @{$v->{'type'}{'x-user'}}) : $v->{'value'};
			push @fieldlist, [ $l => $v ];
		    }
		}
	    }

	    elsif ($prop eq 'X-ABRELATEDNAMES') {
		while (exists $p->{$prop}) {
		    if ($v = get_prop_value($p, $prop)) {
			$l = lc sprintf "%s(%s)", 'relationship', $v->{'label'};
			push @fieldlist, [ $l => $v->{'value'} ];
		    }
		}
	    }

	    elsif ($prop eq 'X-ICQ') {
		if ($v = get_prop_value($p, $prop, 'type=pref')) {		# get preferred items
		    push @fieldlist, [ $prop => $v->{'value'} ];
		}
		while (exists $p->{$prop}) {
		    if ($v = get_prop_value($p, $prop)) {
			$l = lc sprintf "%s(%s)", 'icq', $v->{'label'};
			push @fieldlist, [ $l => $v->{'value'} ];
		    }
		}
	    }

	    elsif ($prop eq 'IMPP') {
		while (exists $p->{$prop}) {
		    if ($v = get_prop_value($p, $prop)) {
			$l = lc sprintf "%s(%s)", 'messaging', myjoin(' ', $v->{'label'}, ($v->{'type'}{'X-SERVICE-TYPE'} // $v->{'type'}{'type'})->[0]);
			push @fieldlist, [ $l => $v->{'value'} =~ s/^[^:]+://r ];
		    }
		}
	    }
	    elsif ($prop eq 'X-ABDATE') {
		while (exists $p->{$prop}) {
		    if ($v = get_prop_value($p, $prop)) {
			$l = lc sprintf "%s(%s)", 'date', $v->{'label'};
			push @fieldlist, [ $l, $v->{'value'} ];
		    }
		}
	    }
	    elsif ($prop eq 'URL') {
		if ($v = get_prop_value($p, $prop, 'type=pref')) {		# get preferred items
		    push @fieldlist, [ $prop => $v->{'value'} ];
		}
		while (exists $p->{$prop}) {
		    if ($v = get_prop_value($p, $prop)) {
			$l = lc sprintf "%s(%s)", 'website', $v->{'label'} // join(' ', @{$v->{'type'}{'type'}});
			push @fieldlist, [ $l, $v->{'value'} ];
		    }
		}
	    }
	    elsif ($prop eq 'X-ABShowAs') {
		push @{$cmeta{'tags'}}, get_prop_value($p, 'X-ABShowAs');
	    }

	    elsif ($prop eq 'REV') {
		if ($v = get_prop_value($p, $prop)) {
		    if ($main::opts{'modified'} and my $epoch = date2epoch($v)) {
			$cmeta{'modified'} = $epoch;
		    }
		    else {
			push @fieldlist, [ 'Last Modified' => revdate2str($v) ];
		    }
		}
	    }

	    else {
		debug "PROP catchall: $prop";
		while (exists $p->{$prop}) {
		    $l = $prop;
		    $v = get_prop_value($p, $prop);
		    $DB::single = 1;
		    if (ref $v eq 'HASH') {
			$l = sprintf "%s(%s)", $prop, $v->{'label'}	 if $v->{'label'};
			$v = $v->{'value'};
		    }
		    push @fieldlist, [ $l => $v ];
		}
		#die "Unexpected property '$prop'";
	    }
	}

	my $normalized = normalize_card_data(\%card_field_specs, $itype, \@fieldlist, \%cmeta);

	if (scalar %$p) {
	    $DB::single = 1;					# triggers breakpoint when debugging
	    die "UNHANDLED STUFF in $p";
	    # map remaining vcard data to notes
	    #$normalized->{'notes'} .= "\n\n" . $vcard	if defined $normalized->{'notes'} and length $normalized->{'notes'}
	}

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

sub get_prop_value {
    my ($p, $key, $param) = @_;

    return undef unless exists $p->{$key};

    my ($i, $ret) = (0, undef);
    if (not defined $param) {
	if (ref $p->{$key} eq 'ARRAY') {
	    my $pp = $p->{$key}[$i];
	    $ret = { 
		label => $pp->{'label'} // undef,
		value => $pp->{'value'},
		type  => $pp->{'_params'},
	    };
	}
	else {
	    return delete $p->{$key}	 if ref $p->{$key} eq '';
	}
    }
    else {
	my ($pkey, $pvalue) = split /=/, $param		if defined $param;
	for ($i = 0; $i < @{$p->{$key}}; $i++) {
	    my $pp = $p->{$key}[$i];
	    if (exists $pp->{'_params'}{$pkey}) {
		if ($pvalue eq '*' or grep { $_ eq $pvalue } @{$pp->{'_params'}{$pkey}}) {
		    $ret = { 
			label => $pp->{'label'} // undef,
			value => $pp->{'value'},
			type  => $pp->{'_params'}{$pkey},
		    };
		    last;
		}
	    }
	    else {
		if ($pvalue eq '*') {		# accept 'label' as a 'type' when there are no 'type' params
		    $ret = { 
			label => $pp->{'label'},
			value => $pp->{'value'},
		    };
		    last;
		}
	    }
	}
    }

    if ($ret) {
	splice @{$p->{$key}}, $i, 1;
	delete $p->{$key} 	if @{$p->{$key}} == 0;
    }

    return $ret;
}

sub convert_address {
    my @data = split /;/, $_[0];
    # data[0] : post office box
    # data[1] : the extended address;
    return {
	street  => $data[2],
	city    => $data[3],
	state   => $data[4],
	zip     => $data[5],
	country => $data[6]
    };
}

sub clean_svc_types {
    local $_ = shift;
    return myjoin ' ', split /;?type=/, lc $_;
}

sub clean_phone_types {
    local $_ = shift;

    my @typelist;
    for (split /;?type=/, $_) {
	next if $_ eq '';
	if ($_ eq 'VOICE') {
	    unshift @typelist, 'phone';
	}
	elsif ($_ =~ /^PAGER|FAX$/) {
	    unshift @typelist, lc $_;
	}
	else {
	    push @typelist, lc $_;
	}
    }

    return join ' ', @typelist;
}

# sort logins as the last to check
sub by_test_order {
    return  1 if $a eq 'login';
    return -1 if $b eq 'login';
    $a cmp $b;
}

# sort field data, moving Date Created and Date Modified to the end of the list
sub by_field_name {
    return  1 if $a eq 'Date Modified';
    return -1 if $b eq 'Date Modified';
    return  1 if $a eq 'Date Created';
    return -1 if $b eq 'Date Created';
    $a cmp $b;
}

# Date converters
# BDAY: 		yyyy-mm-dd
# REV:    		yyyy-mm-ddThh:mm:sss
sub parse_date_string {
    local $_ = $_[0];
    my $when = $_[1] || 0;					# -1 = past only, 0 = assume this century, 1 = future only, 2 = 50-yr moving window

    if (/^(\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}:\d{2}Z)?)$/) {
	my $str = $1;
	$str .= 'T03:00:00Z'	 if not defined $2;
	if (my $t = Time::Piece->strptime($str, "%Y-%m-%dT%H:%M:%SZ")) {
	    return $t;
	}
    }

    return undef;
}

sub date2epoch {
    my $t = parse_date_string @_;
    return undef if not defined $t;
    return defined $t->year ? 0 + timelocal($t->sec, $t->minute, $t->hour, $t->mday, $t->mon - 1, $t->year): $_[0];
}

sub revdate2str {
    my $t = parse_date_string @_;
    return undef if not defined $t;
    return $t->strftime;
}

1;
