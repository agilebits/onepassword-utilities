#!/usr/bin/perl

use v5.14;
use strict;
use warnings;
binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

use Getopt::Long;
use File::Basename;
use XML::Parser;
use HTML::Entities;
use Data::Dumper;
use Text::CSV;

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
#    --type        | -t <type>			# login,creditcard,software,note
    --verbose     | -v				# output operations more verbosely
ENDUSAGE
    exit $exitcode;
}

my @save_ARGV = @ARGV;
my %opts = (
    outfile => join('/', $^O eq 'MSWin32' ? $ENV{'HOMEPATH'} : $ENV{'HOME'}, 'Desktop', '1P4_import.csv'),
    type    => 'login',
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
#	'type|t=s',
	'verbose|v'	 => sub { verbose_on() },
);

{
local $SIG{__WARN__} = sub { say "\n*** ", $_[0]; };
Getopt::Long::Configure('no_ignore_case');
GetOptions(\%opts, @opt_config) or Usage(1);
}

debug "Command Line: @save_ARGV";

#if (exists $opts{'type'} and ! $opts{'type'} ~~ /^(?:login|software|creditcard|note)$/) {
#    die "Invalid argument to --type: use one of login, software, creditcard, note.\nStopped";
#}

if ($opts{'outfile'} !~ /\.csv$/i) {
    $opts{'outfile'} = join '.', $opts{'outfile'}, 'csv';
}

@ARGV == 1 or Usage(1);

my $file = shift;

die "Can't find file \"$file\""
    unless -f $file;

my @Cards;
my %fields = ();
my @paths;		# xml paths
my @group;		# current group hierarchy

my %sortorders = (
    login	=> [ qw/title location=url username password notes=comment/ ],
    creditcard	=> [ qw/title cardnumber cardexpires cardholder cardpin cardbank cardcvv notes/ ],
    software	=> [ qw/title version licensekey ownername owneremail ownercompany downloadlink publisher publisherURL retailprice supportemail purchasedate ordernumber notes/ ],
    note	=> [ qw/title notes/ ],
);

my $parser = new XML::Parser(ErrorContext => 2);

$parser->setHandlers(
    Char =>     \&char_handler,
    Start =>    \&start_handler,
    End =>      \&end_handler,
    Final =>    \&final_handler,
    Default =>  \&default_handler
);

$parser->parsefile($file);

@Cards or
    die "No entries detected\n";

my $csv = Text::CSV->new ( { binary => 1, sep_char => ',' } );
open my $outfh, ">:encoding(utf8)", $opts{'outfile'}
    or die "Cannot create output file: $opts{'outfile'}\n$!\nStopped";

my $type = 'login';
for my $card (@Cards) {
    my @row;
    for (@{$sortorders{$type}}) {
	my ($import_name, $export_name) = split '=', $_;
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

# handlers below

sub start_handler {
    my ($p, $el) = @_;

    push @paths, my $path = join('::', $p->context, $el);
    debug 'START path: ', $path;

    sub get_values {
	my $attr_re = shift;
	my $ret = '';

	while (@_) {
	    my ($a, $v) = (shift, shift);
	    $ret = ($ret ? join($1 ? '=' : ' ', $ret, $v) : $v)  if $v and $a =~ /$attr_re/;
	}
	return $ret;
    }

    if (defined $p->current_element) {

	if ($path =~ /::group$/) {
	    debug "=== START GROUP";
	}
	elsif ($path =~ /::group::entry$/) {
	    debug "START ENTRY";
	    %fields = ();
	}
	elsif ($path =~ /::group::entry::comment::br$/) {
	    debug "\tSTART NEWLINE";
	}
    }
}

sub char_handler {
    my ($p, $data) = @_;

    my $path = $paths[-1];

    #if ($data eq '&' or $data eq '<' or $data eq '>') { $data = encode_entities($data); }	# only required when output is XML
    # the expat parser returns entities as single characters
    #else					      { $data = decode_entities($data); }

    if ($path =~ /::group::title$/) {
	push @group, $data;
	debug "\tGroup name: ==> '$data'";
    }
    elsif ($path =~ /::group::entry::(.+)$/) {
	debug " **** Field: $1 ==> '$data'";
	$fields{$1}	  .= $data;
    }
    else {
	debug "\t\t...ignoring char data: ", $data =~ /^\s+/ms ? 'WHITESPACE' : $data;
    }
}

sub end_handler {
    my ($p, $el) = @_;

    my $path = pop @paths;
    debug '__END path: ', $path;

    if ($path =~ /::group$/) {
	debug "========= END GROUP: ", pop @group;
    }
    elsif ($path =~ /::group::entry$/) {
	debug "END ENTRY: ... output values\n";
	$fields{'group'} = join '::', @group;
	push @Cards, { %fields };
	#print Dumper \%fields;

	return;
    }
    elsif ($path =~ /::group::entry::comment::br$/) {
	debug "\tEND_ NEWLINE added to comment";
	$fields{'comment'} .= "\n";
    }
}

sub final_handler {
    #print Dumper(\%fields);
}

sub default_handler { }

1;
