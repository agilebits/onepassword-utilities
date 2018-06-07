use strict;
use warnings;

package PBKDF2::Tiny;
# ABSTRACT: Minimalist PBKDF2 (RFC 2898) with HMAC-SHA1 or HMAC-SHA2

our $VERSION = '0.005';

use Carp ();
use Exporter 5.57 qw/import/;

our @EXPORT_OK = qw/derive derive_hex verify verify_hex hmac digest_fcn/;

my ( $BACKEND, $LOAD_ERR );
for my $mod (qw/Digest::SHA Digest::SHA::PurePerl/) {
    $BACKEND = $mod, last if eval "require $mod; 1";
    $LOAD_ERR ||= $@;
}
die $LOAD_ERR if !$BACKEND;

#--------------------------------------------------------------------------#
# constants and lookup tables
#--------------------------------------------------------------------------#

# function coderef placeholder, block size in bytes, digest size in bytes
my %DIGEST_TYPES = (
    'SHA-1'   => [ undef, 64,  20 ],
    'SHA-224' => [ undef, 64,  28 ],
    'SHA-256' => [ undef, 64,  32 ],
    'SHA-384' => [ undef, 128, 48 ],
    'SHA-512' => [ undef, 128, 64 ],
);

for my $type ( keys %DIGEST_TYPES ) {
    no strict 'refs';
    ( my $name = lc $type ) =~ s{-}{};
    $DIGEST_TYPES{$type}[0] = \&{"$BACKEND\::$name"};
}

my %INT = map { $_ => pack( "N", $_ ) } 1 .. 16;

#--------------------------------------------------------------------------#
# public functions
#--------------------------------------------------------------------------#

#pod =func derive
#pod
#pod     $dk = derive( $type, $password, $salt, $iterations, $dk_length )
#pod
#pod The C<derive> function outputs a binary string with the derived key.
#pod The first argument indicates the digest function to use.  It must be one
#pod of: SHA-1, SHA-224, SHA-256, SHA-384, or SHA-512.
#pod
#pod If a password or salt are not provided, they default to the empty string, so
#pod don't do that!  L<RFC 2898
#pod recommends|https://tools.ietf.org/html/rfc2898#section-4.1> a random salt of at
#pod least 8 octets.  If you need a cryptographically strong salt, consider
#pod L<Crypt::URandom>.
#pod
#pod The password and salt should encoded as octet strings. If not (i.e. if
#pod Perl's internal 'UTF8' flag is on), then an exception will be thrown.
#pod
#pod The number of iterations defaults to 1000 if not provided.  If the derived
#pod key length is not provided, it defaults to the output size of the digest
#pod function.
#pod
#pod =cut

sub derive {
    my ( $type, $passwd, $salt, $iterations, $dk_length ) = @_;

    my ( $digester, $block_size, $digest_length ) = digest_fcn($type);

    $passwd = '' unless defined $passwd;
    $salt   = '' unless defined $salt;
    $iterations ||= 1000;
    $dk_length  ||= $digest_length;

    # we insist on octet strings for password and salt
    Carp::croak("password must be an octet string, not a character string")
      if utf8::is_utf8($passwd);
    Carp::croak("salt must be an octet string, not a character string")
      if utf8::is_utf8($salt);

    my $key = ( length($passwd) > $block_size ) ? $digester->($passwd) : $passwd;
    my $passes = int( $dk_length / $digest_length );
    $passes++ if $dk_length % $digest_length; # need part of an extra pass

    my $dk = "";
    for my $i ( 1 .. $passes ) {
        $INT{$i} ||= pack( "N", $i );
        my $digest = my $result =
          "" . hmac( $salt . $INT{$i}, $key, $digester, $block_size );
        for my $iter ( 2 .. $iterations ) {
            $digest = hmac( $digest, $key, $digester, $block_size );
            $result ^= $digest;
        }
        $dk .= $result;
    }

    return substr( $dk, 0, $dk_length );
}

