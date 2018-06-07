# Subsembly Wallet 4X/4W HTML export converter
#
# Copyright 2016 Mike Cappella (mike@cappella.us)

package Converters::Wallet4 1.01;

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
use Time::Local qw(timelocal);
#use HTML::Entities;

my %card_field_specs = (
    address =>                  { textname => undef, type_out => 'note', fields => [
        [ 'cellphone',		0, 'Mobile phone', ],
        [ 'phone',		0, 'Phone', ],
        [ 'email',		0, 'E-Mail', ],
        [ 'fax',		1, 'Fax', ],
        [ 'street',		0, 'Street', ],
        [ 'city',		0, 'City', ],
    ]},
    bankacct =>                 { textname => undef, fields => [
        [ 'bankName',		0, 'Bank', ],
        [ 'accountNo',		0, 'Account Number', ],
        [ '_sortcode',		1, 'Sort Code', ],
        [ 'url',		0, 'URL', 			{ type_out => 'login' } ],
        [ 'username',		0, 'Account Login', 		{ type_out => 'login' } ],
        [ 'password',		0, 'Password', 			{ type_out => 'login' } ],
        [ 'branchPhone',	0, 'Phone Number', ],
        [ 'callcenterpw',	1, 'Call Center Password', 	{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_concealed, 'call center pw', 'generate'=>'off' ] } ],
        [ 'iban',		1, 'IBAN', ],
        [ '_bic',		1, 'BIC', ],
    ]},
    creditcard =>               { textname => undef, fields => [
        [ 'type',		1, 'Card Type', ],
        [ 'ccnum',		1, 'Card Number', ],
        [ 'pin',		0, 'PIN', ],
        [ 'cardholder',		1, 'Name of Holder', ],
        [ 'bank',		1, 'Issued By', ],
        [ 'expiry',		1, 'Valid Through', 		{ func => sub {return date2monthYear($_[0])}, keep => 1 } ],
        [ '_info',		0, 'Additional Info', ],
    ]},
    email =>                    { textname => undef, fields => [
        [ '_emailaddress',	0, 'E-Mail Address', ],
        [ 'pop_username',	0, 'User ID', ],
        [ 'pop_password',	0, 'Password', ],
        [ 'pop_server',		1, 'POP3-Server', ],
        [ 'smtp_server',	1, 'SMTP-Server', ],
        [ '_imapserver',	1, 'IMAP-Server', ],
    ]},
    internetpassword =>         { textname => undef, type_out => 'login', fields => [
        [ 'url',		1, 'Internet Address', ],
	[ 'username',		0, 'User ID', ],
	[ 'password',		0, 'Password', ],
    ]},
    numericcode =>              { textname => undef, type_out => 'note', fields => [
	[ '_code',		1, 'Code', 			{ custfield => [ $Utils::PIF::sn_main, $Utils::PIF::k_concealed, 'code', 'generate'=>'off' ] } ],
    ]},
    password =>                 { textname => undef, type_out => 'login', fields => [
	[ 'username',		1, 'User', ],
	[ 'password',		0, 'Password', ],
    ]},
    simplepassword =>           { textname => undef, type_out => 'password', fields => [
	[ 'password',		0, 'Password', ],
    ]},
    software =>                 { textname => undef, fields => [
	[ 'reg_name',		1, 'Licensed to', ],
	[ 'reg_code',		1, 'License Key', ],
	[ '_purchasedat',	1, 'Purchased at', ],
	[ 'order_date',		1, 'Date of Purchase', 		{ func => sub {return date2epoch($_[0])} }],
	[ '_couponcode',	1, 'Coupon Code', ],
	[ 'retail_price',	1, 'Price', ],
    ]},
);

$DB::single = 1;					# triggers breakpoint when debugging
my %localized;

