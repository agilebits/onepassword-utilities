# Yojimbo files export converter
#
# Copyright 2017 Mike Cappella (mike@cappella.us)

package Converters::Yojimbo 1.00;

our @ISA 	= qw(Exporter);
our @EXPORT     = qw(do_init do_import do_export);
our @EXPORT_OK  = qw();

use v5.14;
use utf8;
use strict;
use warnings;
#use diagnostics;

binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

use Utils::PIF;
use Utils::Utils;
use Utils::Normalize;
use Encode;
use RTF::Tokenizer;
use Unicode::Normalize;

my %card_field_specs = (
    bookmark =>                 { textname => undef, type_out => 'note', fields => [
	[ 'url',		1, qr/^URL$/, ],
    ]},
    password =>                 { textname => undef, type_out => 'login', fields => [
	[ 'url',		1, qr/^Location$/, ],
        [ 'username',		1, qr/^Account$/, ],
        [ 'password',		1, qr/^Password$/, ],
    ]},
    serialnumber =>             { textname => undef, type_out => 'software', fields => [
	[ 'reg_name',		1, qr/^Owner Name$/, ],
	[ 'reg_email',		1, qr/^Email Address$/, ],
	[ 'company',		1, qr/^Organization$/, ],
	[ 'reg_code',		1, qr/^Serial Number$/, ],
    ]},
    webarchive =>               { textname => undef, type_out => 'note', fields => [
	[ 'url',		1, qr/^URL$/, ],
    ]},
);

$DB::single = 1;					# triggers breakpoint when debugging

