# OS X Keychain text export converter
#
# Copyright 2014 Mike Cappella (mike@cappella.us)

package Converters::Keychain 1.05;

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

use Encode;
use Time::Local qw(timelocal);
use Time::Piece;
use Term::ReadKey;
use PBKDF2::Tiny qw/derive/;

# Use Crypt::CBC module for decryption when available, otherwise fallback to calling openssl
my $can_CryptCBC;
BEGIN {
    eval "require Crypt::CBC";
    $can_CryptCBC = 1 unless $@;
}
#$can_CryptCBC = 0;				# uncomment to force use of openssl even when Crypt::CBC is present
use if ! $can_CryptCBC, 'MIME::Base64';

my $max_encrypted_password_length = 200;	# don't bother decrypting long password data
my $max_password_length		  = 80;		# skip entries whose decrypted passwords are improbably long

my %card_field_specs = (
    login =>			{ textname => undef, fields => [
	[ 'username',		0, qr/^username$/ ],
	[ 'password',		0, qr/^password$/ ],
	[ 'url',		0, qr/^url$/ ],
    ]},
    note =>			{ textname => undef, fields => [
    ]},
);

my (%entry, $itype);

# The following table drives transformations or actions for an entry's attributes, or the class or
# data section (all are collected into a single hash).  Each ruleset is evaluated in order, as are
# each of the rules within a set.  The key 'c' points to a code reference, which is passed the data
# value for the given type being tested.  It can transform the value in place, or simply test it and
# return a string (for debug output).  When the key 'action' is set to 'SKIP', the entry being tested
# will be rejected from consideration for export when the 'c' code reference returns a TRUE value.
# And in that case, the code ref pointed to by 'msg' will be run to produce debug output, used to
# indicate the reason for the rejection.
#
# The table facilitates adding new transformations and rejection rules, as necessary,
# through empirical discover based on user feedback.
my @rules = (
    CLASS => [
		{ c => sub { $_[0] !~ /^inet|genp$/ }, action => 'SKIP', msg => sub { debug "\tskipping non-password class: ", $_[0] } },
    ],
    svce => [
		{ c => sub { $_[0] =~ s/^0x([A-F\d]+)\s+".*"$/pack "H*", $1/ge } },
		{ c => sub { $_[0] =~ s/^"(.*)"$/$1/ } },
		{ c => sub { $_[0] =~ /^Apple Persistent State Encryption$/ or 
			     $_[0] =~ /^Preview Signature Privacy$/ or
			     $_[0] =~ /^Safari Session State Key$/ or
			     $_[0] =~ /^Call History User Data Key$/}, action => 'SKIP',
		    msg => sub { debug "\t\tskipping non-password record: $entry{'CLASS'}: ", $_[0] } },
    ],
    srvr => [
		{ c => sub { $_[0] =~ s/^"(.*)"$/$1/ } },
		{ c => sub { $_[0] =~ s/\.((?:_afpovertcp|_smb)\._tcp\.)?local// } },
    ],
    path => [
		{ c => sub { $_[0] =~ s/^"(.*)"$/$1/ } },
		{ c => sub { $_[0] =~ s/^<NULL>$// } },
    ],
    ptcl => [
		{ c => sub { $_[0] =~ s/0x00000000 // } },
		{ c => sub { $_[0] =~ s/htps/https/ } },
		{ c => sub { $_[0] =~ s/^"(\S+)\s*"$/$1/ } },
    ],
    acct => [
		{ c => sub { $_[0] =~ s/^0x([A-F\d]+)\s+".*"$/pack "H*", $1/ge } },
		{ c => sub { $_[0] =~ s/^"(.*)"$/$1/ } },
    ],
    mdat => [
		{ c => sub { $_[0] =~ s/^0x\S+\s+"(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z.+"$/$1-$2-$3 $4:$5:$6/g } },
    ],
    cdat => [
		{ c => sub { $_[0] =~ s/^0x\S+\s+"(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z.+"$/$1-$2-$3 $4:$5:$6/g } },
    ],
    desc => [
		{ c => sub { $_[0] =~ s/^"(.*)"$/$1/; $_[0] } },
    ],
    # type must come before DATA so that 'note' type can be used as a condition in DATA below
    type => [
		{ c => sub { $_[0] =~ s/^"(.*)"$/$1/; $itype = 'note' if $_[0] eq 'note'; $_[0] } },
    ],
    DATA => [
		# secure note data, early terminates rule list testing
		{ c => sub { $itype eq 'note' and $_[0] =~ s/^.*<key>NOTE<\/key>\\012\\011<string>(.+?)<\/string>.*$/$1/ }, action => 'BREAK',
		    msg => sub { debug "\t\tskipping non-password record: $entry{'CLASS'}: ", $entry{'svce'} // $entry{'srvr'} } },

		{ c => sub { $_[0] !~ s/^"(.+)"$/$1/ }, action => 'SKIP',
		    msg => sub { debug "\t\tskipping non-password record: $entry{'CLASS'}: ", $entry{'svce'} // $entry{'srvr'} } },
		{ c => sub { $_[0] =~ /^[A-Z\d]{8}-[A-Z\d]{4}-[A-Z\d]{4}-[A-Z\d]{4}-[A-Z\d]{12}$/ }, action => 'SKIP',
		    msg => sub { debug "\t\tskipping record with CLSID type password: $entry{'CLASS'}: ", $entry{'svce'} // $entry{'srvr'} } },
		{ c => sub { length $_[0] > $max_password_length }, action => 'SKIP',
		    msg => sub { debug "\t\tskipping record with improbably long password: $entry{'CLASS'}: ", $entry{'svce'} // $entry{'srvr'} } },
		{ c => sub { join '', "\trecord: class = $entry{'CLASS'}: ", $entry{'svce'} // $entry{'srvr'} } },	# debug output only
    ],
);

$DB::single = 1;					# triggers breakpoint when debugging

sub do_init {
    return {
	'specs'		=> \%card_field_specs,
	'imptypes'  	=> undef,
	'opts'		=> [ 
	      		     [ q{      --password <pass>    # specify the keychain's password },
			       'password=s' ],
			   ],
    };
}

sub do_import {
    my ($file, $imptypes) = @_;
    my (%Cards, %dup_check);

    my $password;
    if (exists $main::opts{'password'}) {
	$password = $main::opts{'password'};
    }
    else {
	# Ask for the user's password
	print "Enter the keychain's password: ";
	ReadMode('noecho');
	chomp($password = <STDIN>);
	ReadMode(0);
	print "\n";
    }

    my $key_list = get_keylist_from_keychain($file, $password);
    $key_list or bail "Failed to get list of decryption keys - aborting";

    my  $contents = qx(security dump-keychain -r "$file");
    my ($n, $examined, $skipped, $duplicates) = (1, 0, 0, 0);

KEYCHAIN_ENTRY:
    while ($contents) {
	if ($contents =~ s/\Akeychain: (.*?)\n+(?=$|^keychain: ")//ms) {
	    local $_ = $1; my $orig = $1;
	    $itype = 'login';
	    %entry = ();

	    $examined++;
	    debug "Entry ", $examined;

	    s/\A"(.*?)"\n^(.+)/$2/ms;
	    my $keychain = $1;
	    #debug 'Keychain: ', $keychain;

	    # icloud exports may have a "version: value" line
	    s/\Aversion: (\d+)\n//ms;

	    s/\Aclass: "?(.*?)"? ?\n//ms;
	    $entry{'CLASS'} = $1;

	    # attributes
	    if ($_ eq 'attributes:') {
		debug "\t    skipping empty keychain entry: no attributes";
		$skipped++;
		next KEYCHAIN_ENTRY;
	    }

	    s/\Aattributes:\n(.*?)(?=^raw data:)//ms;
	    my $attrs = $1;
	    debug "raw attibute list:\n$attrs";
	    for my $attr (split /\n\s*/, $1 =~ s/^\s+//r) {
		my ($f,$v) = split /=/, $attr;
		bail "Unexpected undefined value in class=$entry{'CLASS'} attribute '$f'\n$attrs"	if not defined $v;
		$f = clean_attr_name($f);
		debug "\tattr($f) => '$v'";
		$entry{$f} = $v;
	    }

	    # data
	    s/\Araw data:\n(.+)\z//ms;
	    if (defined $1) {
		my $rawdata = $1;
		if ($entry{'CLASS'} =~ /inet|genp/ and $rawdata =~ /^(\S+)\s+"ssgp.+"$/) {
		    my $hex = $1;
		    my $bytes = pack("H*", $hex =~ s/^0x//r);
		    # don't bother trying to decode improbably long password data
		    if (length $bytes <= $max_encrypted_password_length) {
			$entry{'DATA'} = '"' . SSGPDecryption($bytes, $key_list) . '"';
		    }
		}
	    }
	    if (!defined $entry{'DATA'}) {
		$entry{'DATA'} = '';
	    }

	    # run the rules in the rule set above
	    # for each set of rules for an entry key...
RULE:
	    for (my $i = 0;  $i < @rules; $i += 2) {
		my ($key, $ruleset) = ($rules[$i], $rules[$i + 1]);

		debug "  considering rules for ", $key;
		next if not exists $entry{$key};

		# run the entry key's rules...
		my $rulenum = 1;
		for my $rule (@$ruleset) {
		    debug "\t    rule $rulenum: called with ", unfold_and_chop $entry{$key};

		    my $ret = ($rule->{'c'})->($entry{$key});

		    debug "\t    rule $rulenum: returns ", $ret || 0, '   ', unfold_and_chop $entry{$key};

		    if (exists $rule->{'action'}) {
			if ($ret) {
			    if ($rule->{'action'} eq 'SKIP') {
				$skipped++;
				($rule->{'msg'})->($entry{$key})		if exists $rule->{'msg'};
				next KEYCHAIN_ENTRY;
			    }
			    elsif ($rule->{'action'} eq 'BREAK') {
				debug "\t    breaking out of rule chain";
				next RULE;
			    }
			}
		    }

		    $rulenum++;
		}
	    }

	    for (keys %entry) {
		debug sprintf "\t    %-12s : %s", $_, $entry{$_}	if exists $entry{$_};
	    }

	    #my $itype = find_card_type(\%entry);

	    my (%h, @fieldlist, %cmeta);
	    if ($itype eq 'login') {
		$h{'password'}	= $entry{'DATA'};
		$h{'username'}	= $entry{'acct'}						if exists $entry{'acct'};
		if (exists $entry{'srvr'}) {
		    $h{'url'}	= $entry{'srvr'};
		    $h{'url'}	= $entry{'ptcl'} . '://' . $h{'url'}				if $entry{'ptcl'} ne '';
		    $h{'url'}  .= $entry{'path'}						if $entry{'path'} ne '';
		}
	    }
	    elsif ($itype eq 'note') {
		# convert ascii string DATA, which contains \### octal escapes, into UTF-8
		my $octets = encode("ascii", $entry{'DATA'});
		$octets =~ s/\\(\d{3})/"qq|\\$1|"/eeg;
		$cmeta{'notes'} = decode("UTF-8", $octets);
	    }
	    else {
		die "Unexpected itype: $itype";
	    }

	    # will be added to notes
	    $h{'protocol'}	= $entry{'ptcl'}					if exists $entry{'ptcl'} and $entry{'ptcl'} =~ /^afp|smb$/;

	    if ($main::opts{'notimestamps'}) {
		$h{'modified'}	= $entry{'mdat'}			if exists $entry{'mdat'};
		$h{'created'}	= $entry{'cdat'}			if exists $entry{'cdat'};
	    }
	    else {
		$cmeta{'modified'} = date2epoch($entry{'mdat'})		if exists $entry{'mdat'};
		$cmeta{'created'}  = date2epoch($entry{'cdat'})		if exists $entry{'cdat'};
	    }

	    for (keys %h) {
		debug sprintf "\t    %-12s : %s", $_, $h{$_}				if exists $h{$_};
	    }
 
	    # don't set/use $sv before $entry{'svce'} is removed of _afp*, _smb*, and .local, since it defeats dup detection
	    my $sv = $entry{'svce'} // $entry{'srvr'};

	    my $s = join ':::', 'sv', $sv,
		map { exists $h{$_} ? "$_ => $h{$_}" : 'URL => none' } qw/url username password/;

	    if (exists $dup_check{$s}) {
		debug "  *skipping duplicate entry for ", $sv;
		$duplicates++;
		next
	    }
	    $dup_check{$s}++;
	    $cmeta{'title'} = $sv;

	    push @fieldlist, [ $_ => $h{$_} ]	for keys %h;

	    my $normalized = normalize_card_data(\%card_field_specs, $itype, \@fieldlist, \%cmeta);
	    my $cardlist   = explode_normalized($itype, $normalized);

	    for (keys %$cardlist) {
		print_record($cardlist->{$_});
		push @{$Cards{$_}}, $cardlist->{$_};
	    }
	    $n++;
	}
	else {
	    bail "Keychain parse failed, after entry $examined; unexpected: ", substr $contents, 0, 2000;
	}
    }

    verbose "Examined $examined ", pluralize('item', $examined);
    verbose "Skipped $skipped non-login ", pluralize('item', $skipped);
    verbose "Skipped $duplicates duplicate ", pluralize('item', $duplicates);

    summarize_import('item', $n - 1);
    return \%Cards;
}

sub do_export {
    add_custom_fields(\%card_field_specs);
    create_pif_file(@_);
}

sub find_card_type {
    my $eref = shift;

    my $type = (exists $eref->{'desc'} and $eref->{'desc'} eq 'secure note') ? 'note' : 'login';
    debug "\t\ttype set to '$type'";
    return $type;
}

# sort logins as the last to check
sub by_test_order {
    return  1 if $a eq 'login';
    return -1 if $b eq 'login';
    $a cmp $b;
}

sub clean_attr_name {
    $_[0] =~ /"?([^<"]+)"?<\w+>$/;
    return $1;
}

# Date converters
# LastModificationTime field:	 yyyy-mm-dd hh:mm:ss
sub parse_date_string {
    local $_ = $_[0];
    my $when = $_[1] || 0;					# -1 = past only, 0 = assume this century, 1 = future only, 2 = 50-yr moving window

    if (my $t = Time::Piece->strptime($_, "%Y-%m-%d %H:%M:%S")) {
	return $t;
    }

    return undef;
}

sub date2epoch {
    my $t = parse_date_string @_;
    return undef if not defined $t;
    return defined $t->year ? 0 + timelocal($t->sec, $t->minute, $t->hour, $t->mday, $t->mon - 1, $t->year): $_[0];
}

###
### Keychain decryption code ported from ideas here: https://github.com/n0fate/chainbreaker
### 
sub get_keylist_from_keychain {
    my ($file, $password) = @_;

    my %key_list;
    my $raw_keychain = slurp_file($file);

    my $KeychainHeader = getHeader($raw_keychain);
    bail 'Invalid Keychain Format' 	if substr($KeychainHeader, 0, 4) ne "kych";

    my ($SchemaInfo, $TableList)	= getSchemaInfo($raw_keychain, getInt($KeychainHeader,12));
    my ($xTableMetadata, $RecordList)	= getTable($raw_keychain, $TableList->[0]);
    my ($tableCount, $tableEnum)	= getTablenametoList($raw_keychain, $RecordList, $TableList);

    my $CSSM_DB_RECORDTYPE_APP_DEFINED_START	= 0x80000000;
    my $CSSM_DL_DB_RECORD_METADATA		= $CSSM_DB_RECORDTYPE_APP_DEFINED_START + 0x8000;
    my $CSSM_DB_RECORDTYPE_OPEN_GROUP_START	= 0x0000000A;
    my $CSSM_DL_DB_RECORD_SYMMETRIC_KEY		= $CSSM_DB_RECORDTYPE_OPEN_GROUP_START + 7;

    my $masterkey = generateMasterKey($raw_keychain, $password,  $TableList->[$tableEnum->{$CSSM_DL_DB_RECORD_METADATA}]);	# generate master key
    my $dbkey	  =   findWrappingKey($raw_keychain, $masterkey, $TableList->[$tableEnum->{$CSSM_DL_DB_RECORD_METADATA}]);	# generate dbkey
    #debug "DBKEY: ", hexdump($dbkey);

    # get symmetric key blob
    my ($TableMetadata, $symmetrickey_list) = getTable($raw_keychain, $TableList->[$tableEnum->{$CSSM_DL_DB_RECORD_SYMMETRIC_KEY}]);

    for my $symmetrickey_record (@$symmetrickey_list) {
        my ($keyblob, $ciphertext, $iv, $return_value) =
	    getKeyblobRecord($raw_keychain, $TableList->[$tableEnum->{$CSSM_DL_DB_RECORD_SYMMETRIC_KEY}], $symmetrickey_record);
        if ($return_value == 0) {
            my $passwd = KeyblobDecryption($ciphertext, $iv, $dbkey);
            if ($passwd ne '') {
                $key_list{$keyblob} = $passwd;
	    }
	}
    }

    return \%key_list;
}

sub getInt {
    # buf, offset
    my $s = substr($_[0], $_[1], 4);
    return 0 + unpack("N", substr($_[0], $_[1], 4));
}

# get apple DB Header
sub getHeader {
   my $buf = shift;

    return substr($buf, 0, 20);
}

sub getSchemaInfo {
   my ($buf, $offset) = @_;

    my @table_list;
    my $schemaInfo = substr($buf, $offset, 8);
    my $tableCount = getInt($schemaInfo, 4);

    for (my $i = 0; $i < $tableCount; $i++) {
	my $BASE_ADDR = 20 + 8;
	push @table_list, getInt($buf, $BASE_ADDR + (4 * $i));
    }

    return ($schemaInfo, \@table_list);
}

sub getTable {
    my ($buf, $offset) = @_;

    my @record_list;
    my $base_addr = $offset + 20;

    my $TableMetaData = substr($buf, $base_addr, 28);
    my $record_offset_base = $base_addr + 28;

    my $record_count = 0;
    $offset = 0;
    my $TableMetaDataRecordCount = getInt($TableMetaData, 8);
    my $atom_size = 4;
    while ($TableMetaDataRecordCount != $record_count) {
	my $RecordOffset = getInt($buf, $record_offset_base + ($atom_size * $offset));
	1;
	if ($RecordOffset != 0 and $RecordOffset % 4 == 0) {
	    push @record_list, $RecordOffset;
	    $record_count++;
	}
	$offset++;
    }

    return ($TableMetaData, \@record_list);
}

sub getTablenametoList {
    my ($buf, $recordList, $tableList) = @_;
    my %TableDic;
    for (my $i = 0; $i < scalar @$recordList; $i++) {
	my ($tableMeta, $GenericList) = getTable($buf, $tableList->[$i]);
	$TableDic{getInt($tableMeta, 4)} = $i;		# TableID = offset 4; extract valid table list
    }

    return (scalar @$recordList, \%TableDic);
}

sub generateMasterKey {
    my ($raw_keychain, $password, $symmetrickey_offset) = @_;

    my $base_addr = 20 + $symmetrickey_offset + 0x38;			# base_addr = sizeof(_APPL_DB_HEADER) + symmetrickey_offset + 0x38
    my $dbblob = substr($raw_keychain, $base_addr, 92);
    my $salt = substr($dbblob, 44, 20);
    my $masterkey = PBKDF2::Tiny::derive('SHA-1', $password, $salt, 1000, 24);

    return $masterkey;
}

sub findWrappingKey {
    my ($raw_keychain, $masterkey, $symmetrickey_offset) = @_;

    my $base_addr = 20 + $symmetrickey_offset + 0x38;			# base_addr = sizeof(_APPL_DB_HEADER) + symmetrickey_offset + 0x38
    my $dbblob = substr($raw_keychain, $base_addr, 92);
    my $ciphertext = substr($raw_keychain, $base_addr + 120, 48);	# get cipher text area

    # decrypt the key
    my $iv = substr($dbblob, 64, 8);
    my $plain = kcdecrypt($masterkey, $iv, $ciphertext);

    return $plain;
}

sub getKeyblobRecord {
    my ($buf, $base, $offset) = @_;

    my $BASE_ADDR = 20 + $base + $offset;
    my $key_blob_rec_header_size = 132;
    my $KeyBlobRecHeader = substr($buf, $BASE_ADDR, $key_blob_rec_header_size);

    my $start = $BASE_ADDR + $key_blob_rec_header_size;
    my $end   = $BASE_ADDR + getInt($KeyBlobRecHeader, 0);
    my $record = substr($buf, $start, $end - $start);		# password data area

    my $KeyBlobRecord = substr($record, 0, 24);
    my $totalLength = getInt($KeyBlobRecord, 12);
    return (undef, undef, undef, 1)		if not substr($record, $totalLength + 8, 4) eq "ssgp";

    my $startCryptoBlob = getInt($KeyBlobRecord, 8);
    my $CipherLen = $totalLength - $startCryptoBlob;
    if ($CipherLen % 8 != 0) {
	say "Bad ciphertext len";
	return (undef, undef, undef, 1);
    }
    my $ciphertext = substr ($record, $startCryptoBlob, $totalLength - $startCryptoBlob);

    # match data, keyblob_ciphertext, Initial Vector, success
    return ( substr ($record, $totalLength + 8, 20), $ciphertext, substr($KeyBlobRecord, 16, 8), 0);
}

# Documents : http://www.opensource.apple.com/source/securityd/securityd-55137.1/doc/BLOBFORMAT
# source : http://www.opensource.apple.com/source/libsecurity_cdsa_client/libsecurity_cdsa_client-36213/lib/securestorage.cpp
# magicCmsIV : http://www.opensource.apple.com/source/Security/Security-28/AppleCSP/AppleCSP/wrapKeyCms.cpp
sub KeyblobDecryption {
    my ($encryptedblob, $iv, $dbkey) = @_;

    my $magicCmsIV = pack("H*", "4adda22c79e82105");
    my $plain = kcdecrypt($dbkey, $magicCmsIV, $encryptedblob);
    return ''		if length $plain == 0;

    # now we handle the unwrapping. we need to take the first 32 bytes,
    # and reverse them.
    my $revplain = pack("c*", reverse unpack("c*", substr($plain,0,32)));

    # now the real key gets found.
    $plain = kcdecrypt($dbkey, $iv, $revplain);

    if ($plain eq '' or length($plain) != 28) {		# length: 'ssgp' + 24
	bail "Failed to decrypt the keychain - did you supply the correct password?";
    }

    return substr($plain, 4);
}

sub kcdecrypt {
    my ($key, $iv, $data) = @_;

    return ''	if length($data) == 0;
    return ''	if length($data) % 8 != 0;

    my $plain;

    # macOS does not have any Perl Crypt libraries, so openssl is used for most people
    if ($can_CryptCBC) {
	my $cipher = Crypt::CBC->new(
		-cipher => 'DES_EDE3',
		-key => $key,
		-literal_key => 1,
		-iv => $iv,
		-add_header => 0,
		-keysize => length $key,
	);

	$plain = $cipher->decrypt($data);
	#printf "Crypto  %s, keylen: %d (%d), datalen: %d\n", hexdump($plain), length $key, length unpack("H*", $key), length $data;
    }
    else {
	my $keyH = unpack("H*", $key);
	my $ivH  = unpack("H*", $iv);
	# don't use openssl > 1.0.1m  - causes "hex string is too long" errors
	# https://mta.openssl.org/pipermail/openssl-bugs-mod/2016-May/000670.html
	my $data64 = MIME::Base64::encode_base64($data, "");
	my $algo = 'des-ede3-cbc';
	$plain = qx(printf "%s" "$data64" | /usr/bin/openssl $algo -d -a -A -iv "$ivH" -K "$keyH" -nosalt 2>&1);
	if ($plain =~ /bad decrypt\n.*:error:/ms) {
	    return '';
	}

	#printf "OPENSSL  %s, keylen: %d (%d), datalen: %d\n\n", hexdump($plain), length $key, length $keyH, length $data64;

    }

   return $plain;
}

## decrypted dbblob area
## Documents : http://www.opensource.apple.com/source/securityd/securityd-55137.1/doc/BLOBFORMAT
## http://www.opensource.apple.com/source/libsecurity_keychain/libsecurity_keychain-36620/lib/StorageManager.cpp
sub SSGPDecryption {
    my ($encrypted, $keylist) = @_;

    # map {say hexdump($_), ' --> ', hexdump($keylist->{$_}) } keys %$keylist
    my $realkey = $keylist->{substr($encrypted,0,20)};
    my $iv	= substr($encrypted,20,8);
    my $data	= substr($encrypted,28);

    return kcdecrypt($realkey, $iv, $data);
}

1;
