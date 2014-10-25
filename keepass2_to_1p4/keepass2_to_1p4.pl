#!/usr/bin/perl

# Converts a KeePass2 XML export into PIF format for importing into 1P4
#
# http://discussions.agilebits.com/discussion/24909/keepass2-converter-for-1password-4
#
# Copyright 2014 Mike Cappella

use v5.14;
use strict;
use warnings;
binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

use Getopt::Long;
use File::Basename;
use XML::Parser;
use HTML::Entities;
use JSON::PP;
use UUID::Tiny ':std';
#use Data::Dumper;

my $version = "2.0";

my ($verbose, $debug);
my $progstr = basename($0);

my %typeMap = (
    login =>		'webforms.WebForm',
    note =>		'securenotes.SecureNote',
);

my %supported_types;
$supported_types{$_}++ for keys %typeMap;
my $supported_types = join ' ', sort keys %typeMap;

sub Usage {
    my $exitcode = shift;
    say @_ ? join('', @_, "\n") : '',
    <<ENDUSAGE, "\nStopped";
Usage: $progstr <options> <keepassx_export_file.xml>
    options:
    --debug           | -d			# enable debug output
    --help	      | -h			# output help and usage text
    --outfile         | -o <converted.1pif>     # use file named converted.1pif as the output file
    --sparselogin     | -s                      # create login type when at least username or password exists
    --type            | -t <type list>          # comma separated list of one or more types from list below
    --verbose         | -v			# output operations more verbosely
    --[no]watchtower  | -w                      # set each card's creation date to trigger WatchTower checks (default: on)

    supported types:
	- $supported_types
ENDUSAGE
    exit $exitcode;
}

my @save_ARGV = @ARGV;
my %opts = (
    outfile => join('/', $^O eq 'MSWin32' ? $ENV{'HOMEPATH'} : $ENV{'HOME'}, 'Desktop', '1P4_import'),
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
	'sparselogin|s',
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
	unless (exists $supported_types{$_}) {
	    Usage 1, "Invalid --type argument '$_'; see supported types.";
	}
	$t{$_}++;
    }
    $opts{'type'} = \%t;
}

my $file_suffix = '1pif';
if ($opts{'outfile'} !~ /\.${file_suffix}$/i) {
    $opts{'outfile'} = join '.', $opts{'outfile'}, $file_suffix;
}

my $file = shift;

-f $file or
    die "Can't find file \"$file\"";

my %fields = ();
my @paths;		# xml paths
my @group;		# current group hierarchy
my $currentkey;		# the current key name being parsed
my $collecting = 1;	# is the parser currently collecting data?

my @gCards;
my $Cards = import_xml($file);
export_pif($Cards);

sub import_xml {
    my $file = shift;

    my $parser = new XML::Parser(ErrorContext => 2);

    $parser->setHandlers(
	Char =>     \&char_handler,
	Start =>    \&start_handler,
	End =>      \&end_handler,
	Final =>    \&final_handler,
	Default =>  \&default_handler
    );

    $parser->parsefile($file);

    @gCards or
	die "No entries detected\n";

    my ($n, %Cards);
    for my $card (@gCards) {
	my $type = 'note';

	$type = 'login' if exists $card->{'username'} and exists $card->{'password'};
	$type = 'login' if exists $opts{'sparselogin'} and (exists $card->{'username'} or exists $card->{'password'});

	push @{$Cards{$type}}, $card;
	$n++;
    }
    verbose "Imported $n card", $n > 1 || $n == 0 ? 's' : '';
    return \%Cards;
}

