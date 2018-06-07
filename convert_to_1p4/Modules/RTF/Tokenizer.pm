#!perl
# RTF::Tokenizer - Peter Sergeant <pete@clueball.com>

=head1 NAME

RTF::Tokenizer - Tokenize RTF

=head1 VERSION

version 1.20

=head1 DESCRIPTION

Tokenizes RTF

=head1 SYNOPSIS

 use RTF::Tokenizer;

 # Create a tokenizer object
    my $tokenizer = RTF::Tokenizer->new();

    my $tokenizer = RTF::Tokenizer->new( string => '{\rtf1}'  );
    my $tokenizer = RTF::Tokenizer->new( string => '{\rtf1}', note_escapes => 1 );

    my $tokenizer = RTF::Tokenizer->new( file   => \*STDIN    );
    my $tokenizer = RTF::Tokenizer->new( file   => 'lala.rtf' );
    my $tokenizer = RTF::Tokenizer->new( file   => 'lala.rtf', sloppy => 1 );

 # Populate it from a file
    $tokenizer->read_file('filename.txt');

 # Or a file handle
    $tokenizer->read_file( \*STDIN );

 # Or a string
    $tokenizer->read_string( '{\*\some rtf}' );

 # Get the first token
    my ( $token_type, $argument, $parameter ) = $tokenizer->get_token();

 # Ooops, that was wrong...
    $tokenizer->put_token( 'control', 'b', 1 );

 # Let's have the lot...
    my @tokens = $tokenizer->get_all_tokens();

=head1 INTRODUCTION

This documentation assumes some basic knowledge of RTF.
If you lack that, go read The_RTF_Cookbook:

L<http://search.cpan.org/search?dist=RTF-Writer>

=cut

require 5;

package RTF::Tokenizer;
$RTF::Tokenizer::VERSION = '1.20';
use vars qw($VERSION);

use strict;
use warnings;
use Carp;
use IO::File;

=head1 METHODS

=head2 new()

Instantiates an RTF::Tokenizer object.

B<Named parameters>:

C<file> - calls the C<read_file> method with the value provided after instantiation

C<string> - calls the C<read_string> method with the value provided after instantiation

C<note_escapes> - boolean - whether to give RTF Escapes a token type of C<escape> (true) or
C<control> (false, default)

C<sloppy> - boolean - whether or not to allow some illegal but common RTF sequences found
'in the wild'. As of C<1.08>, this currently only allows control words with a numeric
argument to have a text field right after with no delimiter, like:

 \control1Plaintext

but this may change in future releases. Defaults false.

C<preserve_whitespace> - boolean - ... the RTF specification tells you to strip whitespace
which comes after control words, and newlines at the beginning and ending of text areas.
One result of that is that you can't actually round-trip the output of the tokenization
process. Turning this on is probably a bad idea, but someone cared enough to send me a
patch for it, so why not. Defaults false, and you should leave it that way.

=cut

sub new {
    # Get the real class name in the highly unlikely event we've been
    # called from an object itself.
    my $proto = shift;
    my $class = ref($proto) || $proto;

    # Read in the named parameters
    my %config = @_;

    my $self = {
        _BUFFER       => '',    # Stores read but unparsed RTF
        _BINARY_DATA  => '',    # Temporary data store if we're reading a \bin
        _FILEHANDLE   => '',    # Stores the active filehandle
        _INITIAL_READ => 512
        ,  # How many characters to read by default. 512 recommended by RTF spec
        _UC => 1,    # Default number of characters to count for \uc
    };

    bless $self, $class;

    # Call the data-reading convenience methods if required
    if ( $config{'file'} ) {
        $self->read_file( $config{'file'} );
    } elsif ( $config{'string'} ) {
        $self->read_string( $config{'string'} );
    }

    # Set up final config stuff
    $self->{_NOTE_ESCAPES} = $config{'note_escapes'};
    $self->{_SLOPPY}       = $config{'sloppy'};
    $self->{_WHITESPACE}   = $config{'preserve_whitespace'};

    return $self;

}

=head2 read_string( STRING )

