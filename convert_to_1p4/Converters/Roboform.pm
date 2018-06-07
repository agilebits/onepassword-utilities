# RoboForm 6.xx HTML export converter
#
# Copyright 2015 Mike Cappella (mike@cappella.us)

package Converters::Roboform 1.01;

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

use HTML::Entities;

# Roboform does not use standardized Username and Password fields - rather, it uses the names of the
# fields in the HTML form data for the web page login, and those strings get stored in the exported
# HTML.  The tables below are used to define the regular expression patterns to match Usernames and
# Passwords.  If you find you have unmatched Usernames or Passwords in your Login entries, you can add
# new entries to the appropriate tables below.  You'll notice any such unmatched # key / value pairs
# in the Notes section of the entry, or as custom fields if you are using the option --addfields.
#
# Add new patterns to the relevant tables below - these are regular expressions, and will automatically
# be created as fully anchored patterns (beginning and end) of the string.  Place more specific entries
# at the top of the tables (to be tried first) and less specific entries later. This helps provide the
# best match opportunities.  The patterns below have been developed empirically over time, as reported
# by users.
# 
# Note: the pattern matcher will reject username tokens with a variant of 'password' in them, to avoid
# the situation where, for example, 'login_password' when matched as a username (the 'login' term could
# match a username, but 'password' suggests its a password).

# Username and Password regular expression patterns tables.
my %userpass_REs = (
    username_reject => [
	qr/autologin/i,
	qr/passwo?r?d/i,
    ],
    username => [
	qr/^(?:user|login)(?:[-_\s]*(?:name|id))$/i,
	qr/^webusername$/i,
	qr/.*_login_username$/i,
	qr/^login(?:name|user)[-_]?id$/i,
	qr/^user_?name_\w+/i,
	qr/^\w+_?user_?name$/i,
	qr/^user$/i,
	qr/^txtuserid$/i,
	qr/^txtuser$/i,
	qr/^login$/i,
	qr/^[-_\w]*log[oi]nid$/i,
	qr/^loginuser$/i,
	qr/^login-user-name$/i,
	qr/^\w+[-_]?login$/i,
	qr/^\w+-login-id$/i,
	qr/^loginInput$/i,
	qr/^user-field$/i,
	qr/^\w+_usernamefrm$/i,
	qr/^usr_name_home$/i,
	qr/^login-(appleid|account)$/i,
	qr/^appleid$/i,
	qr/^login_field$/i,
	qr/^onlineid\d$/i,
	qr/^txtloginname$/i,
	qr/^(signinemailaddress|emailaddress)$/i,
	qr/^(?:user|login)[-_]?email$/i,
	qr/^login-email-address$/i,
	qr/^inputemailhandle$/i,
	qr/^adslaccount$/i,
	qr/^\w*email[-_](?:\w+)$/i,
	qr/^[-_\w-]*email(?:[-_]?id)?$/i,
	qr/^e?mail$/i,
	qr/^pwuser$/i,
	qr/^uid$/i,
	qr/^\w+_uid$/i,
	qr/^loginquestion\w*$/i,
	qr/^clientpin$/i,
	qr/^\w*accountname$/i,
	qr/^[-_\w]*userid[-_\w]*$/i,
	qr/^wireless_num$/i,
	qr/^membernametext$/i,
	qr/^\w*username[-_\w]*$/i,
	qr/^txtlogin$/i,
	qr/^name$/i,
	qr/^usernm$/i,
	qr/^log$/i,
	qr/^\w+_uname$/i,
	qr/^[-_\w]*login-name[-_\w]*$/i,
	qr/^address$/i,
	qr/^memberid$/i,
	qr/^[-_\w]*accountnumber$/i,
	qr/^inusid$/i,
	qr/^handle$/i,
	qr/^\w*identifier$/i,
	qr/use?r_name/i,
	qr/loginemail/i,
	qr/signinid/i,
	qr/logincontrol/i,
	qr/^(?:usr|id|ns|ui|u)$/i,
    ],
    password_reject => [
	qr/_hint$/i,
    ],
    password => [
	qr/^passwo?r?d$/i,
	qr/.*login[-_]password$/i,
	qr/^loginpassword$/i,
	qr/^webupassword$/i,
	qr/^loginpwd?$/i,
	qr/^passwd_login?$/i,
	qr/^userpwd$/i,
	qr/^pwpwd$/i,
	qr/^txtpwd$/i,
	qr/^\w+-logon-password$/i,
	qr/^passwordInput$/i,
	qr/^(?:user|login)[-_]?pass$/i,
	qr/^\w*loginpwd$/i,
	qr/^(?:pass|txtpass|pword|pswd|pwd)$/i,
	qr/^(?:log|u)pass$/i,
	qr/password[_]?\w+/i,
	qr/^[-_\w-]*password$/i,
	qr/^password-field$/i,
	qr/^\w+_password$/i,
	qr/^usr_password_home$/i,
	qr/^\w+_passwordfrm$/i,
	qr/^passcode\d$/i,
	qr/^adslpw$/i,
	qr/^clientpw$/i,
	qr/^\w*accountpw$/i,
	qr/^[-_\w]*password[-_\w]*$/i,
	qr/^\w+_psd$/i,
	qr/^inpswd$/i,
	qr/^\w*userpwd$/i,
	qr/^[-_\w]*txtpin$/i,
	qr/pass_word/i,
	qr/^(?:pw|ps|up|p)$/i,
    ],
);

