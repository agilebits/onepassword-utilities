# PasswordWallet CSV export converter
#
# Copyright 2015 Mike Cappella (mike@cappella.us)

package Converters::Passwordwallet 1.02;

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

use Text::CSV;

my %card_field_specs = (
    login =>			{ textname => '', fields => [
	[ 'title',		0, qr/^title$/, ],
	[ 'username',		0, qr/^username$/, ],
	[ 'password',		0, qr/^password$/, ],
	[ 'url',		0, qr/^url$/, ],
	[ 'notes',		0, qr/^notes$/, ],
    ]},
    note =>			{ textname => '', fields => [
    ]},
);

$DB::single = 1;					# triggers breakpoint when debugging

sub do_init {
    return {
	'specs'		=> \%card_field_specs,
	'imptypes'  	=> undef,
        'opts'          => [],
    }
}

sub do_import {
    my ($file, $imptypes) = @_;

    my $csv = Text::CSV->new ({
	    binary => 1,
	    allow_loose_quotes => 1,
	    sep_char => "\t",
	    eol => "\n",
    });

    open my $io, $^O eq 'MSWin32' ? "<:encoding(utf16LE)" : "<:encoding(utf8)", $file
	or bail "Unable to open CSV file: $file\n$!";

    my %Cards;
    my ($n, $rownum) = (1, 1);

    $csv->column_names(qw/title url username password notes category browser unused1 unused2/);
    while (my $row = $csv->getline_hr($io)) {
	debug 'ROW: ', $rownum++;

	my $itype = find_card_type($row);
	next if defined $imptypes and (! exists $imptypes->{$itype});

	my (%cmeta, @fieldlist);

	# Grab the special fields and delete them from the row
	@cmeta{qw/title notes tags/} = @$row{qw/title notes category/};
	delete @$row{qw/title notes category/};
	$cmeta{'notes'} =~ s/\x{00AC}/\n/g;		# translate encoded newline: ¬ Unicode: U+00AC, UTF-8: C2 AC

	# handle the special auto-type characters in username and password
	#
	# • Unicode: U+2022, UTF-8: E2 80 A2		pass,user: tab to next field
	# ¶ Unicode: U+00B6, UTF-8: C2 B6		pass,user: carriage return, does auto-submit
	# § Unicode: U+00A7, UTF-8: C2 A7		pass,user: adds delay
	# ∞ Unicode: U+221E, UTF-8: E2 88 9E		pass,user: pause/resume auto-type
	# « Unicode: U+00AB, UTF-8: C2 AB		pass,user: reverse tab
	#
	# pass through - referent Title may not be unique
	# [:OtherEntryName:]				pass,login: uses value from the named entry
	#
	for (qw/username password/) {
	    next unless $row->{$_} =~ /[\x{2022}\x{00B6}\x{00A7}\x{221E}\x{00AB}]/;

	    $row->{$_} =~ s/(?:\x{00A7}|\x{221E})//g;				# strip globally: delay, pause/resume
	    $row->{$_} =~ s/(?:\x{2022}|\x{00B6}|\x{00AB})+$//;			# strip from end: tab/reverse tab, auto-submit
	    $row->{$_} =~ s/^(?:\x{2022}|\x{00B6}|\x{00AB})+//;			# strip from beginning: tab/reverse tab, auto-submit

	    if ($row->{$_} =~ s/^(.+?)(?:\x{2022}|\x{00AB})+(.*)$/$1/) {	# split at tab-to-next-field char
		my @a = split /(?:\x{2022}|\x{00AB})+/, $2;
		for (my $i = 1; $i <= @a; $i++) {
		    push @fieldlist, [ join('_', $_ , 'part', $i + 1)  =>  $a[$i - 1] ];
		}
	    }

	    $row->{$_} =~ s/[\x{2022}\x{00B6}\x{00A7}\x{221E}\x{00AB}]//g;	# strip all remaining metcharacters now
	}

	# Everything that remains in the row is the field data
	for (keys %$row) {
	    debug "\tcust field: $_ => $row->{$_}";
	    push @fieldlist, [ $_ => $row->{$_} ];
	}

	my $normalized = normalize_card_data(\%card_field_specs, $itype, \@fieldlist, \%cmeta);
	my $cardlist   = explode_normalized($itype, $normalized);

	for (keys %$cardlist) {
	    print_record($cardlist->{$_});
	    push @{$Cards{$_}}, $cardlist->{$_};
	}
	$n++;
    }
    if (! $csv->eof()) {
	warn "Unexpected failure parsing CSV: row $n";
    }

    summarize_import('item', $n - 1);
    return \%Cards;
}

sub do_export {
    add_custom_fields(\%card_field_specs);
    create_pif_file(@_);
}

sub find_card_type {
    my $hr = shift;
    my $type = ($hr->{'url'} ne '' or $hr->{'username'} ne '' or $hr->{'password'} ne '') ? 'login' : 'note';
    debug "type detected as '$type'";
    return $type;
}

1;
