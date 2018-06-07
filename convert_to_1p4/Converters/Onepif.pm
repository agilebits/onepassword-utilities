# 1PIF converter
#
# Copyright 2015 Mike Cappella (mike@cappella.us)

package Converters::Onepif 1.03;

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

use JSON::PP;
use XML::Simple;
use XML::LibXSLT;
use XML::LibXML;
use Time::Piece;

my $header	= qq/'1password data'/;

my %card_field_specs = (
    bankacct =>		{ textname => '', fields => [ ]},
    creditcard =>	{ textname => '', fields => [ ]},
    database =>		{ textname => '', fields => [ ]},
    driverslicense =>	{ textname => '', fields => [ ]},
    email =>		{ textname => '', fields => [ ]},
    identity =>		{ textname => '', fields => [ ]},
    login =>		{ textname => '', fields => [ ]},
    membership =>	{ textname => '', fields => [ ]},
    note =>		{ textname => '', fields => [ ]},
    outdoorlicense =>	{ textname => '', fields => [ ]},
    passport =>		{ textname => '', fields => [ ]},
    password =>		{ textname => '', fields => [ ]},
    rewards =>		{ textname => '', fields => [ ]},
    server =>		{ textname => '', fields => [ ]},
    socialsecurity =>	{ textname => '', fields => [ ]},
    software =>		{ textname => '', fields => [ ]},
    wireless =>		{ textname => '', fields => [ ]},
);

$DB::single = 1;					# triggers breakpoint when debugging