=cut
=cut

# Language-specificmy strings, as found in the HTML
my %category_strings = (
    logins => [
	'Rob&shy;oForm Logins List',			# English
	'Liste der Rob&shy;oForm-An&shy;meldungen',	# German
	'Rob&shy;oForm - Loginy',			# Polish

    ],
    safenotes => [
	'Rob&shy;oForm Saf&shy;enotes List',		# English
    ],
    identities => [
	'Rob&shy;oForm Ide&shy;ntities List',		# English
    ],
);

=cut
 consider how to handle these.

_fieldformat$1#j_username##textfield-1015-inputEl:
_fieldformat$1#j_password##textfield-1016-inputEl:

_fieldformat$1#loginfmt##i0116:
_fieldformat$1#passwd##i0118:

 _fieldformat$1#login##i0116:
_fieldformat$1#passwd##i0118:

 _fieldformat$1#email##field:
_fieldformat$1#password##field:

 _fieldformat$1#loginname##text1:
_fieldformat$1#loginpassword##text2:
=cut

sub userpass_matcher {
    my ($kvpair, $key) = @_;

    my $key_reject = $key . '_reject';

    if ($key eq 'password' or $key eq 'username') {
	my $token = $kvpair->[0];

	# when the HTML contains fields named such as loginform[usernameemail], pull out the inner component
	if ($token =~ /^[^[]+\[([^]]+)\]$/) {
	    $token = $1;
	}
	# otherwise, split the components and use the last on
	else {
	    $token = (split /[#.:\$]/, $token)[-1];
	}

	debug "   attempting to match field token '$token' as a $key";
	if ($token =~ /^\[[^\]]+\]$/) {
	    debug "      rejecting bracketed token '$token' as a $key";
	    return ();
	}
	if ($kvpair->[1] eq '*') {
	    debug "      rejecting token '$token' as a $key because its value is '*'";
	    return ();
	}
	if ($kvpair->[1] =~ /^([01])$/) {
	    debug "      rejecting token '$token' as a $key because its value is '$1'";
	    return ();
	}

	# rejection tests first
	for (my $i = 0; $i < @{$userpass_REs{$key_reject}}; $i++) {
	    debug "        $i: pattern reject test: $userpass_REs{$key_reject}[$i]";
	    if ($token =~ $userpass_REs{$key_reject}[$i]) {
		debug "\t\t pattern reject $i matched";
		debug "      rejecting token '$token' as a $key because its in the reject list";
		return ();
	    }
	}

	for (my $i = 0; $i < @{$userpass_REs{$key}}; $i++) {
	    debug "        $i: pattern test: $userpass_REs{$key}[$i]";
	    if ($token =~ $userpass_REs{$key}[$i]) {
		debug "\t\t pattern $i matched";
		return ($token, $i + 1);
	    }
	}
	debug "      NO match on field token '$token' as a $key";
    }

    return ();
}

my %card_field_specs = (
    address =>                  { textname => 'Address', fields => [
        [ 'address1',		0, qr/^Address Line 1$/, ],
        [ 'address2',		0, qr/^Address Line 2$/, ],
        [ 'city',		0, qr/^City$/, ],
        [ 'state_zip',		0, qr/^State Zip$/, ],
        [ 'county',		0, qr/^County$/, ],
        [ 'country',		0, qr/^Country$/, ],
    ]},
    authentication =>           { textname => 'Authentication', type_out => 'note', fields => [
        [ 'favuserid',		0, qr/^Favorite User ID$/, 	{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_string, 'favorite user id' ] } ],
        [ 'favpassword',	0, qr/^Favorite Password$/, 	{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_concealed, 'favorite password', 'generate'=>'off' ] } ],
        [ 'password_q',		0, qr/^Password Question$/, 	{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_string, 'password question' ] } ],
        [ 'password_a',		0, qr/^Password Answer$/, 	{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_concealed, 'password answer', 'generate'=>'off' ] } ],
    ]},
    bankacct =>                 { textname => 'Bank Account', fields => [
        [ 'bankName',		0, qr/^Bank Name$/, ],
        [ 'accountNo',		0, qr/^Account Number$/, ],
        [ 'accountType',	0, qr/^Account Type$/, ],
        [ 'routingNo',		0, qr/^Routing Number$/, ],
	[ '_branch',		0, qr/^Bank Branch$/,	{ custfield => [ $Utils::PIF::sn_branchInfo, $Utils::PIF::k_string, 'branch' ] } ],
        [ 'branchPhone',	0, qr/^Bank Phone$/, ],
        [ 'branchAddress',	0, qr/^Bank Address$/, ],
        [ 'swift',		0, qr/^SWIFT$/, ],
	[ '_rate',		0, qr/^Interest Rate$/,	{ custfield => [ $Utils::PIF::sn_extra, $Utils::PIF::k_string, 'interest rate' ] } ],
        [ 'owner',		0, qr/^Account Owner$/, ],
        [ 'telephonePin',	0, qr/^Bank PIN Code$/, ],
    ]},
    business =>                 { textname => 'Business', fields => [
        [ 'name',		0, qr/^Company Name$/, ],
        [ 'department',		0, qr/^Department$/, ],
        [ 'phone',		0, qr/^Toll Free Phone$/, ],
        [ 'website',		0, qr/^Web Site$/, ],
        [ 'biztype',		0, qr/^Business Type$/, ],
        [ 'employerid',		0, qr/^Employer Id$/, ],
        [ 'stocksym',		0, qr/^Stock Symbol$/, ],
    ]},
    car =>                      { textname => 'Car', type_out => 'note', fields => [
        [ 'plate',		0, qr/^Plate$/, ],
        [ 'make',		0, qr/^Make$/, ],
        [ 'model',		0, qr/^Model$/, ],
        [ 'year',		0, qr/^Year$/, ],
        [ 'vin',		0, qr/^VIN$/, ],
    ]},
    creditcard =>               { textname => 'Credit Card', fields => [
        [ 'type',		0, qr/^Card Type$/, ],
        [ 'ccnum',		0, qr/^Card Number$/, ],
        [ 'cvv',		0, qr/^Validation Code$/, ],
        [ '_expiry',		0, qr/^Card Expires$/, ],
        [ '_validFrom',		0, qr/^Valid From$/, ],
        [ 'cardholder',		0, qr/^Card User Name$/, ],
        [ 'bank',		0, qr/^Issuing Bank$/, ],
        [ 'phoneTollFree',	0, qr/^Cust Svc Phone $/, ],	# note trailing space
        [ 'phoneIntl',		0, qr/^Intl Svc Phone $/, ],	# note trailing space
        [ 'pin',		0, qr/^PIN Number$/, ],
        [ 'creditLimit',	0, qr/^Credit Limit$/, ],
        [ 'interest',		0, qr/^Interest Rate$/, ],
    ]},
    custom =>                   { textname => 'Custom', type_out => 'note', fields => [
    ]},
    person =>                   { textname => 'Person', type_out => 'identity', fields => [
        [ '_title',		0, qr/^Title$/, ],
        [ '_name',		0, qr/^Name$/, ],
        [ 'jobtitle',		0, qr/^Job Title$/, ],
        [ 'defphone',		0, qr/^Phone$/, ],
        [ 'homephone',		0, qr/^Home Tel$/, ],
        [ 'busphone',		0, qr/^Work Tel$/, ],
        [ 'cellphone',		0, qr/^Cell Tel$/, ],
        [ '_pager',		0, qr/^Pager$/, ],
        [ '_fax',		0, qr/^Fax$/, ],
        [ 'email',		0, qr/^Email$/, ],
        [ 'yahoo',		0, qr/^Yahoo ID$/, ],
        [ 'msn',		0, qr/^MSN ID$/, ],
        [ 'aim',		0, qr/^AOL Name$/, ],
        [ 'icq',		0, qr/^ICQ No$/, ],
        [ 'skype',		0, qr/^Skype ID$/, ],
        [ 'sex',		0, qr/^Sex$/, ],
        [ '_age',		0, qr/^Age$/, ],
        [ '_birthdate',		0, qr/^Birth Date$/, ],
        [ '_birthplace',	0, qr/^Birth Place$/, ],
        [ '_income',		0, qr/^Income$/, ],
        [ 'number',		0, qr/^Soc Sec No$/,		{ type_out => 'socialsecurity' } ],
        [ 'number',		0, qr/^Driver License$/,	{ type_out => 'driverslicense' } ],	# see DL FIXUP
        [ 'state',		0, qr/^Driver License State$/,	{ type_out => 'driverslicense' } ],	# see DL FIXUP
        [ '_expiry_date',	0, qr/^License Expires$/,	{ type_out => 'driverslicense' } ],	# see DL FIXUP
    ]},
    login =>                    { textname => undef, fields => [
        [ 'url',		1, qr/url/i, ],
	[ 'password',           1, \&userpass_matcher, ],
	[ 'username',           1, \&userpass_matcher, ],
    ]},
    passport =>                 { textname => 'Passport', fields => [
        [ 'number',		0, qr/^Passport Number$/, ],
        [ '_issue_date',	0, qr/^Passport Issue Date$/, ],
        [ '_expiry_date',	0, qr/^Passport Expiration Date$/, ],
    ]},
);

