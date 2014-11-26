#
# Copyright 2014 Mike Cappella (mike@cappella.us)

package Utils::Utils 1.02;

our @ISA	= qw(Exporter);
our @EXPORT	= qw();
our @EXPORT_OK	= qw(pluralize myjoin bail debug verbose debug_on verbose_on print_record unfold_and_chop flow hexdump);

use v5.14;
use utf8;
use strict;
use warnings;
use diagnostics;

my ($verbose, $debug);

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

sub bail {
    say @_, "\n";
    exit 1;
}

sub pluralize {
    return ($_[0] > 1 || $_[0] == 0) ? 's' : '';
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

sub print_record {
    my $h = shift;

    return unless $debug;

    my $tags = (! defined $h->{'tags'}) ? '' : ref($h->{'tags'}) eq 'ARRAY' ? join('; ', @{$h->{'tags'}}) : $h->{'tags'};

    debug join "\n",
	"title: $h->{'title'}",
	' ' x 22 . "tags:  $tags",
	map { ' ' x 22 . "key($_->{'outkey'}): $_->{'inkey'} = $_->{'value'}" } @{$h->{'fields'}};

=cut
    for my $f (@{$h->{'fields'}}) {
	print "\t    key($f->{'outkey'}): $f->{'inkey'} = ";
	print "$_\n    "  for (ref($f->{'value'}) eq 'ARRAY' ? @{$f->{'value'}} : $f->{'value'});
    }
=cut
}

sub unfold_and_chop {
    local $_ = shift;
    my $maxlen = shift || 80;

    return undef if not defined $_;
    s/\R/<CR>/g;
    my $len = length $_;
    return $_ ? (substr($_, 0, 77) . ($len > 77 ? '...' : '')) : '';
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