#pod =func derive_hex
#pod
#pod Works just like L</derive> but outputs a hex string.
#pod
#pod =cut

sub derive_hex { unpack( "H*", &derive ) }

#pod =func verify
#pod
#pod     $bool = verify( $dk, $type, $password, $salt, $iterations, $dk_length );
#pod
#pod The C<verify> function checks that a given derived key (in binary form) matches
#pod the password and other parameters provided using a constant-time comparison
#pod function.
#pod
#pod The first parameter is the derived key to check.  The remaining parameters
#pod are the same as for L</derive>.
#pod
#pod =cut

sub verify {
    my ( $dk1, @derive_args ) = @_;

    my $dk2 = derive(@derive_args);

    # shortcut if input dk is the wrong length entirely; this is not
    # constant time, but this doesn't really give much away as
    # the keys are of different types anyway

    return unless length($dk1) == length($dk2);

    # if lengths match, do constant time comparison to avoid timing attacks
    my $match = 1;
    for my $i ( 0 .. length($dk1) - 1 ) {
        $match &= ( substr( $dk1, $i, 1 ) eq substr( $dk2, $i, 1 ) ) ? 1 : 0;
    }

    return $match;
}

#pod =func verify_hex
#pod
#pod Works just like L</verify> but the derived key must be a hex string (without a
#pod leading "0x").
#pod
#pod =cut

sub verify_hex {
    my $dk = pack( "H*", shift );
    return verify( $dk, @_ );
}

#pod =func digest_fcn
#pod
#pod     ($fcn, $block_size, $digest_length) = digest_fcn('SHA-1');
#pod     $digest = $fcn->($data);
#pod
#pod This function is used internally by PBKDF2::Tiny, but made available in case
#pod it's useful to someone.
#pod
#pod Given one of the valid digest types, it returns a function reference that
#pod digests a string of data. It also returns block size and digest length for that
#pod digest type.
#pod
#pod =cut

sub digest_fcn {
    my ($type) = @_;

    Carp::croak("Digest function '$type' not supported")
      unless exists $DIGEST_TYPES{$type};

    return @{ $DIGEST_TYPES{$type} };
}

#pod =func hmac
#pod
#pod     $key = $digest_fcn->($key) if length($key) > $block_size;
#pod     $hmac = hmac( $data, $key, $digest_fcn, $block_size );
#pod
#pod This function is used internally by PBKDF2::Tiny, but made available in case
#pod it's useful to someone.
#pod
#pod The first two arguments are the data and key inputs to the HMAC function.  Both
#pod should be encoded as octet strings, as underlying HMAC/digest functions may
#pod croak or may give unexpected results if Perl's internal UTF-8 flag is on.
#pod
#pod B<Note>: if the key is longer than the digest block size, it must be
#pod preprocessed using the digesting function.
#pod
#pod The third and fourth arguments must be a digesting code reference (from
#pod L</digest_fcn>) and block size.
#pod
#pod =cut

# hmac function adapted from Digest::HMAC by Graham Barr and Gisle Aas.
# Compared to that implementation, this *requires* a preprocessed
# key and block size, which makes iterative hmac slightly more efficient.
sub hmac {
    my ( $data, $key, $digest_func, $block_size ) = @_;

    my $k_ipad = $key ^ ( chr(0x36) x $block_size );
    my $k_opad = $key ^ ( chr(0x5c) x $block_size );

    &$digest_func( $k_opad, &$digest_func( $k_ipad, $data ) );
}

1;


# vim: ts=4 sts=4 sw=4 et:

__END__

=pod

=encoding UTF-8

=head1 NAME

PBKDF2::Tiny - Minimalist PBKDF2 (RFC 2898) with HMAC-SHA1 or HMAC-SHA2

=head1 VERSION

version 0.005

