# Apple Contacts's vCard export converter
#
# Copyright 2015 Mike Cappella (mike@cappella.us)

package Converters::Vcard 1.00;

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
use Utils::Utils qw(verbose debug bail pluralize myjoin print_record);
use Time::Local qw(timelocal);
use Time::Piece;

my %card_field_specs = (
    vcard =>			{ textname => '', type_out => 'identity', fields => [
	[ 'firstname',		0, qr/^__(firstname)::(.+?)\R+/m, ],
	[ 'lastname',		0, qr/^__(lastname)::(.+?)\R+/m, ],
	[ 'address',		0, qr/^(ADR;type=HOME;type=pref):;;(.+?)\R+/m,		{ func => \&convert_address } ],
	[ 'birthdate',		0, qr/^(BDAY):(.+?)\R+/m, 				{ func => \&date2epoch } ],
	[ 'company',		0, qr/^(ORG):(.+?)\R+/m, 				{ func => sub { 1; return (split(/;/, $_[0]))[0] } } ],
	[ 'defphone',		0, qr/^(TEL;(?:type=\w+;)*)type=pref:(.+?)\R+/m, ],
	[ 'homephone',		0, qr/^(TEL;type=HOME;type=VOICE):(.+?)\R+/m, ],
	[ 'cellphone',		0, qr/^(TEL;.*type=CELL.*):(.+?)\R+/m, ],
	[ 'busphone',		0, qr/^(TEL;type=WORK;type=VOICE):(.+?)\R+/m, ],
	[ 'email',		0, qr/^(EMAIL;type=INTERNET;type=\w+;type=pref):(.+?)\R+/m, ],
	[ 'website',		0, qr/^(URL;type=pref(?:;type=\w+)?):(.+?)\R+/m, ],
	[ 'icq',		0, qr/^X-(ICQ;type=pref(?:;type=\w+)?):(.+?)\R+/m, ],
	# skipping the skype entry for now, since there is no preferred attribue - need to change parsing to read all entries, and accept
	# either the preferred entry, or a single entry.
	#[ 'skype',		0, qr/^IMPP;X-SERVICE-(TYPE=Skype:skype):(.+?)\R+/m, ],
	[ 'aim',		0, qr/^(?:item\d+\.)?X-(AIM;type=\w+;type=pref):(.+?)\R+/m, ],
	[ 'yahoo',		0, qr/^X-(YAHOO;type=\w+;type=pref):(.+?)\R+/m, ],
	[ 'msn',		0, qr/^X-(MSN;type=pref(?:;type=\w+)?):(.+?)\R+/m, ],

    ]},
    note =>			{ textname => '', fields => [
    ]},
);

$DB::single = 1;					# triggers breakpoint when debugging

sub do_init {
    return {
	'specs'		=> \%card_field_specs,
	'imptypes'  	=> undef,
	'opts'		=> [],
    }
}