Appends the string to the tokenizer-object's buffer
(earlier versions would over-write the buffer -
this version does not).

=cut

sub read_string {
    my $self = shift;
    $self->{_BUFFER} .= shift;
}

=head2 read_file( \*FILEHANDLE )

=head2 read_file( $IO_File_object )

=head2 read_file( 'filename' )

Appends a chunk of data from the filehandle to the buffer,
and remembers the filehandle, so if you ask for a token,
and the buffer is empty, it'll try and read the next line
from the file (earlier versions would over-write the buffer -
this version does not).

This chunk is 500 characters, and then whatever is left until
the next occurrence of the IRS (a newline character in this case).
If for whatever reason, you want to change that number to something
else, use C<initial_read>.

=cut

sub read_file {

    my $self = shift;
    my $file = shift;

    # Accept a filehandle referenced via a GLOB
    if ( ref $file eq 'GLOB' ) {
        $self->{_FILEHANDLE} = IO::File->new_from_fd( $file, '<' );
        croak
            "Couldn't create an IO::File object from the reference you specified"
            unless $self->{_FILEHANDLE};

        # Accept IO::File and subclassed objects
    } elsif (
        eval {
            $file->isa('IO::File');
        } )
    {
        $self->{_FILEHANDLE} = $file;

        # This is undocumented, because you shouldn't use it. Don't rely on it.
    } elsif ( ref $file eq 'IO::Scalar' ) {
        $self->{_FILEHANDLE} = $file;

        # If it's not a reference, assume it's a filename
    } elsif ( !ref $file ) {
        $self->{_FILEHANDLE} = IO::File->new("< $file");
        croak "Couldn't open '$file' for reading" unless $self->{_FILEHANDLE};

        # Complain if we get anything else
    } else {
        croak "You passed a reference to read_file of type " . ref($file) .
            " which isn't an allowed type";
    }

    # Check what our line-endings seem to be, then set $self->{_IRS} accordingly.
    # This also reads in the first few lines as a side effect.
    $self->_line_endings;
}

# Reads a line from an IO:File'ish object
sub _get_line {
    my $self = shift();

    # Localize the input record separator before changing it so
    # we don't mess up any other part of the application running
    # us that relies on it
    local $/ = $self->{_IRS};

    # Read the line itself
    my $line = $self->{_FILEHANDLE}->getline();
    $self->{_BUFFER} .= $line if defined $line;
}

# Determine what kind of line-endings the file uses

sub _line_endings {
    my $self = shift();

    my $temp_buffer;
    $self->{_FILEHANDLE}->read( $temp_buffer, $self->{_INITIAL_READ} );

    # This catches all allowed cases
    if ( $temp_buffer =~ m/(\cM\cJ|\cM|\cJ)/ ) {
        $self->{_IRS} = $1;

        $self->{_RS} = "Macintosh" if $self->{_IRS} eq "\cM";
        $self->{_RS} = "Windows"   if $self->{_IRS} eq "\cM\cJ";
        $self->{_RS} = "UNIX"      if $self->{_IRS} eq "\cJ";

    } else {
        $self->{_RS} = "Unknown";
    }

    # Add back to main buffer
    $self->{_BUFFER} .= $temp_buffer;

    # Call C<_get_line> again so we're sure we're not only
    # reading half a line
    $self->_get_line;

}

=head2 get_token()

Returns the next token as a three-item list: 'type', 'argument', 'parameter'.
Token is one of: C<text>, C<control>, C<group>, C<escape> or C<eof>.

If you turned on C<preserve_whitespace>, then you may get a forth item for
C<control> tokens.

=over

=item C<text>

'type' is set to 'text'. 'argument' is set to the text itself. 'parameter'
is left blank. NOTE: C<\{>, C<\}>, and C<\\> are all returned as control words,
rather than rendered as text for you, as are C<\_>, C<\-> and friends.

=item C<control>

'type' is 'control'. 'argument' is the control word or control symbol.
'parameter' is the control word's parameter if it has one - this will
be numeric, EXCEPT when 'argument' is a literal ', in which case it
will be a two-letter hex string.