=head1 SYNOPSIS

    use PBKDF2::Tiny qw/derive verify/;

    my $dk = derive( 'SHA-1', $pass, $salt, $iters );

    if ( verify( $dk, 'SHA-1', $pass, $salt, $iters ) ) {
        # password is correct
    }

=head1 DESCRIPTION

This module provides an L<RFC 2898|https://tools.ietf.org/html/rfc2898>
compliant PBKDF2 implementation using HMAC-SHA1 or HMAC-SHA2 in under 100 lines
of code.  If you are using Perl 5.10 or later, it uses only core Perl modules.
If you are on an earlier version of Perl, you need L<Digest::SHA> or
L<Digest::SHA::PurePerl>.

All documented functions are optionally exported.  No functions are exported by default.

=head1 FUNCTIONS

=head2 derive

    $dk = derive( $type, $password, $salt, $iterations, $dk_length )

The C<derive> function outputs a binary string with the derived key.
The first argument indicates the digest function to use.  It must be one
of: SHA-1, SHA-224, SHA-256, SHA-384, or SHA-512.

If a password or salt are not provided, they default to the empty string, so
don't do that!  L<RFC 2898
recommends|https://tools.ietf.org/html/rfc2898#section-4.1> a random salt of at
least 8 octets.  If you need a cryptographically strong salt, consider
L<Crypt::URandom>.

The password and salt should encoded as octet strings. If not (i.e. if
Perl's internal 'UTF8' flag is on), then an exception will be thrown.

The number of iterations defaults to 1000 if not provided.  If the derived
key length is not provided, it defaults to the output size of the digest
function.

=head2 derive_hex

Works just like L</derive> but outputs a hex string.

=head2 verify

    $bool = verify( $dk, $type, $password, $salt, $iterations, $dk_length );

The C<verify> function checks that a given derived key (in binary form) matches
the password and other parameters provided using a constant-time comparison
function.

The first parameter is the derived key to check.  The remaining parameters
are the same as for L</derive>.

=head2 verify_hex

Works just like L</verify> but the derived key must be a hex string (without a
leading "0x").

=head2 digest_fcn

    ($fcn, $block_size, $digest_length) = digest_fcn('SHA-1');
    $digest = $fcn->($data);

This function is used internally by PBKDF2::Tiny, but made available in case
it's useful to someone.

Given one of the valid digest types, it returns a function reference that
digests a string of data. It also returns block size and digest length for that
digest type.

=head2 hmac

    $key = $digest_fcn->($key) if length($key) > $block_size;
    $hmac = hmac( $data, $key, $digest_fcn, $block_size );

This function is used internally by PBKDF2::Tiny, but made available in case
it's useful to someone.

The first two arguments are the data and key inputs to the HMAC function.  Both
should be encoded as octet strings, as underlying HMAC/digest functions may
croak or may give unexpected results if Perl's internal UTF-8 flag is on.

B<Note>: if the key is longer than the digest block size, it must be
preprocessed using the digesting function.

The third and fourth arguments must be a digesting code reference (from
L</digest_fcn>) and block size.

=begin Pod::Coverage




=end Pod::Coverage

=head1 SEE ALSO

=over 4

=item *

L<Crypt::PBKDF2>

=item *

L<Digest::PBDKF2>

=back

=for :stopwords cpan testmatrix url annocpan anno bugtracker rt cpants kwalitee diff irc mailto metadata placeholders metacpan

=head1 SUPPORT

=head2 Bugs / Feature Requests

Please report any bugs or feature requests through the issue tracker
at L<https://github.com/dagolden/PBKDF2-Tiny/issues>.
You will be notified automatically of any progress on your issue.

=head2 Source Code

This is open source software.  The code repository is available for
public review and contribution under the terms of the license.

L<https://github.com/dagolden/PBKDF2-Tiny>

  git clone https://github.com/dagolden/PBKDF2-Tiny.git

=head1 AUTHOR

David Golden <dagolden@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2014 by David Golden.

This is free software, licensed under:

  The Apache License, Version 2.0, January 2004

=cut
