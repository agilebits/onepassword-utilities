#!/usr/bin/perl

# Convert msecure to CSV for consumption into 1P4
#
# http://discussions.agilebits.com/discussion/24754/msecure-converter-for-1password-4

use v5.14;
use utf8;
use strict;
use warnings;
#use diagnostics;

binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

use Getopt::Long;
use File::Basename;
use Text::CSV;
#use Data::Dumper;

my $version = '1.01';

my ($verbose, $debug);
my $progstr = basename($0);

my $lang;

sub Usage {
    my $exitcode = shift;
    say @_ ? join('', @_, "\n") : '',
    <<ENDUSAGE, "\nStopped";
Usage: $progstr <options> <ewallet_export_text_file>
    options:
    --debug       | -d				# enable debug output
    --help	  | -h				# output help and usage text
    --lang	  | -l				# language in use: de es fr it ja ko pl pt ru zh-Hans zh-Hant
    --outfile     | -o <converted.csv>		# use file named converted.csv as the output file
    --type        | -t <type>			# login,creditcard,software,note
    --verbose     | -v				# output operations more verbosely
ENDUSAGE
    exit $exitcode;
}

my @save_ARGV = @ARGV;
my %opts = (
    outfile => join('/', $^O eq 'MSWin32' ? $ENV{'HOMEPATH'} : $ENV{'HOME'}, 'Desktop', '1P4_import.csv'),
); 

sub debug {
    return unless $debug;
    printf "%-20s: %s\n", (split(/::/, (caller(1))[3] || 'main'))[-1], join('', @_);
}

sub verbose {
    return unless $verbose;
    say @_;
}

sub debug_on   { $debug++; }
sub verbose_on { $verbose++; }

my @opt_config = (
	'debug|d'	 => sub { debug_on() },
	'help|h'	 => sub { Usage(0) },
	'lang|l=s'	 => sub { $lang = $_[1] },
	'outfile|o=s',
	'type|t=s',
	'verbose|v'	 => sub { verbose_on() },
);


{
local $SIG{__WARN__} = sub { say "\n*** ", $_[0]; };
Getopt::Long::Configure('no_ignore_case');
GetOptions(\%opts, @opt_config) or Usage(1);
}

@ARGV == 1 or Usage(1);

debug "Command Line: @save_ARGV";

if (exists $opts{'type'} and ! $opts{'type'} ~~ /^(?:login|software|creditcard|note)$/) {
    die "Invalid argument to --type: use one of login, software, creditcard, note.\nStopped";
}

if ($lang and $lang !~ /^(de|es|fr|it|ja|ko|pl|pt|ru|zh-Hans|zh-Hant)$/) {
    Usage 1, 'Unknown language type: ', $lang;
}


if ($opts{'outfile'} !~ /\.csv$/i) {
    $opts{'outfile'} = join '.', $opts{'outfile'}, 'csv';
}

# String localization.  mSecure has localized card types and field names, so these must be mapped
# to the localized versions in the Localizable.strings file for a given language.
# The type_map table below will be initialized using the localized card type key.  Field name
# localization is handled on output into a card's Notes section (since this is the only place
# field names are output.
my %localized;
if ($lang) {
    my $lstrings_path = '/Applications/mSecure.app/Contents/Resources/XX.lproj/Localizable.strings';
    $lstrings_path =~ s/XX/$lang/;

    local $/ = "\r\n";
    open my $lfh, "<:encoding(utf16)", $lstrings_path or die "Cannot open mSecure's localization strings file: $lstrings_path\n$!\nStopped";
    while (<$lfh>) {
	chomp;
	my ($key, $val) = split /" = "/;
	$key =~ s/^"//;
	$val =~ s/";$//;
	#say "Key: $key, Val: $val";
	$localized{$key} = $val;
    }
}

sub ll {
    my $key = shift;
    return $localized{$key} // $key;
}