If you turned on C<preserve_whitespace>, you'll get a forth item,
which will be the whitespace or a defined empty string.

=item C<group>

'type' is 'group'. If it's the beginning of an RTF group, then
'argument' is 1, else if it's the end, argument is 0. 'parameter'
is not set.

=item C<eof>

End of file reached. 'type' is 'eof'. 'argument' is 1. 'parameter' is
0.

=item C<escape>

If you specifically turn on this functionality, you'll get an
C<escape> type, which is identical to C<control>, only, it's
only returned for escapes.

=back

=cut

# Define a regular expression that matches characters which are 'text' -
# that is, they're not a backspace, a scoping brace, or discardable
# whitespace.
my $non_text_standard_re   = qr/[^\\{}\r\n]/;
my $non_text_whitespace_re = qr/[^\\{}]/;

sub get_token {
    my $self = shift;

    # If the last token we returned was \bin, we'll now have a
    # big chunk of binary data waiting for the user, so send that
    # back
    if ( $self->{_BINARY_DATA} ) {
        my $data = $self->{_BINARY_DATA};
        $self->{_BINARY_DATA} = '';
        return ( 'text', $data, '' );
    }

    # We might have a cached token, and if we do, we'll want to
    # return that first
    if ( $self->{_PUT_TOKEN_CACHE_FLAG} ) {
        # Take the value from the cache
        my @return_values = @{ pop( @{ $self->{_PUT_TOKEN_CACHE} } ) };

        # Update the flag
        $self->{_PUT_TOKEN_CACHE_FLAG} = @{ $self->{_PUT_TOKEN_CACHE} };

        # Give the user the token back
        return @return_values;
    }

    my $non_text_re =
        $self->{_WHITESPACE} ? $non_text_whitespace_re : $non_text_standard_re;

    # Our main parsing loop
    while (1) {

        my $start_character = substr( $self->{_BUFFER}, 0, 1, '' );

        # Most likely to be text, so we check for that first
        if ( $start_character =~ $non_text_re ) {
            no warnings 'uninitialized';

            # We want to return text fields that have newlines in as one
            # token, which requires a bit of work, as we read in one line
            # at a time from out files...
            my $temp_text = '';

        READTEXT:

            # Grab all the next 'text' characters
            $self->{_BUFFER} =~ s/^([^\\{}]+)//s;
            $temp_text .= $1 if defined $1;

            # If the buffer is empty, try reading in some more, and
            # then go back to READTEXT to keep going. Now, the clever
            # thing would be to assume that if the buffer *IS* empty
            # then there MUST be more to read, which is true if we
            # have well-formed input. We're going to assume that the
            # input could well be a little broken.
            if ( ( !$self->{_BUFFER} ) && ( $self->{_FILEHANDLE} ) ) {
                $self->_get_line;
                goto READTEXT if $self->{_BUFFER};
            }

            # Make sure we're not including newlines in our output,
            # as RTF spec says they're to be ignored...
            unless ( $self->{_WHITESPACE} ) {
                $temp_text =~ s/(\cM\cJ|\cM|\cJ)//g;
            }

            # Give the user a shiny token back
            return ( 'text', $start_character . $temp_text, '' );

            # Second most likely to be a control character
        } elsif ( $start_character eq "\\" ) {
            my @args = $self->_grab_control();

            # If the control word was an escape, and the user
            # asked to be told separately about those, this
            # will be set, so return an 'escape'. Otherwise,
            # return the control word as a 'control'
            if ( $self->{_TEMP_ESCAPE_FLAG} ) {
                $self->{_TEMP_ESCAPE_FLAG} = 0;
                return ( 'escape', @args );
            } else {
                return ( 'control', @args );
            }

            # Probably a group then
        } elsif ( $start_character eq '{' ) {
            return ( 'group', 1, '' );
        } elsif ( $start_character eq '}' ) {
            return ( 'group', 0, '' );

            # No start character? Either we're at the end of our input,
            # or we need some new input
        } elsif ( !$start_character ) {
            # If we were read from a string, we're all done
            return ( 'eof', 1, 0 ) unless $self->{_FILEHANDLE};

            # If we were read from a file, try and get some more stuff
            # in to the buffer, or return the 'eof' character
            return ( 'eof', 1, 0 ) if $self->{_FILEHANDLE}->eof;
            $self->_get_line;
            return ( 'eof', 1, 0 ) unless $self->{_BUFFER};
        }
    }
}