sub do_init {
    return {
	'specs'		=> \%card_field_specs,
	'imptypes'  	=> undef,
	'opts'		=> [
	      		     [ q{      --serial2note        # serial numbers go to note instead of software},
			       'serial2note' ],
			   ],
    };
}

sub do_import {
    my ($dir, $imptypes) = @_;
    my %Cards;

    if ($main::opts{'serial2note'}) {
	$card_field_specs{'serialnumber'}{'type_out'} = 'note';
    }

    opendir(my $dh, $dir) or
	bail "Can't open directory $dir: $!";

    my $n = 1;
    my $ignored = 0;
    while (readdir $dh) {
	my (%cmeta, @fieldlist);
	my $f = $_;
	next if $f =~ /^\./;

	$n++;

	my $file = join '/', $dir, $f;
	debug "$file";

	my $itype = get_cmeta_from_file($file, $f, \%cmeta, \@fieldlist);

	if (not defined $itype) {
	    $ignored++;
	    next;
	}

	# skip all types not specifically included in a supplied import types list
	next if defined $imptypes and (! exists $imptypes->{$itype});

	$cmeta{'title'} //= NFC(Encode::decode_utf8($f =~ s/\.\w+$//r));

	my @lines = do_safe_shell_command('stat', '-f', '%m %B', $file);
	chomp $lines[0];
	my ($date_modified, $date_created) = split / /, $lines[0];
	if ($main::opts{'notimestamps'}) {
            push @fieldlist, [ 'Date Modified', scalar localtime $date_modified];
	    push @fieldlist, [ 'File Created',  scalar localtime $date_created];
        }
        else {
            $cmeta{'modified'} = $date_modified;
	    $cmeta{'created'}  = $date_created;
        }

	my $normalized = normalize_card_data(\%card_field_specs, $itype, \@fieldlist, \%cmeta);
	my $cardlist   = explode_normalized($itype, $normalized);

	for (keys %$cardlist) {
	    print_record($cardlist->{$_});
	    push @{$Cards{$_}}, $cardlist->{$_};
	}
    }
    closedir $dh;

    summarize_import('file', $n - 1);
    verbose "Ignored $ignored ", pluralize('file', $ignored)		if $ignored;

    return \%Cards;
}

sub do_export {
    add_custom_fields(\%card_field_specs);
    create_pif_file(@_);
}

sub get_cmeta_from_file {
    my ($file, $f, $cmeta, $fieldlist) = @_;

    my $type;

    # Bookmarks
    if ($f =~ /\.(?:web|inet)loc$/) {
	$type = 'bookmark';
	$_ = slurp_file($file, 'utf8');
	while (s/<key>(.+?)<\/key>\s+<string>(.+?)<\/string>//ms) {
	    next if $1 eq 'urln';
	    if ($1 eq 'public.url-name') {
		$cmeta->{'title'} = $2;
	    }
	    else {
		push @$fieldlist, [ $1 => $2 ]			if defined $2 and $2 ne '';
	    }
	}
    }

    # Note, Password, and Serial Number
    elsif ($f =~ /\.txt$/) {
	$_ = slurp_file($file, 'utf8');
	chomp $_;
	if (my @x = ($_ =~ /^(Name):\s*(.*)\n(Location):\s*(.*)\n^(Account):\s*(.*)\n^(Password):\s*(.*)\n^(Comments):\s*(.*)\Z/ms)) {
	    $type = 'password';
	    while (@x) {
		my ($key, $value) = (shift @x, shift @x);
		if ($key eq 'Name') {
		    $cmeta->{'title'} = $value;
		}
		elsif ($key eq 'Comments') {
		    $cmeta->{'notes'} = $value;
		}
		else {
		    push @$fieldlist, [ $key => $value ]	if defined $value and $value ne '';
		}
	    }
	}
	elsif (@x = ($_ =~ /^(Product Name):\s*(.*)\n^(Owner Name):\s*(.*)\n^(Email Address):\s*(.*)\n^(Organization):\s*(.*)\n^(Serial Number):\s*(.*)\n^(Comments):\s*(.*)\Z/ms)) {
	    $type = 'serialnumber';
	    while (@x) {
		my ($key, $value) = (shift @x, shift @x);
		if ($key eq 'Product Name') {
		    $cmeta->{'title'} = $value;
		}
		elsif ($key eq 'Comments') {
		    $cmeta->{'notes'} = $value;
		}
		else {
		    push @$fieldlist, [ $key => $value ]	if defined $value and $value ne ''; 
		}
	    }
	}
	else {
	    $type = 'note';
	    $cmeta->{'notes'} = slurp_file($file, 'utf8');
	}
    }

    # Formatted Notes (RTF)
    elsif ($f =~ /\.rtf$/) {
	$type = 'note';
	my $rtfnote = slurp_file($file);
	$cmeta->{'notes'} = rtf_decode($rtfnote);
    }
    elsif ($f =~ /\.webarchive$/) {
	$type = 'webarchive';
	my @lines = do_safe_shell_command('plutil', '-p', $file);
	my $value;
TOP:
	while (@lines) {
	    $_ = shift @lines;
	    next unless /"WebMainResource" => \{/;
	    while ($_ = shift @lines) {
		next unless /"WebResourceURL" => "([^"]+)"/;
		$value = $1;
		last TOP;
	    }
	}

	push @$fieldlist, [ 'URL' => $value ]		if defined $value and $value ne ''; 
	push @$fieldlist, [ 'Original File' => $file ];
	$cmeta->{'notes'} = "This entry is only a partial import.  See Origial File above.";
    }
    else {
	verbose "- ignoring unsupported file format: $file";
	return undef;
    }

    debug "  type: $type";
    debug "    field: $_->[0] = $_->[1]"		for @$fieldlist;

    return $type;
}

# cheap RTF to Text converter.
#
sub rtf_decode {
    return $_[0] unless $_[0] =~ /^{\\rtf1\\/;			# some notes are not in RTF format

    my $tokenizer = RTF::Tokenizer->new('note_escapes' => 1);
    $tokenizer->read_string($_[0]);
    my @tokens = $tokenizer->get_all_tokens();

    my $ret;
    my $paragraph;
    while (@tokens) {
	my $token = shift @tokens;

	if ($paragraph) {
	    if ($token->[0] eq 'control' and $token->[1] eq 'par') {
		$ret .= "\n";
		next;
	    }
	    elsif ($token->[0] eq 'text') {
		$ret .= $token->[1];
	    }
	    elsif ($token->[0] eq 'escape') {
		if ($token->[1] eq "'") {
		    my $char = encode('UTF-8', pack('H*', $token->[2]));
		    Encode::_utf8_on($char);
		    $ret .= $char;
		}
	    }
	    elsif ($token->[0] eq 'control') {
		if ($token->[1] eq "u") {
		    $ret .= pack('U', $token->[2]);
		    # a Unicode number will have a terminating '?', which may be combined with subsequent text
		    if ($tokens[0][0] eq 'text' and $tokens[0][1] =~ /^[?](.*)$/) {
			$ret .= $1;
			shift @tokens;
		    }
		}
	    }
	}

	if ($token->[0] eq 'control' and $token->[1] eq 'pard') {
	    $paragraph++;
	    next;
	}
    }
    return $ret;
}

1;