# These map card types with its assosciated fields, and also to which 1P4 type an entry maps to.
# The hash key and the field names are also subject to localization lookups, so they must match exactly the English string key
# used for proper translation.
my %type_map = (
    ll('Bank Accounts') 	=> { type => 'note',       fields => [ qw/Group: Type Description Notes Account_Number PIN Name Branch Phone_No./ ]},
    ll('Birthdays')		=> { type => 'note',       fields => [ qw/Group: Type Description Notes Date/ ]},
    ll('Calling Cards')	 	=> { type => 'note',       fields => [ qw/Group: Type Description Notes Access_No. PIN/ ]},
    ll('Clothes Size') 	 	=> { type => 'note',       fields => [ qw/Group: Type Description Notes Shirt_Size Pant_Size Shoe_Size Dress_Size/ ]},
    ll('Combinations') 	 	=> { type => 'note',       fields => [ qw/Group: Type Description Notes Code/ ]},
    ll('Credit Cards')	 	=> { type => 'creditcard', fields => [ qw/Group: Type Description Notes Card_No. Expiration_Date Name PIN Bank Security_Code/ ]},
    ll('Email Accounts')	=> { type => 'note',       fields => [ qw/Group: Type Description Notes Username Password POP3_Host SMTP_Host/ ]},
    ll('Frequent Flyer')	=> { type => 'note',       fields => [ qw/Group: Type Description Notes Number URL Username Password Mileage/ ]},
    ll('Identity')		=> { type => 'note',       fields => [ qw/Group: Type Description Notes First_Name Last_Name Nick_Name Company Title Address Address2 City
									  f1 f2 f3 f4 f5 f6 f7 f8 f9 f10/ ]},
    ll('Insurance')		=> { type => 'note',       fields => [ qw/Group: Type Description Notes Policy_No. Group_No. Insured Date Phone_No./ ]},
    ll('Memberships')	 	=> { type => 'note',       fields => [ qw/Group: Type Description Notes Account_Number Name Date/ ]},
    ll('Note')		 	=> { type => 'note',       fields => [ qw/Group: Type Description Notes/ ]},
    ll('Passport') 		=> { type => 'note',       fields => [ qw/Group: Type Description Notes Name Number Type Issuing_Country Issuing_Authority Nationality
									  Expiration Place_of_Birth/ ]},
    ll('Prescriptions') 	=> { type => 'note',       fields => [ qw/Group: Type Description Notes RX_Number Name Doctor Pharmacy Phone_No./ ]},
    ll('Registration Codes')	=> { type => 'note',       fields => [ qw/Group: Type Description Notes Number Date/ ]},
    ll('Social Security') 	=> { type => 'note',       fields => [ qw/Group: Type Description Notes Name Number/ ]},
    ll('Unassigned') 	 	=> { type => 'note',       fields => [ qw/Group: Type Description Notes f1 f2 f3 f4 f5 f6/ ]},
    ll('Vehicle Info') 	 	=> { type => 'note',       fields => [ qw/Group: Type Description Notes License_No. VIN Date_Purchased Tire_Size/ ]},
    ll('Voice Mail')	 	=> { type => 'note',       fields => [ qw/Group: Type Description Notes Access_No. PIN/ ]},
    ll('Web Logins')	 	=> { type => 'login',      fields => [ qw/Group: Type Description Notes URL Username Password/ ]},

    '*'	 			=> { type => 'note',       fields => [ qw/Group: Type Description Notes f1 f2 f3 f4 f5 f6 f7 f8 f9 f10 f11 f12 f13 f14 f15 f16 f17 f18/ ]},
);

# This hash defines the CSV column order / 1P4 card type for importing.  The field names here must match the names used above in %type_map.
my %sortorders = (
    login	=> [ qw/Description URL Username Password Notes/ ],
    creditcard	=> [ qw/Description Card_No. Expiration_Date Name PIN Bank Security_Code Notes/ ],
    software	=> [ qw/Description Version License_Key Owner_Name Owner_Email Owner_Company Download_Link Publisher Publisher_URL Retail_Price
    			Support_Email Purchase_Date Order_Number Notes/ ],
    note	=> [ qw/Description Notes/ ],
);

# lookup hash used to quickly test if an imported field maps to an exported field
my %exp_card_fields;
for my $type (keys %sortorders) {
    $exp_card_fields{$type}{$_}++ 	for @{$sortorders{$type}};
}

my ($Cards, $numcards) = import_csv($ARGV[0]);
verbose "Imported $numcards card", $numcards > 1 || $numcards == 0 ? 's' : '';

for my $type (keys %$Cards) {
    next if exists $opts{'type'} and lc($type) ne $opts{'type'};
    my $n = scalar @{$Cards->{$type}};
    verbose "Exporting $n $type item", $n > 1 ? 's' : '';
    export_csv($Cards->{$type}, $type);
}

