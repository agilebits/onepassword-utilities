# CSV formatter
#
# Copyright 2017 Mike Cappella (mike@cappella.us)

package Formatters::csv 1.00;

our @ISA 	= qw(Exporter);
our @EXPORT     = qw(do_process);
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
use Time::Piece;
use Time::Local qw(timelocal);

$DB::single = 1;					# triggers breakpoint when debugging

my $custom_field_num = 1;

sub by_typeName {
    return -1 if $a eq 'webforms.WebForm';
    return  1 if $b eq 'webforms.WebForm';
    $a cmp $b;
}

sub by_depth {
    length($a =~ s/[^:]//gr) <=> length($b =~ s/[^:]//gr) ||
	$a cmp $b;
}

my (%headers, %field_order, %values);

sub add_fv_pair {
    my ($values, $category, $field, $value) = @_;
    if (not exists $headers{$category}{$field}) {
	push @{$field_order{$category}}, $field;

	# Store the index into the @field_order array as the value for the category,field key
	$headers{$category}{$field} = -1 + scalar @{$field_order{$category}};
    }
    $values->{$field} = $value;
    debug "    field: $field = $value";
}

sub epoch2date {
    my ($t,$notime) = @_;
    $t = localtime $t;
    return $notime ? $t->ymd : join ' ', $t->ymd, $t->hms;
}

sub do_process {
    my ($module, $cards) = @_;

    my $csv = Text::CSV->new ({
	    binary => 1,
	    allow_loose_quotes => 0,
	    sep_char => ',',
	    #eol => "\x{0d}\x{0a}",
    });
    for my $card (@$cards) {
	# collect headers
	my $category = $card->{'typeName'};

	my %v;

	debug "Processing card '$card->{'title'}: category $category";
	add_fv_pair(\%v, $category, 'Title', $card->{'title'})		if exists $card->{'title'};

	if ($category eq 'webforms.WebForm') {				# Logins
	    # iterate over the fields
	    for (@{$card->{'secureContents'}{'fields'}}) {
		# Login records use webform details, so look for only entries with a "designation" key.
		next unless exists $_->{'designation'};

		# Maintain the sort order of headers in a record.  First come, first serve
		add_fv_pair(\%v, $category, $_->{'designation'}, $_->{'value'});
	    }
	}

	if (exists $card->{'secureContents'}) {
	    if ($category eq 'passwords.Password') {			# Passwords
		add_fv_pair(\%v, $category, 'password', $card->{'secureContents'}{'password'})		if exists $card->{'secureContents'}{'password'};
	    }

	    if (exists $card->{'secureContents'}{'sections'}) {
		for my $section (@{$card->{'secureContents'}{'sections'}}) {
		    for my $f (@{$section->{'fields'}}) {
			my $field = $section->{'title'} eq '' ? $f->{'t'} : join('::', $section->{'title'}, $f->{'t'});
			next unless exists $f->{'v'} and $f->{'v'} ne '';
			my $val;
			if ($f->{'k'} eq 'address') {

			    my @addrs;
			    for (qw/street city state zip country/) {
				push @addrs, [ $_, $f->{'v'}{$_} ]	if defined $f->{'v'}{$_} and $f->{'v'}{$_} ne '';
			    }
			    $val = @addrs ? ( myjoin "\n", map { join ': ', $_->[0], $_->[1] } @addrs) : '';
			}
			elsif ($f->{'k'} eq 'date') {
			    $val = epoch2date($f->{'v'}, 1)
			}
			elsif ($f->{'k'} eq 'monthYear') {
			    ($val = $f->{'v'}) =~ s/^(\d{4})(\d{2})$/$1-$2/;
			}
			else {
			    $val = $f->{'v'};
			}
			add_fv_pair(\%v, $category, $field, $val);
		    }
		}
	    }
	}

	# Tags
	add_fv_pair(\%v, $category, 'Tags', join "; ", @{$card->{'openContents'}{'tags'}})	if exists $card->{'openContents'}{'tags'};

	# URLs
	if (exists $card->{'secureContents'}{'URLs'}) {
	    add_fv_pair(\%v, $category, 'URLs', join "\n",
		    map { ( $_->{'label'} eq '' or @{$card->{'secureContents'}{'URLs'}} == 1)
				? $_->{'url'}
				: join(':  ', $_->{'label'}, $_->{'url'});
			} @{$card->{'secureContents'}{'URLs'}});
	}

	# Related Items
	add_fv_pair(\%v, $category, 'Related Items', join "\n", @{$card->{'secureContents'}{'Linked_Items'}})	if exists $card->{'secureContents'}{'Linked_Items'};

	# Dates - last modified, created
	add_fv_pair(\%v, $category, 'Last Updated', epoch2date($card->{'updatedAt'}))		if exists $card->{'updatedAt'};
	add_fv_pair(\%v, $category, 'Date Created', epoch2date($card->{'createdAt'}))		if exists $card->{'createdAt'};

	# Notes
	add_fv_pair(\%v, $category, 'Notes', $card->{'secureContents'}{'notesPlain'})		if exists $card->{'secureContents'}{'notesPlain'};

	push @{$values{$category}}, \%v		if %v;
    }

    my ($status, $output, %output_hash);
    $output = \(my $str = '');
    for my $category (sort by_typeName keys %headers) {
	my $typeMapKey = (grep { $Utils::PIF::typeMap{$_}{'typeName'} eq $category } keys %Utils::PIF::typeMap)[0];
	my $category_name = $Utils::PIF::typeMap{$typeMapKey}{'title'};

	my @columns = ();

	debug "Processing category: $category";
	for my $field (keys %{$headers{$category}}) {
	    debug "\tfield: $field, column = $headers{$category}{$field}";
	    $columns[ $headers{$category}{$field} ] = $field;
	}
	unshift @columns, 'Category';
	$status = $csv->combine(@columns);

	if ($main::opts{'percategory'}) {
	    $output = \$output_hash{$category_name};
	}
	$$output .= $csv->string() . "\n";

	for my $entry (@{$values{$category}}) {
	    @columns = ();
	    for my $field (keys %$entry) {
		$columns[ $headers{$category}{$field} ] = $entry->{$field};
	    }
	    unshift @columns, $category_name;
	    $status = $csv->combine(@columns);
	    $$output .= $csv->string() . "\n";;
	}
	$$output .= "\n"		unless $main::opts{'percategory'};
    }
    return $main::opts{'percategory'} ? \%output_hash : $output;
}

1;