=head2 get_all_tokens

As per C<get_token>, but keeps calling C<get_token> until it hits EOF. Returns
a list of arrayrefs.

=cut

sub get_all_tokens {
    my $self = shift;
    my @tokens;

    while (1) {
        my $token = [ $self->get_token() ];
        push( @tokens, $token );
        last if $token->[0] eq 'eof';
    }

    return @tokens;
}

=head2 put_token( type, token, argument )

Adds an item to the token cache, so that the next time you
call get_token, the arguments you passed here will be returned.
We don't check any of the values, so use this carefully. This
is on a first in last out basis.

=cut

sub put_token {
    my $self = shift;

    push( @{ $self->{_PUT_TOKEN_CACHE} }, [@_] );

    # No need to set this to the real value of the token cache, as
    # it'll get set properly when we try and read a cached token.
    $self->{_PUT_TOKEN_CACHE_FLAG} = 1;
}

=head2 sloppy( [bool] )

Decides whether we allow some types of broken RTF. See C<new()>'s docs
for a little more explanation about this. Pass it 1 to turn it on, 0 to
turn it off. This will always return undef.

=cut

sub sloppy {
    my $self = shift;
    my $bool = shift;

    if ($bool) {
        $self->{_SLOPPY} = 1;
    } else {
        $self->{_SLOPPY} = 0;
    }

    return;
}

=head2 initial_read( [number] )

Don't call this unless you actually have a good reason. When
the Tokenizer reads from a file, it first attempts to work out
what the correct input record-seperator should be, by reading
some characters from the file handle. This value starts off
as 512, which is twice the amount of characters that version 1.7
of the RTF specification says you should go before including a
line feed if you're writing RTF.

Called with no argument, this returns the current value of the
number of characters we're going to read. Called with a numeric
argument, it sets the number of characters we'll read.

You really don't need to use this method.

=cut

sub initial_read {
    my $self = shift;
    if (@_) { $self->{_INITIAL_READ} = shift }
    return $self->{_INITIAL_READ};
}

=head2 debug( [number] )

Returns (non-destructively) the next 50 characters from the buffer,
OR, the number of characters you specify. Printing these to STDERR,
causing fatal errors, and the like, are left as an exercise to the
programmer.

Note the part about 'from the buffer'. It really means that, which means
if there's nothing in the buffer, but still stuff we're reading from a
file it won't be shown. Chances are, if you're using this function, you're
debugging. There's an internal method called C<_get_line>, which is called
without arguments (C<$self->_get_line()>) that's how we get more stuff into
the buffer when we're reading from filehandles. There's no guarentee that'll
stay, or will always work that way, but, if you're debugging, that shouldn't
matter.

=cut

sub debug {
    my $self = shift;
    my $number = shift || 50;

    return substr( $self->{_BUFFER}, 0, $number );
}

# Work with control characters

# It's ugly to repeat myself here, but I believe having two literal re's
# here is going to offer a small performance benefit over a regex with
# a scalar in it.
my $control_word_standard_re = qr/
            ^([a-z]{1,32})          # Lowercase word
            (-?\d+)?                # Optional signed number
            (?:\s|(?=[^a-z0-9]))    # Either whitespace, which we gobble or a
                                    # non alpha-numeric, which we leave
            /ix;
my $control_word_whitespace_re = qr/
            ^([a-z]{1,32})          # Lowercase word
            (-?\d+)?                # Optional signed number
            (\s*)?                  # Capture trailing whitespace
            /ix;