sub do_init {
    return {
	'specs'		=> \%card_field_specs,
	'imptypes'  	=> undef,
	'opts'		=> [ [ q{      --format <formatter> # use specified output formatter (see Formatters folder) },
			       'format=s' ],
			     [ q{      --percategory        # create one file per category },
			       'percategory' ],
			     [ q{      --encodekey <key>    # shift encode password using key },
                               'encodekey=s' ],
			   ],
    }
}

sub bycategory {
    return -1 if $a->{'typeName'} eq 'webforms.WebForm';
    return  1 if $b->{'typeName'} eq 'webforms.WebForm';
    return $a->{'typeName'} cmp $b->{'typeName'}
}

my %exported;
my ($formatter, $proctype, $output_suffix);

sub do_import {
    my ($file, $imptypes) = @_;

    # open the formatter to process the items
    #
    my @formatters = glob join '/', 'Formatters', ($main::opts{'format'} // 'html_compact') . '.*';
    if (@formatters == 0) {
	@formatters = @formatters = map { /Formatters\/(.*)\.[^.]+$/; "    $1" } glob join '/', 'Formatters', '*';
	bail "No such formatter matches '$main::opts{'format'}'; the available formatters are:\n", join "\n", @formatters;
    }
    bail "More than one style formatter matches '$main::opts{'format'}'; specify one more precisely."	if @formatters > 1;

    ($formatter, $proctype) = split '\.', (split '/', $formatters[0])[1];
    $output_suffix = (split '_', $formatter)[0];

    my $itemsref = get_items_from_1pif $file;

    # Imptypes / exptypes filtering - types are one to one in this converter
    # Also, tally exports by type
    my (@newlist, $n);
    for (@$itemsref) {
	# skip 1Password system types (folders, saved searches, ...)
	next if $_->{'typeName'} =~ /^system\.folder\./;

	my $typekey = typename_to_typekey($_->{'typeName'});
	if (! defined $typekey) {
	    say "Unknown typename: $_->{'typeName'}";
	    $typekey = 'UNKNOWN';
	    $n++;
	}
	else {
	    next if $imptypes and ! exists $imptypes->{$typekey};
	    $n++;
	    next if exists $main::opts{'exptypes'} and ! exists $main::opts{'exptypes'}->{$typekey};
	}
	$exported{$typekey}++;
	push @newlist, $_;
    }
    $itemsref = \@newlist;

    my @items = sort bycategory @$itemsref;

    # Fixup the 'linked items' sections; remove the section, and combine the 't' values (the target record's title) into
    # an array in the secureContents area under a new key named "Linked_Items".  This simplifies processing for formatters,
    # since it can be treated just like "tags".
    for my $item (@items) {
	my (@sections, @linked_items);
	if (exists $item->{'secureContents'} and exists $item->{'secureContents'}{'sections'}) {
	    for my $section (@{$item->{'secureContents'}{'sections'}}) {
		if ($section->{'name'} ne 'linked items') {
		    push @sections, $section;
		}
		else {
		    next unless exists $section->{'fields'};

		    for my $field (@{$section->{'fields'}}) {
			push @linked_items, $field->{'t'}	if $field->{'t'} ne '' and exists $field->{'v'};
		    }
		    if (@linked_items) {
			$item->{'secureContents'}{'Linked_Items'} = \@linked_items;
		    }
		}
	    }
	    delete $item->{'secureContents'}{'sections'};
	    $item->{'secureContents'}{'sections'} = \@sections	if @sections;
	}
    }

    # open the formatter and perform the transformation
    #
    my $output;
    if ($proctype eq 'xsl') {
	my $xsl_file = $formatters[0];

	my $xsimple = XML::Simple->new();
	debug "Creating XML...\n";
	my $xml_str = $xsimple->XMLout(\@items,
			   NoAttr	=> 1,
			   XMLDecl	=> '<?xml version="1.0" encoding="UTF-8"?>');

	my $xml_parser  = XML::LibXML->new;
	my $xslt_parser = XML::LibXSLT->new;
	$xslt_parser->register_function("urn:perlfuncs", "epoch2date", \&epoch2date);
	$xslt_parser->register_function("urn:perlfuncs", "monthYear",  \&monthYear);
	$xslt_parser->register_function("urn:perlfuncs", "address2str",  \&address2str);
	$xslt_parser->register_function("urn:perlfuncs", "encodepassword",  \&encodepassword);

	my $xml = eval { $xml_parser->parse_string($xml_str); }; die "XML parse failed: $@"	if $@;
	my $xsl = eval { $xml_parser->parse_file($xsl_file); }; die "XSL file parse failed: $@"	if $@;

	my $stylesheet  = $xslt_parser->parse_stylesheet($xsl);
	my $results     = $stylesheet->transform($xml, header => $header);
	   $output      = \($stylesheet->output_as_chars($results));
    }
    elsif ($proctype eq 'pm') {
	my $module = ($formatters[0] =~ s/\//::/r);
	$module =~ s/\.pm$//;

	eval {
	    require $formatters[0];
	    $module->import();
	    1;
	} or do {
	    my $error = $@;
	    main::Usage(1, "Error: failed to load style formatter module '$formatter'\n$error");
	};

	$output = $module->do_process(\@items);
    }
    else {
	bail "Unsupported style formatter type: $proctype";
    }

    #debug "\n", $output;		# needs to be updated to $$output or iterate through $output hash
    debug "Done\n";

    summarize_import('item', $n);
    return $output;
}

sub do_export {
    my $output = shift;
    my $ntotal = 0;
    my @files;

    if (%exported) {
	my @categories = ref $output eq 'HASH' ? keys %$output : ( '' );
	for (@categories) {
	    my $file = $main::opts{'outfile'};
	    my $catname = lc ($_ =~ s/ /_/gr);
	    $file =~ s/([\\\/]1P)_import\.1pif$/myjoin('_', $1, 'converted', $catname) . ".$output_suffix"/e;
	    debug "Output file: ", $file;
	    push @files, $file;

	    open my $io, ">:encoding(utf8)", $file
		or bail "Unable to open 1PIF file: $file\n$!";
	    print $io ref($output) eq 'HASH' ? $output->{$_} : $$output;
	    close $io;
	}

	for my $type (keys %exported) {
	    $ntotal += $exported{$type};
	    verbose "Exported $exported{$type} $type ", pluralize('item', $exported{$type});
	}
    }

    verbose "Exported $ntotal total ", pluralize('item', $ntotal);
    if ($ntotal) {
	if (@files > 1) {
	    verbose "The following files are ready to use:";
	    verbose "\t$_"	for @files;
	}
	else {
	    verbose "Your output file is $files[0]";
	}
    }
}

# functions used by XML formatters
#
sub epoch2date {
    my ($t,$notime) = @_;
    $t = localtime $t->[0]->textContent;
    return $notime ? $t->ymd : join ' ', $t->ymd, $t->hms;
}

sub monthYear {
    my $val = $_[0][0]->textContent;
    $val =~ s/^(\d{4})(\d{2})$/$1-$2/;
    return $val;
}

sub address2str {
    my $val = $_[0][0]->textContent;
    my @addrs;
    for (qw/street city state zip country/) {
	if (my $found = $_[0][0]->find($_)->[0]) {
	    push @addrs, [ $_, $found->textContent ]	if defined $found->textContent and $found->textContent ne '';
	}
    }
    return @addrs ? ( myjoin ", ", map { join ': ', $_->[0], $_->[1] } @addrs) : '';
}

sub encodepassword {
    my $pw = $_[0][0]->textContent;
    my @chars = unpack("C*", $pw);
    my @keys = unpack("C*", $main::opts{'encodekey'});
    my @shifts;
    for (@keys) {
	push @shifts, $_- ord '1'  - 1;
    }

    my $ret;
    for (my $i = 0; $i < @chars; $i++) {
	my $val = $chars[$i] - $shifts[$i % @shifts];
	$val += 95	if $val < 32;		# wrap over non-printing chars
	$ret .= sprintf "%02x", $val;
    }
    debug $ret;
    return $ret;
}

1;