sub do_import {
    my ($file, $imptypes) = @_;

    open my $io, "<:encoding(utf8)", $file
	or bail "Unable to open vCard file: $file\n$!";

    $/ = undef;
    $_ = <$io>;

    my %Cards;
    my $n = 1;
    my ($npre_explode, $npost_explode);

    my $nvcards;
    s/\x{0d}\x{0a}/\n/gs;
    while (s/^BEGIN:VCARD\R+(.+?)^END:VCARD\R+//ms) {
	my $vcard = $1;
	$nvcards++;

	next unless $vcard =~ s#VERSION:3.0\R+^PRODID:-//Apple Inc.//Mac OS X.*?\R+##ms;

	my $itype = 'vcard';
	next if defined $imptypes and (! exists $imptypes->{$itype});

	debug '*** ENTRY ', $nvcards, "\n", $vcard;
	#my @lines = split /\n/, $vcard;

	my (@data, @fieldlist);
	my ($card_title, $card_notes) = ('Unnamed', undef);

	# Grab the standard items: title, notes
	# FN = full name, used as card's title
	if ($vcard =~ s/^FN:(.*)\R+//m) {
	    $card_title = $1 // 'Unnamed';
	}

	# NOTE = card notes, lines separated by two char sequence '\n' 
	if ($vcard =~ s/^NOTE:(.*)\R+//m) {
	    $card_notes = $1 =~ s/\\n/\n/gr;
	}

	# ignore these entries
	$vcard =~ s/^UID:.+\R//m;
	$vcard =~ s/^X-ABUID:.+\R//m;

	# N = names (last, first, ...)
	# Pre-split the vCard's Name field into first name / last name, and stuff it back into the vCard.  This makes
	# processing easier using the %card_field_specs table, in normalize_card_data().
	if ($vcard =~ s/^N:(.*)\R+//m) {
	    @data = split /;/, $1;
	    $vcard = join "\n", "__lastname::$data[0]", "__firstname::$data[1]", $vcard;
	}

	# join two line items, setting the custom label as a TYPE for easy single-line parsing
	# item2.TEL:555-1818
	# item2.X-ABLabel:foophone
	$vcard =~ s/^(?<item>item\d+)\.(?<svc>[^:]+):(?<val>.+?)\R^\g{item}\.X-ABLabel:(:?_\$!<)?(?<label>.+?)(:?>!\$_)?\R/$+{svc} . ';type=' . lc($+{label}) . ":$+{val}\n"/gmse;

	my $normalized = normalize_card_data($itype, \$vcard,
	    { title	=> $card_title,
	      notes	=> $card_notes });

	if (length $vcard) {
	    # Some Notes friendly replacments for vCard attribute strings

	    # EMAIL;type=INTERNET;type=WORK:me@work.example.com
	    $vcard =~ s/^EMAIL;type=INTERNET;type=(?<label>[^:]+):(?<val>.+?)\R/'email ' . lc($+{label}) . ": $+{val}\n"/gmse;

	    # TEL;type=IPHONE;type=CELL;type=VOICE:555-1313
	    # TEL;type=MAIN:555-1616
	    # TEL;type=OTHER;type=VOICE:555-1717
	    $vcard =~ s/^TEL;(?<types>.+?):(?<val>.+?)\R/clean_phone_types($+{types}) . ": $+{val}\n"/gem;

	    # IMPP;X-SERVICE-TYPE=AIM;type=HOME;type=pref:aim:me@aol.com
	    $vcard =~ s/^IMPP;X-SERVICE-TYPE=(?<svc>[^;]+)(?<types>(?:;type=\w+)+):\w+:(?<val>.+?)\R/lc($+{svc}) . ' ' . clean_svc_types($+{types}) . ": $+{val}\n"/gem;

	    # X-ABRELATEDNAMES;type=pref;type=mother:MOM
	    # X-ABRELATEDNAMES;type=father:DAD
	    $vcard =~ s/^X-ABRELATEDNAMES;(type=pref;)?type=(?<relative>.*?):(?<val>.+)\R/lc $+{relative} . ": $+{val}\n"/gem;

	    $vcard =~ s/^ADR;type=WORK:;+/work address: /gm;

	    # URL;type=WORK:http://myworkpage.example.com
	    $vcard =~ s/^URL;type=([^:]+):(.+)/'url ' . lc $1 . ": $2"/gem;

	    # X-AIM;type=WORK:otherme@aol.com
	    $vcard =~ s/^X-AIM;type=([^:]+):(.+)/'aim ' . lc $1 . ": $2"/gem;

	    # map remaining vcard data to notes
	    $normalized->{'notes'} .= "\n\n" . $vcard	if defined $normalized->{'notes'} and length $normalized->{'notes'}
	}

	# Returns list of 1 or more card/type hashes; one input card may explode into multiple output cards
	my $cardlist = explode_normalized($itype, $normalized);

	my @k = keys %$cardlist;
	if (@k > 1) {
	    $npre_explode++; $npost_explode += @k;
	    debug "\tcard type $itype expanded into ", scalar @k, " cards of type @k"
	}
	for (@k) {
	    print_record($cardlist->{$_});
	    push @{$Cards{$_}}, $cardlist->{$_};
	}
	$n++;
    }

    $n--;
    verbose "Imported $n card", pluralize($n) ,
	$npre_explode ? " ($npre_explode card" . pluralize($npre_explode) .  " expanded to $npost_explode cards)" : "";
    return \%Cards;
}

