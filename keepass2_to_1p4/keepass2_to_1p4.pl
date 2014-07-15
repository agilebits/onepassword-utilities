#!/usr/bin/perl

# Converts a KeePass2 XML export into a CSV file for consumption into 1P4
#
# http://discussions.agilebits.com/discussion/24909/keepass2-converter-for-1password-4

use v5.14;
use strict;
use warnings;
binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

use Getopt::Long;
use File::Basename;
use XML::Parser;
use HTML::Entities;
use Text::CSV;
#use Data::Dumper;

my $version = "1.0";

my ($verbose, $debug);
my $progstr = basename($0);

sub Usage {
    my $exitcode = shift;
    say @_ ? join('', @_, "\n") : '',
    <<ENDUSAGE, "\nStopped";
Usage: $progstr <options> <keepassx_export_file.xml>
    options:
    --debug       | -d				# enable debug output
    --help	  | -h				# output help and usage text
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
	'outfile|o=s',
	'type|t=s',
	'verbose|v'	 => sub { verbose_on() },
);

{
local $SIG{__WARN__} = sub { say "\n*** ", $_[0]; };
Getopt::Long::Configure('no_ignore_case');
GetOptions(\%opts, @opt_config) or Usage(1);
}

debug "Command Line: @save_ARGV";

if (exists $opts{'type'} and ! $opts{'type'} ~~ /^(?:login|software|creditcard|note)$/) {
    die "Invalid argument to --type: use one of login, software, creditcard, note.\nStopped";
}

if ($opts{'outfile'} !~ /\.csv$/i) {
    $opts{'outfile'} = join '.', $opts{'outfile'}, 'csv';
}

@ARGV == 1 or Usage(1);

my $file = shift;

-f $file or
    die "Can't find file \"$file\"";

my %fields = ();
my @paths;		# xml paths
my @group;		# current group hierarchy
my $currentkey;		# the current key name being parsed
my $collecting = 1;	# is the parser currently collecting data?

my %sortorders = (
    login	=> [ qw/title url username password notes/ ],
    creditcard	=> [ qw/title cardnumber cardexpires cardholder cardpin cardbank cardcvv notes/ ],
    software	=> [ qw/title version licensekey ownername owneremail ownercompany downloadlink publisher publisherURL retailprice supportemail purchasedate ordernumber notes/ ],
    note	=> [ qw/title notes/ ],
);

my @gCards;
my ($Cards, $numcards) = import_data($file);
verbose "Imported $numcards card", $numcards > 1 || $numcards == 0 ? 's' : '';

for my $type (keys %$Cards) {
    next if exists $opts{'type'} and lc($type) ne $opts{'type'};
    my $n = scalar @{$Cards->{$type}};
    verbose "Exporting $n $type item", $n > 1 ? 's' : '';
    export_csv($Cards->{$type}, $type);
}

sub import_data {
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

    my %Cards;
    for my $card (@gCards) {
	my $type = 'note';

	$type = 'login' if exists $card->{'username'} and exists $card->{'password'};

	push @{$Cards{$type}}, $card;
    }
    return (\%Cards, scalar @gCards);
}


sub export_csv {
    my ($cardlist, $type) = @_;

    my $csv = Text::CSV->new ( { binary => 1, sep_char => ',' } );
    (my $file = $opts{'outfile'}) =~ s/\.csv$/_$type.csv/;
    open my $outfh, ">:encoding(utf8)", $file
	or die "Cannot create output file: $file\n$!\nStopped";

    for my $card (@$cardlist) {
	my @row;
	for my $col (@{$sortorders{$type}}) {
	    my ($import_name, $export_name) = split '=', $col;
	    my $field_name = $export_name || $import_name;
	    if (exists $card->{$field_name}) {
		push @row, $card->{$field_name};
		delete $card->{$field_name};
	    }
	    else {
		push @row, '';
	    }
	}

	delete $card->{'icon'};
	debug "Extra keys (to notes): ", map { "$_: $card->{$_}\n" } keys %$card;
	if ($row[-1] ne '') {
	    $row[-1] .= "\n\n";
	}
	$row[-1] .= join ': ', 'Group', $card->{'group'};
	delete $card->{'group'};
	$row[-1] .= "\n$_: $card->{$_}" for keys %$card;
	$csv->combine(@row) or die "Failed to combine card fields into a CSV string\nStopped";
	print $outfh $csv->string(), "\r\n";
	debug $csv->string();
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
