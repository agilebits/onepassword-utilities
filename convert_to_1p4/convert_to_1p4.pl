#!/usr/bin/perl

#
# Copyright 2014 Mike Cappella (mike@cappella.us)

use v5.14;
use utf8;
use strict;
use warnings;
#use diagnostics;

binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

use Utils::PIF;
use Utils::Utils;
use Getopt::Long;
use File::Basename;
#use Data::Dumper;

my $version = "1.09";
my $progstr = basename($0);

my $show_full_usage_msg = 0;
my @converters = sort map {s/Converters\/(.*)\.pm$/$1/; lc $_} glob "Converters/*.pm";

my @save_ARGV = @ARGV;
@ARGV == 0 and Usage(1, "Missing converter name");
@ARGV == 1 and grep {$_ =~ /(^|\s)-(?:-help|h)\b/} @ARGV and Usage(0);
grep {lc $ARGV[0] eq $_ } @converters or Usage(1, "Invalid converter specified");

#@ARGV < 2 and Usage(1, "XMissing converter name");
my $module_name = shift;
my $module = "Converters::" . ucfirst lc $module_name;

eval {
    (my $file = $module) =~ s|::|/|g;
    require $file . '.pm';
    $module->import();
    1;
} or do {
    my $error = $@;
    Usage(1, "Error: failed to load converter module '$module_name'\n$error");
};

our $converter = $module->do_init();

my (%supported_types, %supported_types_str);
for (keys %{$converter->{'specs'}}) {
    $supported_types{'imp'}{$_}++;
    $supported_types{'exp'}{$converter->{'specs'}{$_}{'type_out'} // $_}++;
}
for ($converter->{'imptypes'} // ()) {
    $supported_types{'imp'}{$_}++;
}
for (qw/imp exp/) {
    $supported_types{$_}{'note'}++;
    $supported_types_str{$_} = join ' ', sort keys %{$supported_types{$_}};
}

our %opts = (
    outfile => join($^O eq 'MSWin32' ? '\\' : '/', $^O eq 'MSWin32' ? $ENV{'USERPROFILE'} : $ENV{'HOME'}, 'Desktop', '1P_import'),
    watchtower => 1,
    folders => 0,			# folder creation is disabled by default
); 

my @opt_config = (
    [ q{-a or --addfields          # add non-stock fields as custom fields },
       'addfields|a' ],
    [ q{-d or --debug              # enable debug output},
	'debug|d'	=> sub { debug_on() } ],
    [ q{-e or --exptypes <list>    # comma separated list of one or more export types from list below},
	'exptypes|e=s' ],
    [ q{-f or --folders            # create and assign items to folders},
	'folders|f' ],
    [ q{-h or --help               # output help and usage text},
	'help|h'	=> sub { Usage(0) } ],
    [ q{-i or --imptypes <list>    # comma separated list of one or more import types from list below},
	'imptypes|i=s' ],
    [ q{-o or --outfile <ofile>    # use file named ofile.1pif as the output file},
	'outfile|o=s' ],
    [ q{-t or --tags <list>        # add one or more comma-separated tags to the record},
       'tags|t=s' ],
    [ q{-v or --verbose            # output operations more verbosely},
	'verbose|v'	=> sub { verbose_on() } ],
    [ q{      --nowatchtower       # do not set creation date for logins to trigger Watchtower checks},
	'watchtower!'	=> sub { $opts{$_[0]} = $_[1] } ],
    [ q{},
	'testmode' ],		# for output file comparison testing
);

$show_full_usage_msg = 1;

{
    local $SIG{__WARN__} = sub { say "\n*** ", $_[0]; };
    Getopt::Long::Configure('no_ignore_case');
    GetOptions(\%opts, map {(@$_)[1..$#$_]} @opt_config, @{$converter->{'opts'}})
	or Usage(1);
}
debug "Command Line: @save_ARGV";
@ARGV >= 1 or Usage(1, "Missing export_text_file name - please specify the file to convert");

$opts{'outfile'} .= ".1pif"	if not $opts{'outfile'} =~ /\.1pif$/i;
debug "Output file: ", $opts{'outfile'};

for my $impexp (qw/imp exp/) {
    if (exists $opts{$impexp . 'types'}) {
	my %t;
	for (split /\s*,\s*/, $opts{$impexp . 'types'}) {
	    unless (exists $supported_types{$impexp}{$_}) {
		Usage(1, "Invalid --type argument '$_'; see supported types.");
	    }
	    $t{$_}++;
	}
	$opts{$impexp . 'types'} = \%t;
    }
}

-e $ARGV[0] or bail "The file '$ARGV[0]' does not exist.";

# debugging aid
print_fileinfo($ARGV[0])	if debug_enabled();

# import the wallet export data, and export the converted data
do_export( do_import(@ARGV > 1 ? \@ARGV : $ARGV[0], $opts{imptypes} // undef), $opts{'outfile'}, $opts{'exptypes'} // undef);

### end - functions below

sub Usage {
    my $exitcode = shift;

    local $,="\n";
    say @_;
    say "Usage: $progstr <converter> <options> <export_text_file>\n";
    say 'Select a converter:',  map(' ' x 4 . $_, flow(\@converters, 90));

    if (! $show_full_usage_msg) {
	say "\nSelect one of the converters above and add it to the command line to see more\ncomplete options.  Example:";
	say "\n\tperl convert_to_1p4.pl ewallet --help\n";
	exit $exitcode;
    }

    say '',
	'options:',
        map(' ' x 4 . $_->[0], sort {$a->[1] cmp $b->[1]} grep ($_->[0] ne '', @opt_config, @{$converter->{'opts'}})),
        '',
	'supported import types:',
	map(' ' x 4 . $_, flow($supported_types_str{'imp'}, 90)),
	'supported export types:',
	map(' ' x 4 . $_, flow($supported_types_str{'exp'}, 90));

    exit $exitcode;
}

1;