sub _grab_control {
    my $self = shift;

    my $whitespace_re =
        $self->{_WHITESPACE} ? $control_word_whitespace_re :
        $control_word_standard_re;

    # Check for a star here, as it simplifies our regex below,
    # and it occurs pretty often
    if ( $self->{_BUFFER} =~ s/^\*// ) {
        return ( '*', '' );

        # A standard control word:
    } elsif ( $self->{_BUFFER} =~ s/$whitespace_re// ) {
        # Return the control word, unless it's a \bin
        my $param = '';
        $param = $2 if defined($2);

        my @whitespace;
        if ( $self->{_WHITESPACE} ) {
            push( @whitespace, defined $3 ? $3 : '' );
        }

        return ( $1, $param, @whitespace ) unless $1 eq 'bin';

        # Pre-grab the binary data, and return the control word
        my $byte_count = $2;
        $self->_grab_bin($byte_count);
        return ( 'bin', $byte_count, @whitespace );

        # hex-dec character (escape)
    } elsif ( $self->{_BUFFER} =~ s/^'([0-9a-f]{2})//i ) {
        $self->{_TEMP_ESCAPE_FLAG}++ if $self->{_NOTE_ESCAPES};
        return ( "'", $1 );

        # Control symbol (escape)
    } elsif ( $self->{_BUFFER} =~ s/^([-_~:|{}'\\])// ) {
        $self->{_TEMP_ESCAPE_FLAG}++ if $self->{_NOTE_ESCAPES};
        return ( $1, '' );

        # Escaped whitespace (ew, but allowed)
    } elsif ( $self->{_BUFFER} =~ s/^[\r\n]// ) {
        return ( 'par', '' );

        # Escaped tab (ew, but allowed)
    } elsif ( $self->{_BUFFER} =~ s/^\t// ) {
        return ( 'tab', '' );

        # Escaped semi-colon - this is WRONG
    } elsif ( $self->{_BUFFER} =~ s/^\;// ) {
        carp(
            "Your RTF contains an escaped semi-colon. This isn't allowed, but we'll let you have it back as a literal for now. See the RTF spec."
        );
        return ( ';', '' );

        # Unicode characters
    } elsif ( $self->{_BUFFER} =~ s/^u(\d+)// ) {
        return ( 'u', $1 );

        # Allow incorrect control words
    } elsif ( ( $self->{_SLOPPY} ) &&
        ( $self->{_BUFFER} =~ s/^([a-z]{1,32})(-?\d+)//i ) )
    {
        my $param = '';
        $param = $2 if defined($2);

        return ( $1, $param );
    }

    # If we get here, something has gone wrong. First we'll create
    # a human readable section of RTF to show the user.
    my $die_string = substr( $self->{_BUFFER}, 0, 50 );
    $die_string =~ s/\r/[R]/g;

    # Get angry with the user
    carp
        "Your RTF is broken, trying to recover to nearest group from '\\$die_string'\n";
    carp
        "Chances are you have some RTF like \\control1plaintext. Which is illegal. But you can allow that by passing the 'sloppy' attribute to new() or using the sloppy() method. Please also write to and abuse the developer of the software which wrote your RTF :-)\n";

    # Kill everything until the next group
    $self->{_BUFFER} =~ s/^.+?([}{])/$1/;
    return ( '', '' );
}

# A first stab at grabbing binary data
sub _grab_bin {
    my $self  = shift;
    my $bytes = shift;

    # If the buffer is too small, attempt to read in some more data...
    while ( length( $self->{_BUFFER} ) < $bytes ) {

        # If there's no filehandle, or the one we have is eof, complain
        if ( !$self->{_FILEHANDLE} || $self->{_FILEHANDLE}->eof ) {
            croak "\\bin is asking for $bytes characters, but there are only " .
                length( $self->{_BUFFER} ) . " left.";
        }

        # Try and read in more data
        $self->_get_line;
    }

    # Return the right number of characters
    $self->{_BINARY_DATA} = substr( $self->{_BUFFER}, 0, $bytes, '' );
}

=head1 NOTES

To avoid intrusively deep parsing, if an alternative ASCII
representation is available for a Unicode entity, and that
ASCII representation contains C<{>, or C<\>, by themselves, things
will go I<funky>. But I'm not convinced either of those is
allowed by the spec.

=head1 AUTHOR

Pete Sergeant -- C<pete@clueball.com>

=head1 LICENSE

Copyright B<Pete Sergeant>.

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;
