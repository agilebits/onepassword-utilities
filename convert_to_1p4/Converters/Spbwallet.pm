# SPB Wallet converter
#
# Thanks: https://spbwalletexport.codeplex.com/
#
# Copyright 2015 Mike Cappella (mike@cappella.us)

package Converters::Spbwallet 1.03;

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

use DBI;
use Crypt::Rijndael;
use Digest::SHA1 qw(sha1);
use Encode qw(decode encode);
use Term::ReadKey;

my %card_field_specs = (
    bankacct =>                 { textname => 'Bank Account', fields => [
	[ 'accountNo',		0, qr/^Account #$/, ],
	[ 'routingNo',		0, qr/^Routing #$/, ],
	[ 'telephonePin',	0, qr/^PIN$/, ],
	[ '_accountType',	0, qr/^Account Type$/, ],
	[ 'branchPhone',	0, qr/^Branch Phone$/, ],
	[ 'swift',		0, qr/^Swift Code$/, ],
	[ 'iban',		0, qr/^I\.B\.A\.N\.$/, ],
	[ 'url',                0, qr/^Web Site$/,			{ type_out => 'login' } ],
	[ 'username',           0, qr/^User Name$/,			{ type_out => 'login' } ],
	[ 'password',           0, qr/^Password$/,			{ type_out => 'login' } ],
    ]},
    contact =>                  { textname => 'Contact', type_out => 'identity', fields => [
	[ 'firstname',		0, qr/^Name$/, ],
	[ 'company',		0, qr/^Company$/, ],
	[ 'homephone',		0, qr/^Home Phone$/, ],
	[ 'busphone',		0, qr/^Work Phone$/, ],
	[ 'cellphone',		0, qr/^Mobile Phone$/, ],
	[ 'email',		0, qr/^Email$/, ],
	[ 'website',		0, qr/^Web Site$/, ],
	[ 'icq',		0, qr/^ICQ$/, ],
	[ 'msn',		0, qr/^MSN$/, ],
	[ 'aim',		0, qr/^AOL$/, ],
    ]},
    creditcard =>               { textname => 'Credit Card', fields => [
	[ 'cardholder',		0, qr/^Owner$/, ],
	[ 'ccnum',		0, qr/^Card #$/, ],
	[ 'pin',		0, qr/^PIN$/, ],
	[ 'cvv',		0, qr/^CVV$/, ],
	[ 'bank',		0, qr/^Bank$/, ],
	[ 'creditLimit',	0, qr/^Limit$/, ],
	[ 'url',                0, qr/^Web Site$/,			{ type_out => 'login' } ],
	[ 'username',           0, qr/^User Name$/,			{ type_out => 'login' } ],
	[ 'password',           0, qr/^Password$/,			{ type_out => 'login' } ],
    ]},
    driverslicense =>           { textname => 'Driver License', fields => [
	[ 'fullname',		0, qr/^Full Name$/, ],
	[ 'number',		0, qr/^License #$/, ],
	[ 'state',		0, qr/^State$/, ],
	[ 'class',		0, qr/^Class$/, ],
	[ 'conditions',		0, qr/^Restrictions$/, ],
    ]},
    emailacct =>                { textname => 'Email Account', type_out => 'email', fields => [
	[ 'provider',		0, qr/^Email$/, ],
	[ 'smtp_username',	0, qr/^User Name$/, ],
	[ 'smtp_password',	0, qr/^Password$/, ],
	[ 'smtp_server',	0, qr/^Outgoing Srv$/, ],
	[ 'pop_server',		0, qr/^Incoming Srv$/, ],
	[ 'provider_website',	0, qr/^Web Site$/, ],
	[ 'phone_local',	0, qr/^Support Phn$/, ],
    ]},
    frequentflyer =>            { textname => 'Frequent Flyer Account', type_out => 'rewards', fields => [
	[ 'membership_no',	0, qr/^Account #$/, ],
	[ 'member_name',	0, qr/^Owner$/, ],
	[ 'company_name',	0, qr/^Airline$/, ],
	[ 'pin',		0, qr/^PIN$/, ],
	[ 'customer_service_phone', 0, qr/^Phone$/, ],
	[ 'url',                0, qr/^Web Site$/,			{ type_out => 'login' } ],
	[ 'username',           0, qr/^User Name$/,			{ type_out => 'login' } ],
	[ 'password',           0, qr/^Password$/,			{ type_out => 'login' } ],
    ]},
    hosting =>                  { textname => 'Hosting', type_out => 'server', fields => [
	[ 'url',                0, qr/^Web Site$/, ],
	[ 'username',           0, qr/^User Name$/, ],
	[ 'password',           0, qr/^Password$/, ],
	[ '_os',           	0, qr/^OS$/, 				{ to_title => 'value' } ],
	[ 'support_contact_phone', 0, qr/^Support Phn$/, ],
	[ 'support_contact_url',0, qr/^Support Site$/, ],
    ]},
    idcard =>                   { textname => 'ID Card', type_out => 'membership', fields => [
	[ 'org_name',		0, qr/^Card Title$/, ],
	[ 'member_name',	0, qr/^Full Name$/, ],
	[ 'membership_no',	0, qr/^ID #$/, ],
	[ 'pin',		0, qr/^PIN\/Code$/, ],
	[ 'phone',		0, qr/^Phone$/, ],
    ]},
    librarycard =>              { textname => 'Library Card', type_out => 'membership', fields => [
	[ 'org_name',		0, qr/^Library$/, ],
	[ 'member_name',	0, qr/^Full Name$/, ],
	[ 'membership_no',	0, qr/^Card #$/, ],
	[ 'pin',		0, qr/^PIN\/Code$/, ],
	[ 'phone',		0, qr/^Phone$/, ],
	[ 'username',		0, qr/^User Name$/, 			{ type_out => 'login' } ],
	[ 'password',		0, qr/^Password$/, 			{ type_out => 'login' } ],
	[ 'url',		0, qr/^Web Site$/, 			{ type_out => 'login' } ],
    ]},
    membership =>               { textname => 'Membership', fields => [
	[ 'org_name',		0, qr/^Organization$/, ],
	[ 'membership_no',	0, qr/^ID #$/, ],
	[ 'phone',		0, qr/^Phone$/, ],
	[ 'pin',		0, qr/^PIN$/, ],
	[ 'username',		0, qr/^User Name$/, 			{ type_out => 'login' } ],
	[ 'password',		0, qr/^Password$/, 			{ type_out => 'login' } ],
	[ 'url',		0, qr/^Web Site$/, 			{ type_out => 'login' } ],
    ]},
    note =>                     { textname => '', fields => [
    ]},
    onlineshoppingacct =>       { textname => 'Online Shopping Account', type_out => 'login', fields => [
	[ 'username',		0, qr/^User Name$/, ],
	[ 'password',		0, qr/^Password$/, ],
	[ 'url',		0, qr/^Web Site$/, ],
    ]},
    passport =>                 { textname => 'Passport', fields => [
	[ 'type',		0, qr/^Type$/, ],
	[ 'number',		0, qr/^Passport #$/, ],
	[ 'fullname',		0, qr/^Full Name$/, ],
	[ 'sex',		0, qr/^Sex$/, 	{ func => sub {return $_[0] =~ /F/i ? 'Female' : 'Male'} } ],
	[ 'nationality',	0, qr/^Citizenship$/, ],
	[ 'issuing_authority',	0, qr/^Authority$/, ],
	[ '_birthdate',		0, qr/^Birthday$/, ],
	[ 'birthplace',		0, qr/^Birth Place$/, ],
	[ '_issue_date',	0, qr/^Issued$/, ],
	[ '_expiry_date',	0, qr/^Expires$/, ],
	[ '_lostphone',		0, qr/^Lost Phone$/, ],
	[ '_replacements',	0, qr/^Replacements$/, ],
    ]},
    personalinsurance =>        { textname => 'Personal Insurance', type_out => 'membership', fields => [
	[ 'org_name',		0, qr/^Company$/, ],
	[ 'phone',		0, qr/^Phone$/, ],
	[ 'username',		0, qr/^User Name$/, 			{ type_out => 'login' } ],
	[ 'password',		0, qr/^Password$/, 			{ type_out => 'login' } ],
	[ 'url',		0, qr/^Web Site$/, 			{ type_out => 'login' } ],
    ]},
    server =>                   { textname => 'Server', fields => [
	[ '_service',          	0, qr/^Service$/, 			{ to_title => 'value' } ],
	[ 'username',           0, qr/^Admin Login$/, ],
	[ 'password',           0, qr/^Admin Pwd$/, ],
    ]},
    socialsecurity =>           { textname => 'Social Security Card', fields => [
	[ 'name',		0, qr/^Full Name$/, ],
	[ 'number',		0, qr/^SSN #$/, ],
	[ 'username',		0, qr/^User Name$/, 			{ type_out => 'login' } ],
	[ 'password',		0, qr/^Password$/, 			{ type_out => 'login' } ],
	[ 'url',		0, qr/^Web Site$/, 			{ type_out => 'login' } ],
    ]},
    software =>                 { textname => 'Software Serial Number', fields => [
	[ 'publisher_name',	0, qr/^Manufacturer$/, ],
	[ 'product_version',	0, qr/^Version$/, ],
	[ 'reg_code',		0, qr/^Key\/Code$/, ],
	[ '_product_name',	0, qr/^Product Name$/, 			{ to_title => 'value' } ],
	[ 'publisher_website',	0, qr/^Product Site$/, ],
	[ 'support_email',	0, qr/^Support Email$/, ],
	[ 'url',		0, qr/^Support Site$/, 			{ type_out => 'login' } ],
	[ 'username',		0, qr/^User Name$/, 			{ type_out => 'login' } ],
	[ 'password',		0, qr/^Password$/, 			{ type_out => 'login' } ],
    ]},
    website =>                  { textname => 'Web Site', type_out => 'login', fields => [
	[ 'username',		0, qr/^User Name$/, ],
	[ 'password',		0, qr/^Password$/, ],
	[ 'url',		0, qr/^Web Site$/, ],
    ]},
);

$DB::single = 1;					# triggers breakpoint when debugging

my %groupid_map;
my $cipher;

sub do_init {
    return {
	'specs'		=> \%card_field_specs,
	'imptypes'  	=> undef,
	'opts'		=> [ [ q{-D or --dump           # dump category / field table },
			       'dump|D' ],
			   ],
    };
}

sub do_import {
    my ($file, $imptypes) = @_;
    my %Cards;

    my $n = 1;

    # Ask for the user's password
    print "Enter your SPB Wallet password: ";
    ReadMode('noecho');
    chomp(my $password = <STDIN>);
    ReadMode(0);
    $password .= "\x0"; 
    print "\n";
    my $sha1 = sha1(pack 'v*', unpack('C*', $password));
    $password = '0'; $password = undef;
    my $key = substr($sha1, 0, 20) . substr($sha1, 0, 12);
    $cipher = Crypt::Rijndael->new($key, Crypt::Rijndael::MODE_ECB() );

    debug "*** Connecting to database file";
    my $dbh = DBI->connect("dbi:SQLite:dbname=$file","","") or
	bail "Unable to open wallet file: $file\n$DBI::errstr";

    my $sth;
    my (%categories, %cards, %values, %templatefield, %templates);

    debug "--- Decoding templates";
    $sth = $dbh->prepare("SELECT ID,Name,Description FROM spbwlt_Template");
    $sth->execute();
    for (@{$sth->fetchall_arrayref()}) {
	my $id = to_string($_->[0]);
	$templates{$id}{'Name'} = decrypt($_->[1]);
	$templates{$id}{'Description'} = decrypt($_->[2]);
    }
    $sth->finish();
    debug "--- Done decoding templates";

    debug "--- Decoding card field templates";
    $sth = $dbh->prepare("SELECT ID,Name,TemplateID,FieldTypeID FROM spbwlt_TemplateField");
    $sth->execute();
    for (@{$sth->fetchall_arrayref()}) {
	my $id = to_string($_->[0]);
	$templatefield{$id}{'Name'} = decrypt($_->[1]);
	$templatefield{$id}{'TemplateID'} = $templates{to_string($_->[2])};

	# FieldTypeID values
	# 1: plain text (case insensivte)
	# 2: plain text (caps only, numbers only?)
	# 3: plain text (case sensitive)
	# 4: hidden (pin, password, cvv)
	# 5: N/A
	# 6: URL
	# 7: email
	# 8: phone number
	$templatefield{$id}{'FieldTypeID'} = $_->[3];

	# add field to template
	push @{$templates{$templatefield{$id}{'TemplateID'}}{'fields'}}, \{
		name => $templatefield{$id}{'Name'},
		type => $templatefield{$id}{'FieldTypeID'}
	    };
    }
    $sth->finish();
    debug "--- Done decoding card field templates";

    # There should be a card field named 'Password' in the TemplateField table - if this isn't found,
    # then assume the user's password was incorrect and the decryption produced jibberish.
    #
    unless (grep { $templatefield{$_}{'Name'} eq 'Password'} keys %templatefield) {
	$dbh->disconnect();
	say "*** Disconnecting from database file";
	say "\nIncorrect password\n";
	exit 1;
    }

    debug "--- Decoding categories";
    $sth = $dbh->prepare("SELECT ID,ParentCategoryID,Name FROM spbwlt_Category");
    $sth->execute();
    for (@{$sth->fetchall_arrayref()}) {
	my $id = to_string($_->[0]);
	$categories{$id}{'ParentCategoryID'} = to_string($_->[1]);
	$categories{$id}{'Name'} = decrypt($_->[2]);
    }
    $sth->finish();
    debug "--- Done decoding categories";

    debug "--- Decoding cards";
    $sth = $dbh->prepare("SELECT ID,ParentCategoryID,Name,Description,TemplateID FROM spbwlt_Card");
    $sth->execute();
    for (@{$sth->fetchall_arrayref()}) {
	my $id = to_string($_->[0]);
	$cards{$id}{'ParentCategoryID'} = to_string($_->[1]);
	$cards{$id}{'Name'} = decrypt($_->[2]);
	$cards{$id}{'Description'} = decrypt($_->[3]);
	$cards{$id}{'TemplateID'} = $templates{to_string($_->[4])};
    }

    $sth->finish();
    debug "--- Done decoding cards";

    debug "--- Decoding card field values";
    $sth = $dbh->prepare("SELECT ID,CardID,TemplateFieldID,ValueString FROM spbwlt_CardFieldValue");
    $sth->execute();
    for (@{$sth->fetchall_arrayref()}) {
	my $id = to_string($_->[0]);
	my $cardid = to_string($_->[1]);
	$values{$id}{'def'} = $templatefield{to_string($_->[2])};
	$values{$id}{'value'} = decrypt($_->[3]);

	push @{$cards{$cardid}{'values'}}, $values{$id};
    }
    $sth->finish();
    debug "--- Done decoding card field values";

    $dbh->disconnect();
    debug "*** Disconnecting from database file";

    ##############

    if ($main::opts{'dump'}) {
	my %t;
	for my $cardid (keys %cards) {
	    for my $v (@{$cards{$cardid}{'values'}}) {
		$t{$cards{$cardid}{'TemplateID'}{'Name'}}{$v->{'def'}{'Name'}}++;
	    }
	}
	for my $template (sort keys %t) {
	    say "$template";
	    say "\t$_"	for keys %{$t{$template}};
	}
	exit;
    }

    for my $cardid (keys %cards) {
	my $itype = find_card_type($cards{$cardid}->{'TemplateID'}->{'Name'});

	# skip all types not specifically included in a supplied import types list
	next if defined $imptypes and (! exists $imptypes->{$itype});

	my (%cmeta, @fieldlist);
	$cmeta{'title'} = $cards{$cardid}{'Name'} // 'Untitled';
	my @card_category = get_category(\%categories, $cards{$cardid}{'ParentCategoryID'});
	$cmeta{'tags'} = join '::', @card_category;
	$cmeta{'folder'} = [ @card_category ];
	debug 'Category: ', $cmeta{'tags'};
	$cmeta{'notes'} = $cards{$cardid}{'Description'};

	for (@{$cards{$cardid}{'values'}}) {
	    push @fieldlist, [ $_->{'def'}->{'Name'} => $_->{'value'} ];
	    debug "\t    Field((T=$_->{'def'}->{'FieldTypeID'} $_->{'def'}->{'Name'}) = ", $_->{'value'} // '';
	}

	my $normalized = normalize_card_data(\%card_field_specs, $itype, \@fieldlist, \%cmeta);
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

sub find_card_type {
    my $f = shift;

    my $type = 'note';
    for my $type (keys %card_field_specs) {
	next unless $card_field_specs{$type}->{'textname'};
	if ($f =~ qr/$card_field_specs{$type}->{'textname'}/) {
	    debug "\t\ttype set to '$type'";
	    return $type;
	}
    }

    debug "\t\ttype defaulting to '$type'";
    return $type;
}

sub get_category {
    my $categories = shift;
    my $id = shift;

    my @cats;
    return '' if $id eq '';

    if ($categories->{$id}{'ParentCategoryID'} ne '') {
	push @cats, get_category($categories, $categories->{$id}{'ParentCategoryID'});
    }

    push @cats, $categories->{$id}{'Name'};
    return @cats;
}

sub decrypt {
    my $crypted = shift;

    my ($padlen, $padding) = (0, '');

    my $str = substr($crypted, 4);
    if (length($str) % 16) {
	$padlen = 2 * unpack "v", substr($crypted, 0, 4);
	$padding = pack "a" x (16 - (length($str) % 16));
    }
    my $plaintext = decode("UTF-16LE", substr $cipher->decrypt($padding . $str), $padlen);
    $plaintext =~ s/\x00*$//;
    #say "decrypt: ", $plaintext;

    return $plaintext;
}

# For a given string parameter, returns a string which shows
# whether the utf8 flag is enabled and a byte-by-byte view
# of the internal representation.
#
sub to_string
{
    use Encode qw/is_utf8/;
    my $str = shift;
    my $flag = Encode::is_utf8($str) ? 1 : 0;
    use bytes; # this tells unpack to deal with raw bytes
    my @internal_rep_bytes = unpack('C*', $str);
    return join('', map { sprintf("%02x", $_) } @internal_rep_bytes)
}

# Date converters
#     d-mm-yyyy			keys: date_added, date_modified, date_expire
sub parse_date_string {
    local $_ = $_[0];
    my $when = $_[1] || 0;					# -1 = past only, 0 = assume this century, 1 = future only, 2 = 50-yr moving window

    #s#^(\d/\d{2}/\d{4})$#0$1#;
    if (my $t = Time::Piece->strptime($_, "%m/%d/%Y")) {	# d/mm/yyyy
	return $t;
    }

    return undef;
}

sub date2epoch {
    my $t = parse_date_string @_;
    return undef if not defined $t;
    return defined $t->year ? 0 + timelocal($t->sec, $t->minute, $t->hour, $t->mday, $t->mon - 1, $t->year): $_[0];
}

1;
