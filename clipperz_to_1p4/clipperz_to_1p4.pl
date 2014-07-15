#!/usr/bin/perl

# Converts a Clipperz JSON export into a 1PIF format for importing into 1P4
#
# http://discussions.agilebits.com/discussion/comment/127962#Comment_127962

use v5.14;
use utf8;
use strict;
use warnings;
use diagnostics;

binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

use Getopt::Long;
use File::Basename;
use JSON::PP;
use UUID::Tiny ':std';
  
#use Data::Dumper;

my $version = '1.02';

my ($verbose, $debug);
my $progstr = basename($0);

my $supported_types_pif = 'login creditcard software note socialsecurity passport email bankacct membership';
my %supported_types;
$supported_types{'pif'}{$_}++ for split(/\s+/, $supported_types_pif);

sub Usage {
    my $exitcode = shift;
    say @_ ? join('', @_, "\n") : '',
    <<ENDUSAGE, "\nStopped";
Usage: $progstr <options> <ewallet_export_text_file>
    options:
    --debug           | -d			# enable debug output
    --help	      | -h			# output help and usage text
    --outfile         | -o <converted.csv>	# use file named converted.csv as the output file
    --type            | -t <type list>		# comma separated list of one or more types from list below
    --verbose         | -v			# output operations more verbosely
    --[no]watchtower  | -w			# set each card's creation date to trigger Watchtower checks (default: on)
ENDUSAGE
    exit $exitcode;
}

my @save_ARGV = @ARGV;
my %opts = (
    outfile => join('/', $^O eq 'MSWin32' ? $ENV{'HOMEPATH'} : $ENV{'HOME'}, 'Desktop', '1P4_import'),
    format  => 'pif',
    watchtower => 1,
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
	'outfile|o=s',
	'type|t=s',
	'verbose|v'	 => sub { verbose_on() },
	'watchtower|w!'  => sub { $opts{$_[0]} = $_[1] },
);

{
local $SIG{__WARN__} = sub { say "\n*** ", $_[0]; };
Getopt::Long::Configure('no_ignore_case');
GetOptions(\%opts, @opt_config) or Usage(1);
}

debug "Command Line: @save_ARGV";
@ARGV == 1 or Usage(1);

if (exists $opts{'type'}) {
    my %t;
    for (split /\s*,\s*/, $opts{'type'}) {
	unless (exists $supported_types{$opts{'format'}}{$_}) {
	    Usage 1, "Invalid --type argument '$_'; see supported types.";
	}
	$t{$_}++;
    }
    $opts{'type'} = \%t;
}

(my $file_suffix = $opts{'format'}) =~ s/pif/1pif/;
if ($opts{'outfile'} !~ /\.${file_suffix}$/i) {
    $opts{'outfile'} = join '.', $opts{'outfile'}, $file_suffix;
}

my %typeMap = (
    note =>		'securenotes.SecureNote',
    socialsecurity =>	'wallet.government.SsnUS',
    passport =>		'wallet.government.Passport',
    software =>		'wallet.computer.License',
    creditcard =>	'wallet.financial.CreditCard',
    email =>		'wallet.onlineservices.Email.v2',
    bankacct =>		'wallet.financial.BankAccountUS',
    membership =>	'wallet.membership.Membership',
    login =>		'webforms.WebForm',
);