sub export_pif {
    my $cardlist = shift;

    #open my $outfh, ">:encoding(utf8)", $opts{'outfile'} or
    open my $outfh, ">", $opts{'outfile'} or
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

    for my $type (keys %$cardlist) {
	next if exists $opts{'type'} and not exists $opts{'type'}{lc $type};
	my $n = scalar @{$cardlist->{$type}};
	verbose "Exporting $n $type item", ($n > 1 || $n == 0) ? 's' : '';

	for my $card (@{$cardlist->{$type}}) {
	    my (%f, $ret);
	    $f{'typeName'} = $typeMap{$type} // $typeMap{'note'};

	    if (exists $card->{'title'}) { $f{'title'} = $card->{'title'}; delete $card->{'title'}; }
	    if (exists $card->{'group'}) { push @{$f{'openContents'}{'tags'}}, $card->{'group'}; delete $card->{'group'}; }

	    # logins and notes have a different format than other 1P4 entries, and this works as a nice catch all
	    if (exists $card->{'username'}) {
		push @{$f{'secureContents'}{'fields'}}, { designation => 'username', name => 'Username', type => 'T', value => $card->{'username'} };
		delete $card->{'username'};
	    }
	    if (exists $card->{'password'}) {
		push @{$f{'secureContents'}{'fields'}}, { designation => 'password', name => 'Password', type => 'P', value => $card->{'password'} };
		delete $card->{'password'};
	    }
	    if (exists $card->{'url'}) {
		$f{'location'} = $card->{'url'};
		push @{$f{'secureContents'}{'URLs'}}, { label => 'website', url => $card->{'url'} };
		delete $card->{'url'};
	    }

	    if (exists $card->{'notes'}) {
		$f{'secureContents'}{'notesPlain'} = ref($card->{'notes'}) eq 'ARRAY' ? join("\n", @{$card->{'notes'}}) : $card->{'notes'};
		delete $card->{'notes'};
	    }
	    for (keys %$card) {
		warn "Unmapped card field pushed to Notes: $_\n" if $_ ne 'favorite';
		$f{'secureContents'}{'notesPlain'} .= join ': ', "\n" . ucfirst $_, $card->{$_};
	    }

	    ($f{'uuid'} = create_uuid_as_string(UUID::Tiny->UUID_RANDOM(), 'cappella.us')) =~ s/-//g;
	    # set the creaated time to 1/1/2000 to help trigger WatchTower checks, unless --nowatchtower was specified
	    $f{'createdAt'} = 946713600		if $opts{'watchtower'};

	    my $encoded = encode_json \%f;
	    print $outfh $encoded, "\n", '***5642bee8-a5ff-11dc-8314-0800200c9a66***', "\n";
	}
    }
    close $outfh;

}

# handlers below

sub start_handler {
    my ($p, $el) = @_;

    push @paths, my $path = join('::', $p->context, $el);
    debug 'START path: ', $path;

    if (defined $p->current_element) {

	# Ignore the data in the card's History group
	if ($path =~ /::Group::Entry::History$/) {
	    debug "START HISTORY - collecting disabled";
	    $collecting = 0;
	    return;
	}

	return if not $collecting;
	if ($path =~ /::Group$/) {
	    debug "=== START GROUP";
	}
	elsif ($path =~ /::Group::Entry$/) {
	    debug "START ENTRY";
	    %fields = ();
	}
	elsif ($path =~ /::Group::Entry::String::Key$/) {
	    debug "START KEY";
	}
    }
}

sub char_handler {
    my ($p, $data) = @_;

    my $path = $paths[-1];

    #if ($data eq '&' or $data eq '<' or $data eq '>') { $data = encode_entities($data); }	# only required when output is XML
    # the expat parser returns entities as single characters
    #else					      { $data = decode_entities($data); }

    return if not $collecting;

    if ($path =~ /::Group::Name$/) {
	push @group, $data;
	debug "\tGroup name: ==> '$data'";
    }
    elsif ($path =~ /::Group::Entry::String::Key$/) {
	debug " **** current key: '$data'";
	$currentkey = lc $data;
    }
    elsif ($path =~ /::Group::Entry::String::Value$/) {
	debug " **** Field: $currentkey ==> '$data'";
	$fields{$currentkey} .= $data;
    }
    else {
	debug "\t\t...ignoring char data: ", $data =~ /^\s+/ms ? 'WHITESPACE' : $data;
    }
}

sub end_handler {
    my ($p, $el) = @_;

    my $path = pop @paths;
    debug '__END path: ', $path;

    if ($path =~ /::Group::Entry::History$/) {
	debug "END HISTORY - collecting enabled";
	$collecting = 1;
	return;
    }

    return if not $collecting;

    if ($path =~ /::Group$/) {
	debug "========= END GROUP: ", pop @group;
    }
    elsif ($path =~ /::Group::Entry$/) {
	debug "END ENTRY: ... output values\n";
	$fields{'group'} = join '::', @group[1..$#group];
	push @gCards, { %fields };
	#print Dumper \%fields;

	return;
    }
}

sub final_handler {
    #print Dumper(\%fields);
}

sub default_handler { }

1;