$DB::single = 1;					# triggers breakpoint when debugging

sub do_init {
    return {
	'specs'		=> \%card_field_specs,
	'imptypes'  	=> undef,
        'opts'          => [ [ q{      --windows            # export file is from Windows Roboform },
                               'windows' ],
                           ],
    };
}

sub clean {
    local $_ = shift;
    return undef if not defined $_;

    s/<WBR>//gi;
    s/<BR>/\n/gi;
    s/&shy;//g;
    s/(?:&nbsp;)+$//g;		# rf mac sometimes adds trailing nbsp
    s/(?:&nbsp;)+/ /g;		# rf mac inserts multiple nbsp chars as spaces
    return decode_entities $_;
}

my %rfinfo;
my %identity_title_re = (
    mac   => qr#\A\s*<TR align=left><TD class="caption" colspan=\d+>(.+?)</TD></TR>#ms,
    winv6 => qr#\A<TR align=left>\s*<TD class=caption(?: colSpan=\d+)?>(.+?)<\/TD><\/TR>\s*#ms,
    winv7 => qr#\A<DIV class=caption style="WIDTH: 100%; WORD-BREAK: break-all; CLEAR: both">(.*?)</DIV>\s*#ms,
);
my %entry_re = (
    mac   => qr#\A.*?<TABLE width="100%">\s*(.*?)\s*<\/TABLE>\s*</TD></TR>\s*#ms,
    winv6 => qr#\A.*?<TABLE width="100%">\s*(.*?)\s*<\/TABLE>\s*</TD>(?:</TR>)?\s*#ms,
    winv7 => qr#\A.*?<DIV class="floatdiv orph">(.+?)</TABLE>(?:</DIV>){1,2}\s*#ms,
);
my %url_re = (
    mac   => qr#^.*?<TR align=left><TD class="subcaption" colspan=\d+>(.+?)</TD></TR>#ms,
    winv6 => qr#^.*?<TR align=left>\s*<TD class=subcaption colSpan=\d+>(.+?)</TD></TR>\s*#ms,
    winv7 => qr#.*?<TD class=subcaption style="WORD-BREAK: break-all; COLOR: gray" colSpan=\d+>(.*?)</TD></TR>#msi,
);
my %re_fvpair = (
    mac   => qr#<TR><TD class=field align=left valign=top width="40%">(.+?)</TD><TD></TD><TD class=wordbreakfield align=left valign=top width="55%">(.+?)</TD></TR>\s*#,
    winv6 => qr#<TR>\s*<TD class=field[^>]*>(.*?)</TD>.*?<TD class=wordbreakfield [^>]*>(.*?)</TD></TR>\s*#msi,
    winv7 => qr#<TR width="100%">\s*<TD width=.*? class=field[^>]*>(.*?):?</TD>.*?<TD width=.*? class=field[^>]*>(.*?)</TD></TR>\s*#msi,
);
my %re_entry_type = (
    mac   => qr#\A<TR align=left><TD class="subcaption" colspan=3>(.+?)</TD></TR>\s*#ms,
    winv6 => qr#\A.*?<TR align=left>\s*<TD class=subcaption colSpan=\d+>(.+?)</TD></TR>\s*#ms,
    winv7 => qr#\A.*?<TR align=left width="100%">\s*<TD class=idsubcaption style="WORD-BREAK: break-all" colSpan=3>(.+?)</TD></TR>\s*#ms,
);

# Patterns used to detect the export type, per-plaform, per-Roboform release
my %type_pats = (
    winv7 => {
	logins     => '<P style="FONT-SIZE:.*; TEXT-ALIGN: center">__TYPE_STRING__</P>',
	safenotes  => '<P style="FONT-SIZE:.*; TEXT-ALIGN: center">__TYPE_STRING__</P>',
	identities => '<P style="FONT-SIZE:.*; TEXT-ALIGN: center">__TYPE_STRING__</P>\s*<DIV class=preline>\s*',
    },
    winv6 => {
	logins     => qr#<HEAD><TITLE>RoboForm Passcards List#,
	safenotes  => qr#<HEAD><TITLE>RoboForm Safenotes List#,
	identities => qr#<HTML><HEAD><TITLE>RoboForm Identities List.*?<TBODY>\s*#ms,
    },
    mac => {
	safenotes  => sub { ! grep(/class="subcaption"/, $_[0]) },
	logins     => sub { m#<TR align=left><TD class="caption" colspan=3>.+?</TD></TR>\s+<TR align=left><TD class="subcaption" colspan=3>.+?</TD></TR>#m },
	identities => sub { m#^<TR align=left><TD class="caption" colspan=1>.*?</TD></TR>\s+<TR><TD style="border-left: 0 solid darkgray; border-right-width: 0;" valign=top align=left width="100%">\s+<TABLE width="100%">\s+<TR align=left><TD class="subcaption" colspan=3>Person#m },
    }
);

sub do_import {
    my ($files, $imptypes) = @_;
    my %Cards;
    my $n = 1;
    my $entry_re;
	 
    # for debugging Windows exports on OS X
    $^O = 'MSWin32'	if exists $main::opts{'windows'};

    for my $file (ref($files) eq 'ARRAY' ? @$files : $files) {
	$_ = slurp_file($file, $^O eq 'MSWin32' ? 'UTF-16LE' : 'UTF-8');
	s/^\x{FEFF}//;		# remove BOM

	get_export_file_info($_);

	my $identity_name;								# identity entry blocks are preceeded by the identity name
	while (my $entry = get_next_entry(\$_)) {
	    my (%cmeta, @fieldlist);
	    my ($title, $label, $value);
	    my $identity_type;

	    if ($rfinfo{'type'} eq 'safenotes') {
		my $notes;
		($title, $notes) = get_notes($entry);
		$title ||= 'Untitled';
		if ($notes) {
		    debug "\tnotes => unfold_and_chop $notes";
		    $cmeta{'notes'} = $notes;
		}
	    }
	    else {
		if ($rfinfo{'type'} eq 'logins') {
		    $title = get_title($entry);
		    debug "\tfull title: $title";

		    if (my $url = get_url($entry)) {
			debug "\tfield(url) => $url";
			push @fieldlist, [ url => $url ];
		    }

		    if (my $notes = get_notes($entry)) {
			debug "\tnotes => unfold_and_chop $notes";
			$cmeta{'notes'} = $notes;
		    }
		}

		elsif ($rfinfo{'type'} eq 'identities') {
		    if (ref $entry eq 'SCALAR') {
			$identity_name = $$entry;
			debug "**** Identity items for ", $identity_name;
			next;
		    }

		    my @a = split / - /, get_identity_entry_type($entry);
		    $identity_type = shift @a;
		    debug "\t**Identity subtype: ", $identity_type;
		    $title = myjoin ' - ', $identity_name, $identity_type, @a;
		}

		while (1) {
		    ($label, $value) = get_fv_pair($entry);
		    last if !defined $label;

		    # Notes from login's print list on darwin
		    if ($rfinfo{'version'} ne 'winv7' and $label eq 'Note$') {
			$cmeta{'notes'} = clean $value;
			debug "\tnotes => ", unfold_and_chop $cmeta{'notes'};
			next;
		    }

		    next if not defined $value or $value eq '';

		    my $fvref = undef;
		    if ($rfinfo{'type'} eq 'identities') {
			$label =~ s/^"(.*)"$/$1/	if $identity_type eq 'Custom';

			# DL FIXUPs
			if ($identity_type eq 'Person') {
			    if ($label eq '') {
				$label = 'License Expires'
			    }
			    elsif ($label eq 'Driver License') {
				$fvref = do_dl_fixup($label,$value);
			    }
			}
		    }
		    if ($fvref) {
			for (keys %$fvref) {
			    debug "\tfield($_) => $fvref->{$_}";
			    push @fieldlist, [ $_ => $fvref->{$_} ];
			}
		    }
		    else {
			debug "\tfield($label) => $value";
			push @fieldlist, [ $label => $value ];
		    }
		}
	    }

	    if ($title) {
		my @title = split $rfinfo{'pathsep_re'}, clean $title;
		$cmeta{'title'} = pop @title;
		debug "\ttitle => $cmeta{'title'}";
		if (@title) {
		    $cmeta{'tags'}   = join '::', @title;
		    $cmeta{'folder'} = [ @title ];
		    debug "\ttags => $cmeta{tags}";
		}
	    }

	    my $itype = find_card_type(\@fieldlist, $identity_type);

	    # skip all types not specifically included in a supplied import types list
	    next if defined $imptypes and (! exists $imptypes->{$itype});

	    prioritize_fieldlist($itype, \@fieldlist)	if $itype eq 'login';

	    my $normalized = normalize_card_data(\%card_field_specs, $itype, \@fieldlist, \%cmeta);
	    my $cardlist   = explode_normalized($itype, $normalized);

	    for (keys %$cardlist) {
		print_record($cardlist->{$_});
		push @{$Cards{$_}}, $cardlist->{$_};
	    }
	    $n++;
	}
    }

    summarize_import('item', $n - 1);
    return \%Cards;
}

sub do_dl_fixup {
    my ($l,$v) = @_;

    # mac:   CA&nbsp;N21828857Expires02/31/2019
    # winv7: CA&nbsp;&shy;N21&shy;828857
    if ($v =~ /^(?:(?<state>.+?) )?(?<num>.+?)(?:Expires(?<expires>.+))?$/) {
	my %dlhash;
	$dlhash{'Driver License'} = $+{num};
	$dlhash{'Driver License State'} = $+{state}	if exists $+{state};
	$dlhash{'License Expires'} = $+{expires}	if exists $+{expires} and $+{expires} ne '//';
	return \%dlhash;
    }

    return undef;
}

sub do_export {
    add_custom_fields(\%card_field_specs);
    create_pif_file(@_);
}

sub find_card_type {
    my $fieldlist = shift;
    my $identity_type = shift;

    for my $type (keys %card_field_specs) {
	# for identity sub types, match the textname
	if ($identity_type) {
	    if (defined $card_field_specs{$type}{'textname'} and $identity_type eq $card_field_specs{$type}{'textname'}) {
		debug "type detected as '$type'";
		return $type;
	    }
	    next;
	}
	else {
	    for my $cfs (@{$card_field_specs{$type}{'fields'}}) {
		for (@$fieldlist) {
		    if ($cfs->[CFS_TYPEHINT]) {
			if (ref $cfs->[CFS_MATCHSTR] eq 'CODE') {
			    if (my @ret = $cfs->[CFS_MATCHSTR]->($_, $cfs->[0]) and $_->[1] ne '') {
				debug "type detected as '$type' (pattern $ret[1], token='$ret[0]'	key='$_->[0]')";
				return $type;
			    }
			}
			elsif ($_->[0] =~ $cfs->[CFS_MATCHSTR]) {
			    debug "type detected as '$type' (key='$_->[0]')";
			    return $type;
			}
		    }
		}
	    }
	}
    }

    debug "\t\ttype defaulting to 'note'";
    return 'note';
}

# For 'login' types, need to munge the fieldlist to downgrade fields that would result in duplicate matches
# for a given key. For example, for the 'username' key, the HTML might contain form strings that result in
# both of the tokens 'username' and 'email', each of which would match the 'username' patterns.
# This will be done by modifying the field names of the lower priority entries such that they wont match in
# the normalize_card_data() routine.
#
sub prioritize_fieldlist {
    my ($type, $fieldlist) = @_;

    for my $cfs (@{$card_field_specs{$type}{'fields'}}) {
	debug "\tprioritizing key '$cfs->[0]'";

	# Add the cfs key and weight to the fieldlist entry.  A weight of 0 is added for simple single-RE matches
	for (@$fieldlist) {
	    if (ref $cfs->[CFS_MATCHSTR] eq 'CODE') {
		if (my @ret = $cfs->[CFS_MATCHSTR]->($_, $cfs->[0]) and $_->[1] ne '') {
		    debug "\tCODE match (pattern \#$ret[1] token='$ret[0]', key='$_->[0]')";
		    push @$_, ($cfs->[0], $ret[1]);		# add cfs key and weight
		    next;
		}
	    }
	    elsif ($_->[0] =~ $cfs->[CFS_MATCHSTR]) {
		debug "\tRE match (pattern $cfs->[CFS_MATCHSTR], key='$_->[0]')";
		push @$_, ($cfs->[0], 0);			# add cfs key and weight=0
		next;
	    }
	}
    }

    my (%field_key_done, @newlist);
    for (@$fieldlist) {
	# fieldlist entries that don't match - nothing to do
	if (not defined $_->[2]) {
	    push @newlist, $_;
	    next;
	}

	# skip already processed cfs keys
	next if exists $field_key_done{$_->[2]};

	# look for all fieldlist entries with the current key
	my $key = $_->[2];
	my @found = grep { defined $_->[2] and $_->[2] eq $key } @$fieldlist;

	# single entries just go to the new list
	if (@found == 1) {
	    push @newlist, @found;
	}

	# adjust the field name of 1..N-th entries so they will not match later in normalize_card_data()
	else {
	    @found = sort {$a->[3] <=> $b->[3] } @found;
	    for (my $i = 1; $i < @found; $i++) {
		$found[$i][0] = '[' . $found[$i][0] . ']';
	    }
	    push @newlist, @found;
	}

	$field_key_done{$_->[2]}++;		# done with this cfs key
    }

    # Done with the original fieldlist, now create a new one with the (possibly modified) field, value pairs
    @$fieldlist = ();
    push @$fieldlist, [ $_->[0], $_->[1] ]	 for @newlist;
}

# Localize the REs used to detect the export type.  See the %category_strings table above.  Only valid currently for winv7.
sub patch_langauage_strings {
    my $vers = $rfinfo{'version'};
    return unless $vers eq 'winv7';

    for my $type (keys %{$type_pats{$vers}}) {
	$type_pats{$vers}{$type} =~ s/__TYPE_STRING__/join '|', map { "(?:$_)" } @{$category_strings{$type}}/e;
	$type_pats{$vers}{$type} = qr/$type_pats{$vers}{$type}/;
    }
}


sub get_export_file_info {
    if    ($_[0] =~ /^<html>/) {		$rfinfo{'version'} = 'mac'; }
    elsif ($_[0] =~ /^<HTML>/) { 		$rfinfo{'version'} = 'winv6'; }
    elsif ($_[0] =~ s/^<!DOCTYPE html>.*?<BODY oncontextmenu="return false">\s*//ms) {	$rfinfo{'version'} = 'winv7'; }
    else {
	bail 'Unexpected RoboForm print list format; please report your platform and version of RoboForm';
    }

    if ($rfinfo{'version'} eq 'winv6') {
	#$_[0] =~ s/^.*?<TABLE width="100%">//ms;
	$rfinfo{'pathsep_re'} = qr/\\/;		# Win v6 uses \ as the folder separator
    }
    else {
	$_[0] =~ s/^.*?<body>//ms;
	$rfinfo{'pathsep_re'} = qr/\//;		# OS X and Win v7 use / as the folder separator

	patch_langauage_strings();
    }

    for my $key (keys %{$type_pats{$rfinfo{'version'}}}) {
	if (ref $type_pats{$rfinfo{'version'}}{$key} eq 'CODE') {
	    $rfinfo{'type'} = $key 	if &{$type_pats{$rfinfo{'version'}}{$key}}($_[0]);
	}
	elsif ($_[0] =~ s#$type_pats{$rfinfo{'version'}}{$key}##) {
	    $rfinfo{'type'} = $key;
	    last;
	}
    }
    exists $rfinfo{'type'} or
	bail "Failed to detect file's type from Roboform $rfinfo{'version'} export file";

    debug "RoboForm export version: $rfinfo{'version'}; type: $rfinfo{'type'}";
}

sub get_next_entry {
    my $sref = shift;
    my $ret;

    if ($rfinfo{'type'} eq 'identities' and $$sref =~ s#$identity_title_re{$rfinfo{'version'}}##) {
	return \(my $ref = clean $1);		# return a REF to indicate this is an identity title
    }
    elsif ($$sref =~ s#$entry_re{$rfinfo{'version'}}##) {
	$ret = $1;
    }

    return $ret	if defined $ret;
    return undef;
}

sub get_title {
    if ($rfinfo{'version'} eq 'mac') {
	if ($_[0] =~ s#^.*?<TR align=left><TD class="caption" colspan=\d+>(.+?)</TD></TR>\s*##ms) {
	    return clean $1;
	}
    }
    else {
	if ($rfinfo{'type'} eq 'logins') {
	    if ($rfinfo{'version'} eq 'winv6') {
		if ($_[0] =~ s#\A.*?<TR align=left>\s*<TD class=caption colSpan=\d+>(.+?)</TD></TR>\s*##ms) {
		    return $1;
		}
	    }
	    else {
		if ($_[0] =~ s#^.*<TD style="WORD-BREAK: break-all"><SPAN class=caption style="VERTICAL-ALIGN: middle; WORD-BREAK: break-all">(.*?)</SPAN></TD></TR>\s*##ms) {
		    return $1;
	    }
	}
	}
    }
    return undef;
}

sub get_url {
    my $ret;

    if ($_[0] =~ s#$url_re{$rfinfo{'version'}}##) {
	return lc clean $1;
    }

    return undef
}

sub get_fv_pair {
    if ($_[0] =~ s#$re_fvpair{$rfinfo{'version'}}##) {
	return (clean($1), clean($2));
    }

    return (undef, undef);
}

sub get_notes {
    if ($rfinfo{'version'} eq 'mac') {
	# bookmarks
	if ($rfinfo{'type'} eq 'logins' and $_[0] =~ s#<TR><TD class=wordbreakfield align=left valign=top width="100%">(.+?)</TD></TR>##m) {
	    return clean $1;
	}

	# safenotes: pull title and note
	if ($_[0] =~ s#<TR align=left><TD class="caption" colspan=\d+>(.*?)</TD></TR>\s*<TR><TD class=wordbreakfield [^>]+>(.*?)</TD></TR>##ms) {
	    return (clean($1), clean($2));
	}
    }
    elsif ($rfinfo{'version'} eq 'winv7') {
	if ($rfinfo{'type'} eq 'logins') {
	    # passcards/logins
	    if ($_[0] =~ s#<TR align=left width="100%">\s*<TD class=field[^>]*>Note:</TD>.*?<TD class=field[^>]*>(.*?)</TD></TR>\s*##msi) {
		return clean $1;
	    }
	    # bookmarks
	    elsif ($_[0] =~ s#\s*<TD width="100%" align=left class=field vAlign=top>(.*?)</TD></TR></TBODY></TABLE></TD></TR></TBODY>##ms) {
		return clean $1;
	    }
	}
	elsif ($rfinfo{'type'} eq 'safenotes') {
	    $_[0] =~ s#^.*<DIV class=caption style="WIDTH: \d+%; WORD-BREAK: break-all; CLEAR: both">(.*?)</DIV></TD></TR>.*<TD width="\d+%".*class=field[^>]*>(.*?)</TD></TR>##ms;
	    return (clean($1), clean($2));
	}
    }
    elsif ($rfinfo{'version'} eq 'winv6') {
	if ($rfinfo{'type'} eq 'logins') {
	    # bookmarks
	    if ($_[0] =~ s#^<TD class=wordbreakfield vAlign=top width="100%" align=left>(.+?)</TD></TR></TBODY>##m) {
		return clean $1;
	    }
	}
	elsif ($rfinfo{'type'} eq 'safenotes') {
	    $_[0] =~ s#^.*?<TBODY>\s*<TR align=left>\s*<TD class=caption colSpan=\d+>(.+?)</TD></TR>\s*<TR>\s*<TD class=wordbreakfield vAlign=top width="100%" align=left>(.+?)</TD></TR></TBODY>\s*##ms; 
	    return (clean($1), clean($2));
	}
    }

    return undef;
}

sub get_identity_entry_type {
    if ($_[0] =~ s#$re_entry_type{$rfinfo{'version'}}##ms) {
	return clean $1;
    }
    return undef;
}

1;
