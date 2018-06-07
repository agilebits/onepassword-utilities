# True Key JSON/CSV export converter
#
# Copyright 2016 Mike Cappella (mike@cappella.us)

package Converters::Truekey 1.01;

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

use JSON::PP;		# early versions exported as JSON
use Text::CSV;		# newer versions export to CSV
use Time::Local qw(timelocal);
use Time::Piece;

# fields to be ignored from the CSV output
my @ignored_fields = (
    'autologin',
    'hexColor',
    'kind',
    'protectedWithPassword',
    'subdomainOnly',
    'tk_export_version',
);

my %card_field_specs = (
    login =>                    { textname => undef, fields => [
        [ 'url',		1, qr/^url$/, ],
        [ 'username',		1, qr/^login$/, ],
        [ 'password',		1, qr/^password$/, ],
    ]},
    driverslicense =>           { textname => undef, fields => [
        [ 'number',		1, qr/^number$/, ],
        [ 'birthdate',		1, qr/^dateOfBirth$/,		{ func => sub { return date2epoch($_[0]) } }],
        [ 'expiry_date',	1, qr/^expirationDate$/,	{ func => sub { return date2monthYear($_[0]) } }],
        [ 'firstname',		1, qr/^firstName$/, ],		# see 'Fixup: combine names'
        [ 'lastname',		1, qr/^lastName$/, ],		# see 'Fixup: combine names'
        [ 'fullname',		1, qr/^First__Last$/, ],	# see 'Fixup: combine names' - input never matches
        [ 'state',		1, qr/^state$/, ],
    ]},
);

$DB::single = 1;					# triggers breakpoint when debugging

sub do_init {
    return {
	'specs'		=> \%card_field_specs,
	'imptypes'  	=> undef,
        'opts'          => [],
    };
}