my %card_match_patterns = (
    login => [
	[ 'Site Name',		0, 0, qr/^Site Name: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'URL',		2, 0, qr/^URL:? ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'username',		3, 0, qr/^User Name: ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
	[ 'password',		4, 0, qr/^Password ([^\x{0a}]+)(?:\x{0a}|\Z)/ms ],
     ],
);

my %exp_card_fields;
if ($opts{'format'} eq 'pif') {
    for my $type (keys $supported_types{'pif'}) {
	$exp_card_fields{$type}{$_}++				for qw/title notes tags URL/;
    }
    for my $type (keys %card_match_patterns) {
	$exp_card_fields{$type}{$_->[0]}++			for @{$card_match_patterns{$type}};
    }
}

my $Cards = import_json();
export_pif($Cards) if $opts{'format'} eq 'pif';

sub import_json {
    my %Cards;

    # sort logins as the last to check
    sub by_test_order {
	return  1 if $::a eq 'login';
	return -1 if $::b eq 'login';
	$::a cmp $::b;
    }

    use open qw(:std :utf8);
    $/ = undef;
    $_ = <>;
    my $decoded = decode_json $_;

    my $n = 1;
    for (@$decoded) {
	my %c;
	my $type;

	$c{'title'} = $_->{'label'} // 'NO LABEL';

	my $fieldref = $_->{'currentVersion'}{'fields'};
	for my $key (keys %$fieldref) {
	    if ($fieldref->{$key}{'label'} =~ 'Username|Login' or
	        $fieldref->{$key}{'label'} eq 'Login')
	    {
		$c{'username'} = $fieldref->{$key}{'value'};
	    }
	    elsif ($fieldref->{$key}{'label'} =~ 'Password') {
		$c{'password'} = $fieldref->{$key}{'value'};
	    }
	    elsif ($fieldref->{$key}{'type'} eq 'URL') {
		$c{'URL'} = $fieldref->{$key}{'value'}
	    }
	    else {
		$c{$fieldref->{$key}{'label'}} = $fieldref->{$key}{'value'};
	    }

	    delete $fieldref->{$key};
	}
	push @{$c{'notes'}}, $_->{'data'}{'notes'}	if $_->{'data'}{'notes'} ne '';

	# When type isn't set already, it is a login if username and password exists;
	# otherwise, everything else is a note.
	$type ||= (exists $c{'username'} and exists $c{'password'}) ? 'login' : 'note';
	debug "\tCard Type: ", $type;

	debug "";

	push @{$Cards{$type}}, { %c };

	$debug and print_record(\%c);
	$n++;
    }

    $n--;
    verbose "Imported $n card", ($n > 1 || $n == 0) ? 's' : '';
    return \%Cards;
}

sub export_pif {
    my $cardlist = shift;

    open my $outfh, ">:encoding(utf8)", $opts{'outfile'} or
	die "Cannot create 1pif output file: $opts{'outfile'}\n$!\nStopped";

    # href, key, k, n, t, v, a
    sub field_knta {
	my $h = shift, my $k = shift;
	my $sc;
	if (ref $h eq 'ARRAY') {
	    $sc = $h->[1]; $h = $h->[0];
	}
	return undef unless exists $h->{$k};

	my $href = { 'k' => shift, 'n' => shift, 't' => shift, 'v' => $h->{$k} };
	$href->{'a'} = { @_ }	if @_;
	$sc->{$href->{'n'}} = $h->{$k}	if defined $sc;
	delete $h->{$k};
	return $href;
    }
    sub new_section {
	my ($var, $key, $name, $title) = (shift, shift, shift, shift);
	my @a;
	for (@_) {
	    push @a, $_ if defined $_;
	}
	scalar @a and push @{$var->{$key}{'sections'}}, { name => $name, title => $title, fields => [ @a ] };
    }
    sub make_t {
	local $_ = shift;
	s/\s+/_/g;
	return lc $_;
    }

    for my $type (keys %$cardlist) {
	next if exists $opts{'type'} and not exists $opts{'type'}{lc $type};
	my $n = scalar @{$cardlist->{$type}};
	verbose "Exporting $n $type item", ($n > 1 || $n == 0) ? 's' : '';

	for my $card (@{$cardlist->{$type}}) {
	    my (%f, $ret);
	    $f{'typeName'} = $typeMap{$type} // $typeMap{'note'};

	    if (exists $card->{'title'}) { $f{'title'} = $card->{'title'}; delete $card->{'title'}; }
	    if (exists $card->{'tags'}) { push @{$f{'openContents'}{'tags'}}, $card->{'tags'}; delete $card->{'tags'}; }

	    if ($type eq 'login') {
		# notes field: card notes and all unmapped fields
		# Move to notes any key/value pairs that don't belong in the export type
		my %extra_fields;
		for (keys %$card) {
		    if (!exists $exp_card_fields{$type}{$_}) {
			$extra_fields{$_} = $card->{$_};
		    }
		}

		if (keys %extra_fields) {
		    new_section(\%f, 'secureContents', 'extraFields', 'Extra Fields', 
				map { field_knta( $card, $_,      'string',    make_t($_),       $_) } keys %extra_fields
			       );
		}
	    }

	    # logins and notes have a different format, and this works as a nice catch all
	    if (exists $card->{'username'}) {
		push @{$f{'secureContents'}{'fields'}}, { designation => 'username', name => 'Username', type => 'T', value => $card->{'username'} };
		delete $card->{'username'};
	    }
	    if (exists $card->{'password'}) {
		push @{$f{'secureContents'}{'fields'}}, { designation => 'password', name => 'Password', type => 'P', value => $card->{'password'} };
		delete $card->{'password'};
	    }
	    if (exists $card->{'URL'}) {
		$f{'location'} = $card->{'URL'};
		push @{$f{'secureContents'}{'URLs'}}, { label => 'website', url => $card->{'URL'} };
		delete $card->{'URL'};
	    }
	    if (exists $card->{'notes'}) {
		$f{'secureContents'}{'notesPlain'} = ref($card->{'notes'}) eq 'ARRAY' ? join("\n", @{$card->{'notes'}}) : $card->{'notes'};
		delete $card->{'notes'};
	    }
	    for (keys %$card) {
		debug "Unmapped field pushed to notes: $_\n";
		$f{'secureContents'}{'notesPlain'} .= join ': ', "\n" . ucfirst $_, $card->{$_};
	    }

	    ($f{'uuid'} = create_uuid_as_string(UUID::Tiny->UUID_RANDOM(), 'cappella.us')) =~ s/-//g;
	    # set the creaated time to 1/1/2000 to help trigger Watchtower checks, unless --nowatchtower was specified
	    $f{'createdAt'} = 946713600		if $opts{'watchtower'};

	    my $encoded = encode_json \%f;
	    print $outfh $encoded, "\n", '***5642bee8-a5ff-11dc-8314-0800200c9a66***', "\n";
	}
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
    use Encode qw/is_utf8/;
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

# parts from module: Data::Uniqid;
use Math::BigInt;
use Sys::Hostname;
use Time::HiRes qw( gettimeofday usleep );

sub base62() { ################################################### Base62 #####
  my($s)=@_;
  my(@c)=('0'..'9','a'..'z','A'..'Z');
  my(@p,$u,$v,$i,$n);
  my($m)=20;
  $p[0]=1;  
  for $i (1..$m) {
    $p[$i]=Math::BigInt->new($p[$i-1]);
    $p[$i]=$p[$i]->bmul(62);
  }

  $v=Math::BigInt->new($s);
  for ($i=$m;$i>=0;$i--) {
    $v=Math::BigInt->new($v);
    ($n,$v)=$v->bdiv($p[$i]);
    $u.=$c[$n];
  }
  $u=~s/^0+//;
  
  return($u);
}

sub unique_id {
    my ($s,$us) = gettimeofday(); usleep(1);
    my ($ia,$ib,$ic,$id) = unpack("C4", (gethostbyname(hostname()))[4]);
    my ($v) = sprintf("%06d%10d%06d%03d%03d%03d%03d", $us,$s,$$,$ia,$ib,$ic,$id);
    return (&base62($v));
}

1;