sub do_export {
    create_pif_file(@_);
}

# Places card data into a normalized internal form.
#
# Basic card data passed as $norm_cards hash ref:
#    title
#    notes
#    tags
#    folder
#    modified
# Per-field data hash {
#    inkey	=> imported field name
#    value	=> field value after callback processing
#    valueorig	=> original field value
#    outkey	=> exported field name
#    outtype	=> field's output type (may be different than card's output type)
#    keep	=> keep inkey:valueorig pair can be placed in notes
#    to_title	=> append title with a value from the narmalized card
# }
sub normalize_card_data {
    my ($type, $cardstr, $norm_cards) = @_;

    for my $def (@{$card_field_specs{$type}{'fields'}}) {
	my $h = {};
	# REs captures in %card_field_specs table: $1 = matched field, $2 = value
	debug "Testing def: $def->[2]";
	if ($$cardstr =~ s/$def->[2]//ms) {
	    next if not defined $2 or $2 eq '';
	    my ($inkey, $value) = ($1, $2);
	    my $origvalue = $value;

	    if (exists $def->[3] and exists $def->[3]{'func'}) {
		#         callback(value, outkey)
		my $ret = ($def->[3]{'func'})->($value, $def->[0]);
		$value = $ret	if defined $ret;
	    }
	    $h->{'inkey'}		= $inkey;
	    $h->{'value'}		= $value;
	    $h->{'valueorig'}		= $origvalue;
	    $h->{'outkey'}		= $def->[0];
	    $h->{'outtype'}		= $def->[3]{'type_out'} || $card_field_specs{$type}{'type_out'} || $type; 
	    $h->{'keep'}		= $def->[3]{'keep'} // 0;
	    $h->{'to_title'}		= ' - ' . $h->{$def->[3]{'to_title'}}	if $def->[3]{'to_title'};
	    push @{$norm_cards->{'fields'}}, $h;
	}
    }

    return $norm_cards;
}

sub convert_address {
    # ADR;type=HOME;type=pref:;;555 Mockingbird lane;Busterville;GA;66565;USA
    my @data = split /;/, $_[0];
    return {
	street  => $data[0],
	city    => $data[1],
	state   => $data[2],
	zip     => $data[3],
	country => $data[4]
    };
}

sub clean_svc_types {
    $_ = shift;
    return myjoin ' ', split /;?type=/, lc $_;
}

sub clean_phone_types {
    $_ = shift;

    my @typelist;
    for (split /;?type=/, $_) {
	next if $_ eq '';
	if ($_ eq 'VOICE') {
	    unshift @typelist, 'phone';
	}
	elsif ($_ =~ /^PAGER|FAX$/) {
	    unshift @typelist, lc $_;
	}
	else {
	    push @typelist, lc $_;
	}
    }

    return join ' ', @typelist;
}

# sort logins as the last to check
sub by_test_order {
    return  1 if $a eq 'login';
    return -1 if $b eq 'login';
    $a cmp $b;
}

# sort field data, moving Date Created and Date Modified to the end of the list
sub by_field_name {
    return  1 if $a eq 'Date Modified';
    return -1 if $b eq 'Date Modified';
    return  1 if $a eq 'Date Created';
    return -1 if $b eq 'Date Created';
    $a cmp $b;
}

# Date converters
# BDAY: 		yyyy-mm-dd
sub parse_date_string {
    local $_ = $_[0];
    my $when = $_[1] || 0;					# -1 = past only, 0 = assume this century, 1 = future only, 2 = 50-yr moving window

    if (my $t = Time::Piece->strptime($_, "%Y-%m-%d")) {
	return $t;
    }

    return undef;
}

sub date2epoch {
    my $t = parse_date_string @_;
    return defined $t->year ? 0 + timelocal(0, 0, 0, $t->mday, $t->mon - 1, $t->year): $_[0];
}

1;