sub do_import {
    my ($file, $imptypes) = @_;
    my %Cards;

    my $data = slurp_file($file);

    my $n;
    if ($data =~ /^{".*}$/) {
	$n = process_json(\$data, \%Cards, $imptypes);
    }
    else {
	$n = process_csv($file, \%Cards, $imptypes);
    }
	
    summarize_import('item', $n - 1);
    return \%Cards;
}

sub process_csv {
    my ($file, $Cards, $imptypes) = @_;

    my $csv = Text::CSV->new ({
	    binary =>	1,
	    sep_char =>	",",
	    #eol => 	$^O eq 'MSWin32' ? "\x{0d}\x{0a}" : "\n",
	    eol => 	"\n",
    });

    open my $io, "<:encoding(utf8)", $file
        or bail "Unable to open CSV file: $file\n$!";

    my ($n, $rownum) = (1, 1);

    my @colnames = $csv->getline($io) or
	bail "Failed to get CSV column names from first row";
    $csv->column_names(@colnames);

    while (my $row = $csv->getline_hr($io)) {
	debug 'ROW: ', $rownum++;

	my (%cmeta, @fieldlist, $tmp);
	my ($title_key, $note_key);

	my $itype = $row->{'kind'};
	if ($itype eq 'login') {
	    ($title_key, $note_key) = ('name', 'memo');
	}
	elsif ($itype eq 'note') {
	    ($title_key, $note_key) = ('title', 'document_content');
	}
	elsif ($itype eq 'drivers') {
	    ($title_key, $note_key) = ('title', 'note');
	    $itype = 'driverslicense';
	}

	$cmeta{'title'} = $row->{$title_key} || 'Untitled';
	$cmeta{'notes'} = $row->{$note_key}	if exists $row->{$note_key} and $row->{$note_key} ne '';

	if ($row->{'favorite'} eq 'true') {
	    $cmeta{'tags'}	= 'Favorite';
	    $cmeta{'folder'}	= [ 'Favorite' ];
	}
	for (qw/kind name memo title document_content note favorite/) {
	    delete $row->{$_};
	}

	for my $label (keys %$row) {
	    next if ($row->{$label} eq '' or grep { $label eq $_ } @ignored_fields);
	    my $value = $row->{$label};
	    next if not defined $value or $value eq '';
	    push @fieldlist, [ $label => $value ];		# @fieldlist maintains card's field order
	}

	# Fixup: combine names
	if ($itype eq 'driverslicense') {
	    my ($first, $last, @found);
	    $first = $found[0][1]	if @found = grep { $_->[0] eq 'firstName' } @fieldlist;
	    $last  = $found[0][1]	if @found = grep { $_->[0] eq 'lastName' } @fieldlist;

            if ($first or $last) {
                push @fieldlist, [ 'First__Last' =>  myjoin(' ',  $first, $last) ];
                debug "\t\tfield added: $fieldlist[-1][0] -> $fieldlist[-1][1]";
            }
        }

	if (do_common($Cards, \@fieldlist, \%cmeta, $imptypes, $itype)) {
	    $n++;
	}
    }
    return $n;
}

sub process_json {
    my ($data, $Cards, $imptypes) = @_;

    my $decoded = decode_json $$data;

    exists $decoded->{'logins'} or
	bail "Export JSON file - unexpected format";

    my $n = 1;
    for my $entry (@{$decoded->{'logins'}}) {
	my (%cmeta, @fieldlist);

	$cmeta{'title'} = $entry->{'name'};
	$cmeta{'notes'} = $entry->{'memo'};
	if ($entry->{'favorite'} eq 'true') {
	    $cmeta{'tags'} = 'Favorite';
	    $cmeta{'folder'}  = [ 'Favorite' ];
	}

	for my $label (qw/login password url/) {
	    my $value = $entry->{$label};
	    next if not defined $value or $value eq '';
	    push @fieldlist, [ $label => $value ];		# @fieldlist maintains card's field order
	}

	if (do_common($Cards, \@fieldlist, \%cmeta, $imptypes, undef)) {
	    $n++;
	}
    }
}

sub do_common {
    my ($Cards, $fieldlist, $cmeta, $imptypes, $itype) = @_;

    $itype = find_card_type($fieldlist, $itype);

    # skip all types not specifically included in a supplied import types list
    return undef	if defined $imptypes and (! exists $imptypes->{$itype});

    my $normalized = normalize_card_data(\%card_field_specs, $itype, $fieldlist, $cmeta);
    my $cardlist   = explode_normalized($itype, $normalized);

    for (keys %$cardlist) {
	print_record($cardlist->{$_});
	push @{$Cards->{$_}}, $cardlist->{$_};
    }

    return 1;
}

sub do_export {
    add_custom_fields(\%card_field_specs);
    create_pif_file(@_);
}

sub find_card_type {
    my ($fieldlist, $itype) = @_;

    # CSV export data contains the entry type
    if ($itype) {
	debug "type defined as '$itype'";
	return $itype;
    }

    for my $type (sort by_test_order keys %card_field_specs) {
	for my $cfs (@{$card_field_specs{$type}{'fields'}}) {
	    for (@$fieldlist) {
		if ($cfs->[CFS_TYPEHINT] and $_->[0] =~ $cfs->[CFS_MATCHSTR]) {
		    debug "type detected as '$type' (key='$_->[0]')";
		    return $type;
		}
	    }
	}
    }

    debug "\t\ttype defaulting to 'note'";
    return 'note';
}

# sort logins as the last to check
sub by_test_order {
    return  1 if $a eq 'login';
    return -1 if $b eq 'login';
    $a cmp $b;
}

# Date converters
#     yyyy-mm-ddThh:mm:ss-Zh:Zm
sub parse_date_string {
    local $_ = $_[0];
    my $when = $_[1] || 0;					# -1 = past only, 0 = assume this century, 1 = future only, 2 = 50-yr moving window

    if (/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}-\d{2}:\d{2}$/) {
	# remove the : separator between the TZ components
	s/(-\d{2}):(\d{2})$/$1$2/;
	if (my $t = Time::Piece->strptime($_, "%Y-%m-%dT%H:%M:%S%z")) {	# yyyy-mm-ddThh:mm:ss[-+]ZhZs
	    return $t;
	}
    }

    return undef;
}

sub date2epoch {
    my $t = parse_date_string @_;
    return undef if not defined $t;
    return defined $t->year ? 0 + timelocal($t->sec, $t->minute, $t->hour, $t->mday, $t->mon - 1, $t->year): $_[0];
}

sub date2monthYear {
    my $t = parse_date_string @_;
    return defined $t->year ? $t->strftime("%Y%m") : $_[0];
}


1;
