#
# Copyright 2014 Mike Cappella (mike@cappella.us)

package Utils::Utils 1.03;

our @ISA	= qw(Exporter);
our @EXPORT	= qw(pluralize myjoin bail debug verbose debug_on verbose_on debug_enabled print_record summarize_import
		     unfold_and_chop flow hexdump fs_safe create_attachment slurp_file print_fileinfo);

use v5.14;
use utf8;
use strict;
use warnings;
use diagnostics;

use File::Basename;
use File::Spec;
use File::Path qw(make_path);

my ($verbose, $debug);

sub debug {
    return unless $debug;
    printf "%-20s: %s\n", (split(/::/, (caller(1))[3] || 'main'))[-1], join('', @_);
}

sub verbose {
    return unless $verbose;
    say @_;
}

sub debug_on      { $debug++; }
sub verbose_on    { $verbose++; }
sub debug_enabled { return $debug; }

sub bail {
    say @_, "\n";
    exit 1;
}

sub pluralize {
    return $_[0] . 's'	if $_[1] == 0 or $_[1] > 1;
    return $_[0];
}

sub summarize_import {
    my ($nouns, $n) = @_;
    my ($noun1, $noun2) = ref($nouns) eq 'ARRAY' ? @$nouns : ($nouns, $nouns);
    my $explode_summary = '';
    if ($Utils::Normalize::npre_explode) {
	$explode_summary = sprintf " (%s %s expanded to %d %s)", 
	    $Utils::Normalize::npre_explode,
	    pluralize($noun2, $Utils::Normalize::npre_explode),
	    $Utils::Normalize::npost_explode,
	    pluralize($noun2, $Utils::Normalize::npost_explode);
    }

    verbose "Imported $n ", pluralize($noun1, $n) . $explode_summary;
}

sub myjoin {
    my $sep = shift;
    my $ret = '';
    for (@_) {
	next if !defined $_ or $_ eq '';
	$ret .= ($ret eq '' ? '' : $sep )  . $_;
    }
    return $ret;
}

sub slurp_file {
    my ($file, $encoding) = @_;

    local $/;
    $encoding = ":encoding($encoding)"	 if $encoding and $encoding !~ /^:/;
    open my $fh, myjoin('', "<", $encoding), $file or
	bail "Unable to open file: $file\n$!";
    my $ret   = <$fh>;
    close $fh;
    return $ret;
}

sub print_fileinfo {
    my $file = shift;

    debug "Export file info";
    debug "\tsize: ", (stat($file))[7];
    if ($^O ne 'MSWin32') {
	my $s = qx(/usr/bin/file --brief    "$file");
	chomp $s;
	debug "\tkind: $s";
	$s = qx(/usr/bin/file --brief --mime "$file");
	chomp $s;
	debug "\tmime: $s";
    }
}

# Replace filesystem illegal/unsafe characters with underbar
sub fs_safe {
    local $_ = shift;
    s/[:\/\\*?"<>|]/_/g;		# replace FS-unsafe chars
    return $_;
}

my $attachdir;
sub create_attachment {
    my ($data, $dir, $filename, $title) = @_;

    $attachdir ||= File::Spec->catfile(dirname($main::opts{'outfile'}), '1P4_Attachments');

    if (!$dir) {
	$dir = File::Spec->catfile($attachdir, fs_safe($title));
	if (-e $dir) {
	    my $i;
	    for ($i = 1; $i <= 1000; $i++) {
		my $uniqdir = sprintf "%s (%d)", $dir, $i;
		next if -e $uniqdir;
		$dir = $uniqdir;
		last;
	    }
	    if ($i > 1000) {
		warn "Failed to create unique attachment directory: $dir\n$!";
		return;
	    }
	}
    }
    if (! -e $dir and ! make_path($dir)) {
	warn "Failed to create attachment directory: $dir\n$!";
	return;
    }
    $filename = File::Spec->catfile($dir, fs_safe($filename));
    if (! open FD, ">", $filename) {
	warn "Failed to create new file for attachment: $filename\n$!";
	return;;
    }
    print FD $$data;
    close FD;
    verbose "Attachment created: $filename";

    return $dir;
}

sub print_record {
    my $h = shift;

    return unless $debug;

    my $tags = (! defined $h->{'tags'}) ? '' : ref($h->{'tags'}) eq 'ARRAY' ? join('; ', @{$h->{'tags'}}) : $h->{'tags'};

    debug join "\n",
	"title: $h->{'title'}",
	' ' x 22 . "tags:  $tags",
	( map { ' ' x 22 . "key($_->{'outkey'}): $_->{'inkey'} = $_->{'value'}" } @{$h->{'fields'}} ), 
	' ' x 22 . "notes: " . unfold_and_chop($h->{'notes'} // '');
=cut
    for my $f (@{$h->{'fields'}}) {
	print "\t    key($f->{'outkey'}): $f->{'inkey'} = ";
	print "$_\n    "  for (ref($f->{'value'}) eq 'ARRAY' ? @{$f->{'value'}} : $f->{'value'});
    }
=cut
}

sub unfold_and_chop {
    local $_ = shift;
    my $maxlen = shift || 120;
    $maxlen -= 3;

    return undef if not defined $_;
    s/\R/<CR>/g;
    my $len = length $_;
    return $_ ? (substr($_, 0, $maxlen) . ($len > $maxlen ? '...' : '')) : '';
}

sub flow {
    my $maxlen = $_[1] || 80;
    my @lines = ('');
    foreach my $word (ref($_[0]) eq 'ARRAY' ? @{$_[0]} : split(/\s+/, $_[0])) {
	# assumes length(word) < maxlen
	if (length($word) + (@lines ? 1 + length($lines[-1]) : 0) >= $maxlen) {
	    push @lines, $word;
	    1;
	}
	else {
	    $lines[-1] .= ' ' 	if $lines[-1] ne '';
	    $lines[-1] .= $word;
	}
    }
    return @lines;
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

1;