sub import_csv {
    my $file = shift;
    my %Cards;

    my $csv = Text::CSV->new ({ binary => 1, eol => ",\x{a}", allow_loose_quotes => 1, sep_char => ',', auto_diag => 2 });

    open my $io, "<:encoding(utf8)", $file or die "Failed to open CSV file: $file: $!\nStopped";

    # toss the header row
    {
	local $/ = "\x{0a}";
	my $header = <$io>; 
    }
    my $n = 1;
    while (my $row = $csv->getline ($io)) {
	if ($row->[0] eq '' and @$row == 1) {
	    warn "Skipping unexpected empty row: $n";
	    next;
	}

	my %card;
	debug 'ROW: ', $n;

	# $row->[1] contains the exported card type, used as a $type_map key.
	# Types may be redefined, so they may not be in the type_map, so map them to Notes (for now -
	# consider how to easily allow users to specify their remappings).
	if (! exists $type_map{$row->[1]}) {
	    warn "Renamed card type '$row->[1]' is not a default type, and is being mapped to Secure Notes\n";
	    unshift @{$card{'Notes'}}, join ': ', ll('Type'), $row->[1];
	    $row->[1] = '*';
	}

	my $cardtype = $type_map{$row->[1]}{'type'};

	if ($row->[1] ne '*' and @$row > @{$type_map{$row->[1]}{fields}}) {
	    warn '**** Hit mSecure CSV quoting bug on row ', $n, ': compensating...', "\n";
	    while (@$row > @{$type_map{$row->[1]}{fields}}) {
		$row->[3] .= ',' . splice @$row, 4, 1
	    }
	}

	for (my $i = 0; $i <= $#{$row}; $i++) {
	    $row->[$i] =~ s/\x{0b}/\n/g;
	    debug "\tfield: ", $type_map{$row->[1]}{'fields'}[$i], ' => ', $row->[$i];
	    # Notes field
	    if ($type_map{$row->[1]}{'fields'}[$i] eq 'Notes') {
		unshift @{$card{'Notes'}}, $row->[$i];
	    }
	    # All non mapped fields get pushed to the Notes field
	    elsif (!exists $exp_card_fields{$cardtype}{$type_map{$row->[1]}{'fields'}[$i]}) {
		my $label = ll(clean($type_map{$row->[1]}{'fields'}[$i]));
		$label =~ s/:$//;		# in localazaion file, 'Group:' is used (note trailing :)
		push @{$card{'Notes'}}, join ': ', $label, $row->[$i] unless $row->[$i] eq '';
	    }
	    # Mapped fields
	    else {
		$card{clean($type_map{$row->[1]}{'fields'}[$i])} = $row->[$i];
	    }
	}

	push @{$Cards{$cardtype}}, \%card;
	$n++;
    }
    if (! $csv->eof()) {
	warn "Unexpected failure parsing CSV: row $n";
    }

    return (\%Cards, $n - 1);
}

# Map underbar to space in field names
sub clean {
    $_ = shift;
    s/_/ /g;
    return $_;
}

sub export_csv {
    my ($cardlist, $type) = @_;

    my $csv = Text::CSV->new ( { binary => 1, sep_char => ',' } );

    (my $file = $opts{'outfile'}) =~ s/\.csv$/_$type.csv/;
    open my $outfh, ">:encoding(utf8)", $file or die "Cannot create output file: $file\n$!\nStopped";
    for my $card (@$cardlist) {
	my @row;
	for my $col (@{$sortorders{$type}}) {
	    $col = clean($col);
	    push @row, !exists $card->{$col} ? ''
			  : ref($card->{$col}) eq 'ARRAY'
			  ? join("\n", @{$card->{$col}}) : $card->{$col};
	}
	$csv->combine(@row) or die "Failed to combine card fields into a CSV string\nStopped";
	print $outfh $csv->string(), "\r\n";
	debug $csv->string();
    }
    close $outfh;
}

sub print_record {
    my $h = shift;

    for my $key (keys $h) {
	print "\t$key: ";
	print "$_\n"  for (ref($h->{$key}) eq 'ARRAY' ? @{$h->{$key}} : $h->{$key});
    }
}

sub unfold_and_chop {
    local $_ = shift;

    return undef if not defined $_;
    s/\R/<CR>/g;
    my $len = length $_;
    return $_ ? (substr($_, 0, 77) . ($len > 77 ? '...' : '')) : '';
}

# For a given string parameter, returns a string which shows
# whether the utf8 flag is enabled and a byte-by-byte view
# of the internal representation.
#
sub hexdump
{
    use Encode;
    my $str = shift;
    my $flag = Encode::is_utf8($str) ? 1 : 0;
    use bytes; # this tells unpack to deal with raw bytes
    my @internal_rep_bytes = unpack('C*', $str);
    return
        $flag
        . '('
        . join(' ', map { sprintf("%02x", $_) } @internal_rep_bytes)
        . ')';
}

1;