sub do_init {
    return {
	'specs'		=> \%card_field_specs,
	'imptypes'  	=> undef,
	'opts'		=> [ [ q{-l or --lang <lang>        # language in use: de },
			       'lang|l=s'	=> sub { init_localization_table($_[1]) or Usage(1, "Unknown language type: '$_[1]'") } ],
			   ],
    };
}

sub do_import {
    my ($file, $imptypes) = @_;
    my %Cards;
    my $n = 1;

    # Localize the %card_field_specs table
    if (scalar %localized) {
	for my $key (keys %card_field_specs) {
	    for my $cfs (@{$card_field_specs{$key}{'fields'}}) {
		$cfs->[CFS_OPTS]{'i18n'} = ll($cfs->[CFS_MATCHSTR]);
	    }
	}
    }

    $_ = slurp_file($file, 'UTF-8');
    s/^\x{FEFF}//;		# remove BOM

    # Keep only the body contents
    $_ =~ s#\A.*?<body>(.+)</body>.*\z#$1#ims;

    # Eliminate the leading HTML, and fixup the inital wallet items list so that get_entries() can work recursively.
    $_ =~ s#^.*?(<h2><a name="0">.+?</a></h2>)(<ul>)#$1<div class="parent"><a href="\#00">Parent folder</a></div>$2#ims;

    my @Entries;
    get_entries('', \$_, \@Entries);

    for (@Entries)  {
	my ($title, $fieldlistref, $cmetaref) = @$_;
	debug "+++ Adding entry: $title";

	my (%cmeta, @fieldlist);
	%cmeta = %$cmetaref;
	@fieldlist = @$fieldlistref;

	debug "\tnotes => ", unfold_and_chop($cmeta{'notes'})		 if exists $cmeta{'notes'};

	my @folders = split /::/, $title;
	$cmeta{'title'} = pop @folders;
	shift @folders; shift @folders;		# shift out the empty entry and then the wallet name
	if (@folders) {
	    $cmeta{'tags'}   = join '::', @folders;
	    $cmeta{'folder'} = [ @folders ];
	    debug "\ttags => $cmeta{tags}";
	}

	my $itype = find_card_type(\@fieldlist);

	# skip all types not specifically included in a supplied import types list
	next if defined $imptypes and (! exists $imptypes->{$itype});

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
    my $fieldlist = shift;
    my $type = 'note';

    for $type (sort by_test_order keys %card_field_specs) {
	my ($nfound, @found);
	for my $cfs (@{$card_field_specs{$type}{'fields'}}) {
	    next unless $cfs->[CFS_TYPEHINT] and defined $cfs->[CFS_MATCHSTR];
	    for (@$fieldlist) {
		# type hint, requires matching the specified number of fields
		if ($_->[0] eq ($cfs->[CFS_OPTS]{'i18n'} // $cfs->[CFS_MATCHSTR])) {
		    $nfound++;
		    push @found, $_->[0];
		    if ($nfound == $cfs->[CFS_TYPEHINT]) {
			debug sprintf "type detected as '%s' (%s: %s)", $type, pluralize('key', scalar @found), join('; ', @found);
			return $type;
		    }
		}
	    }
	}
    }

    # internetpassword: Password + User ID + Internet Address
    # password:		Password + User
    # simplepassword:	Password
    if (grep { $_->[0] eq ll('Password') } @$fieldlist) {
	if (grep { $_->[0] eq ll('User') } @$fieldlist) {
	    $type = 'password';
	}
	elsif (@$fieldlist == 1) {
	    $type = 'simplepassword';
	}
    }

    debug "\t\ttype defaulting to '$type'";
    return $type;
}


# sort logins as the last to check
sub by_test_order {
    return  1 if $a eq 'login';
    return -1 if $b eq 'login';
    $a cmp $b;
}

=cut
Each category (aka Folder) starts with a Section Header...
  <h2><a name="508003273">my section name</a></h2>
  <div class="parent"><a href="#0">Parent folder</a></div>			# note: href == #0 differentiating it from an entry header

Next follows a list of the items within that category...
  <ul>
    <li><a href="#508004575">Card</a></li>
    <li><a href="#508004567">Dress Sizes</a></li>
    ...
  </ul>

And then a block for each entry.
  # entry #1 --------------
      ### Entry name
      <h2><a name="508004575">Card</a></h2>
      <div class="parent"><a href="#508003259">Parent folder</a></div>		# note: href != #0, differentiating it from a section header

      ### Key / Value pairs
      ### NOTE: The Favorites category will not have the items below
      <table>
	<tr> <th>File Name</th> <td>C:\Users\Mike Cappella\Desktop\1P_print.html</td> </tr>
	...
      </table>

      ### Notes
      <div class="notes">my notes</div>

      ### TAN table: Optional: only in category="TAN Lists" entries
      <table>
	<tr> <th>Nr.</th> <th>TAN</th> <th>Date used</th> <th>Amount</th> <th>BEN</th> <th>Remarks</th> </tr>
	<tr> <td>1</td> <td class="password">2747</td> <td>2/5/2016</td> <td>5.00</td> <td>8887</td> <td>my tan1 note</td> </tr>
	...
      </table>

  # entry #2 --------------
      ...

=cut

my $re_header	= qr#<h2><a name=[^>]+>(?<name>.+?)</a></h2><div class="parent"><a href="\#\d+">[^>]+</a></div>#i;
my $re_itemlist	= qr#<ul>(?<itemlist>.+?)</ul>#i;
my $re_notes	= qr#(?:<div class="notes">(?<notes>.*?)</div>)?#msi;
my $re_fields	= qr#(?:<table>(?<fields>.+?)</table>)?#i;
my $re_tantable	= qr#(?:<table>(?<tanfields>.+?)</table>)?#i;

sub get_entries {
    my ($parent_name, $sref, $lref) = @_;

    my $name;
    if ($$sref =~ s#\A$re_header##) {
	$name = $+{'name'};

	if ($$sref =~ s#\A$re_itemlist##) {
	    debug '***** Folder: ', $name;
	    if (defined $+{'itemlist'}) {
		my $i = 1;
		my @itemlist = ($+{'itemlist'} =~ m#<li><a href="\#\d+">(.*?)</a></li>#g);
		for (@itemlist) {
		    debug '******* Processing item(', $i++, '): ', $_;
		    get_entries(join('::', $parent_name, $name), $sref, $lref);
		}
	    }
	    else {
		debug "***** Section: $1, no items; skipping";
	    }
	}

	elsif ($$sref =~ s#\A${re_fields}${re_notes}${re_tantable}##) {
	    debug '***** Entry: ', $name;
	    my (%cmeta, @fieldlist);
	    if (exists $+{'notes'}) {
		$cmeta{'notes'} = $+{'notes'};
		if (exists $+{'fields'}) {
		    my $fields = $+{'fields'};
		    while ($fields =~ s#\A<tr>\s*<th>\s*(.+?)\s*</th>\s*<td(?: class="password")?>(.*?)</td>\s*</tr>\s*##ms) {
			debug "\tfield($1) => $2";
			push @fieldlist, [ $1 => $2 ];
		    }
		}
		if (exists $+{'tanfields'}) {
		    debug "TAN entry", unfold_and_chop $+{'tanfields'};
		    my $tf;
		    ($tf = $+{'tanfields'}) =~ s#<(/?)th>#<${1}td>#g;
		    while ($tf) {
			$tf =~ s#^<tr>(.+?)</tr>##;
			my @fields = split '<td(?: class="password")?>(.*?)</td>', $1;
			$cmeta{'notes'} = myjoin ("\n", $cmeta{'notes'}, myjoin(' ' x 5, @fields));
		    }
		}
		push @$lref, [ join('::', $parent_name, $name), \@fieldlist, \%cmeta ];
	    }
	    else {
		# Favorites entry - skip it since there is no way to relate the entry to the actual entry.
		debug "\tFavorite item: skipping";
	    }
	}
	else {
	    die "*******************  UNEXPECTED CASE ************************";
	}
    }

    return undef;
}

# m-d-yyyy
sub parse_date_string {
    local $_ = $_[0];

    #$_ = sprintf("%02d-%0d2%-%d", $1, $2, $3)	if /^\d{1,2}-\d{1,2}-\d{4}$/;
    s/\./\//g;
    if (my $t = Time::Piece->strptime($_, "%m/%d/%Y")) {
	return $t;
    }

    return undef;
}

sub date2epoch {
    my $t = parse_date_string @_;
    return undef if not defined $t;
    return defined $t->year ? 0 + timelocal($t->sec, $t->minute, $t->hour, $t->mday, $t->mon - 1, $t->year): $_[0];
}

sub date2monthYear {
    my $t = parse_date_string @_;
    return defined $t->year ? sprintf("%d%02d", $t->year, $t->mon) : $_[0];
}

# String localization.
# The %localized table will be initialized using the localized name as the key, and the english version
# as the value.
#
sub init_localization_table {
    my $lang = shift;
    main::Usage(1, "Unknown language type: '$lang'")
	unless defined $lang and $lang =~ /^(de)$/;

    if ($lang) {
	my $lstrings_path = join '.', File::Spec->catfile('Languages', 'wallet4'), $lang, 'txt';

	local $/ = "\n";
	#open my $lfh, "<:encoding(utf16)", $lstrings_path
	open my $lfh, "<:encoding(utf8)", $lstrings_path
	    or bail "Unable to open localization strings file: $lstrings_path\n$!";
	while (<$lfh>) {
	    chomp;
	    my ($key, $val) = split /" = "/;
	    $key =~ s/^"//;
	    $val =~ s/"$//;
	    #say "Key: $key, Val: $val";
	    if ($val =~ s#^/(.+)/$#$1#) {
		$val = qr/$val/;
	    }
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
