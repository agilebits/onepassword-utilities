#
# Copyright 2015 Mike Cappella (mike@cappella.us)

package Utils::Normalize 1.02;

our @ISA	= qw(Exporter);
our @EXPORT	= qw(normalize_card_data explode_normalized add_custom_fields npre_explode npost_explode CFS_FIELD CFS_TYPEHINT CFS_MATCHSTR CFS_OPTS);
#our @EXPORT_OK	= qw();

use v5.14;
use utf8;
use strict;
use warnings;
#use diagnostics;

use Utils::PIF qw(add_new_field);
use Utils::Utils qw(verbose debug bail pluralize unfold_and_chop myjoin);

use constant {
    CFS_FIELD	 => 0,
    CFS_TYPEHINT => 1,
    CFS_MATCHSTR => 2,
    CFS_OPTS	 => 3,
};


our ($npre_explode, $npost_explode);

# generate a unique custom field key 
my $custom_field_num = 1;
sub gen_field_key {
    my ($key, $type) = @_;
    $key =~ s/_?###/'_' . $custom_field_num++/e;
    $key =~ s/^_//;
    return sprintf "_%s_%s",  $type, $key;
}

# Places card data into a normalized internal form.
#
# Card metadata input via hash ref with keys+values:
#    title, notes, tags, folder, modified
#
# Normalized output contains the input metadata keys+values, and an array of fields, each containing:
#    inkey	=> imported field name
#    value	=> field value after callback processing
#    valueorig	=> original field value
#    outkey	=> exported field name
#    outtype	=> field's output type (may be different than card's output type)
#    keep	=> keep inkey:valueorig pair so it can be placed in notes
#    as_title	=> set title to a value from the normalized card or a calc'd value
#    to_title	=> append title with a value from the narmalized card or a calc'd value
#
sub normalize_card_data {
    my ($card_field_specs, $type, $fieldlist, $cmeta, $postprocess) = @_;

    my @to_notes;
    my $i = 0;
    while (@$fieldlist) {
	my ($inkey, $value);
	my $f = shift @$fieldlist;

	# Grab the field key / value pair
	if (ref $f eq 'ARRAY') {
	    ($inkey, $value) = ($f->[0], $f->[1]);
	    next if not defined $value or $value eq '';
	}
	# Some converters (e.g. ewallet) in their %card_field_specs table use REs to capture key/value pairs.
	# In such cases, the full text string is required below so that the text will match a field entry.
	else {
	    $inkey = $f;
	}

	debug "field: $inkey";

	my ($h, @kv, @found);
	for my $cfs (@{$card_field_specs->{$type}{'fields'}}) {
	    if (ref $cfs->[CFS_MATCHSTR] eq 'Regexp') {
		if ($inkey =~ $cfs->[CFS_MATCHSTR]) {
		    push @kv,($1,$2)	if ref $f eq '';	# key/value capture groups are assumed in the %card_field_spec defs.
		    push @found, $cfs;
		}
	    }
	    elsif (ref $cfs->[CFS_MATCHSTR] eq 'CODE') {
		if ($cfs->[CFS_MATCHSTR]->($f, $cfs->[0])) {
		    push @found, $cfs;
		}
	    }
	    elsif ($inkey eq ($cfs->[CFS_OPTS]{'i18n'} // $cfs->[CFS_MATCHSTR])) {
		push @found, $cfs;
	    }
	}

	if (@found) {
	    bail "Unexpected duplicate key '$inkey' in card_field_specs{$type}"		if @found > 1;
	    my $cfs = shift @found;

	    # Use @kv key/value pair when they were gathered above
	    ($inkey, $value) = ($kv[0],$kv[1])	 if ref $f eq '';

	    my $origvalue = $value;
	    my $outkey = $cfs->[CFS_FIELD] =~ /###/ ? gen_field_key($cfs->[CFS_FIELD], $type) : $cfs->[CFS_FIELD];	# generate a unique key when it contains '###'
	    if (exists $cfs->[CFS_OPTS] and exists $cfs->[CFS_OPTS]{'func'}) {
		#         callback(value, outkey)
		my $ret = ($cfs->[CFS_OPTS]{'func'})->($value, $outkey);
		$value = $ret	if defined $ret;
	    }
	    $h = {
		inkey		=> $inkey,
		value		=> $value,
		valueorig	=> $origvalue,
		outkey		=> $outkey,
		outtype		=> $cfs->[CFS_OPTS]{'type_out'} || $card_field_specs->{$type}{'type_out'} || $type,
		keep		=> $cfs->[CFS_OPTS]{'keep'} // 0,
	    };
	    if (exists $cfs->[CFS_OPTS]{'as_title'}) {
		$h->{'as_title'} = ref $cfs->[CFS_OPTS]{'as_title'} eq 'CODE' ? $cfs->[CFS_OPTS]->{'as_title'}($h) :         $h->{$cfs->[CFS_OPTS]{'as_title'}};
	    }
	    if (exists $cfs->[CFS_OPTS]{'to_title'}) {
		$h->{'to_title'} = ref $cfs->[CFS_OPTS]{'to_title'} eq 'CODE' ? $cfs->[CFS_OPTS]->{'to_title'}($h) : ' - ' . $h->{$cfs->[CFS_OPTS]{'to_title'}};
	    }
	}
	else {
	    if ($main::opts{'addfields'}) {
		$h = {
		    inkey	=> $inkey,
		    value	=> $value,
		    valueorig	=> $value,
		    outkey	=> gen_field_key('custom_###', $type),
		    outtype	=> $card_field_specs->{$type}{'type_out'} || $type,
		    keep	=> 0,
		};
		add_new_field($h->{'outtype'}, $h->{'outkey'}, $Utils::PIF::sn_addfields, $Utils::PIF::k_string, lc $inkey);
		debug "added custom field: $h->{'outtype'}, $h->{'outkey'}, $inkey, $value}";
	    }
	    else {
		# to notes
		debug "\tpushed to notes: $inkey: $value";
		push @to_notes, join ': ', $inkey, $value;
		next;
	    }
	}

	push @{$cmeta->{'fields'}}, $h;
    }

    # Map any remaining keys to notes
    if ($cmeta->{'notes'}) {
	my $notes = myjoin("\n", ref $cmeta->{'notes'} eq 'ARRAY' ? @{$cmeta->{'notes'}} : $cmeta->{'notes'});
	$to_notes[-1] .= "\n"	if @to_notes and length $notes > 0;
	push @to_notes, $notes;
    }
    $cmeta->{'notes'} = myjoin("\n", @to_notes);

    $postprocess and ($postprocess)->($type, $cmeta);
    return $cmeta;
}

# Explodes normalized card data into one or more normalized cards, based on the 'outtype' value in 
# the normalized card data.  The exploded card list is returned as a per-type hash.
sub explode_normalized {
    my ($itype, $norm_card) = @_;

    my (%oc, $nc);
    # special case - Notes cards type have no 'fields', but $norm_card->{'notes'} will contain the notes
    if (not exists $norm_card->{'fields'}) {
	for (qw/title tags notes folder modified created icon pwhistory/) {
	    # trigger the for() loop below
	    $oc{'note'}{$_} = 1		if exists $norm_card->{$_} and defined $norm_card->{$_} and  $norm_card->{$_} ne '';
	}
    }
    else {
	while (my $field = pop @{$norm_card->{'fields'}}) {
	    push @{$oc{$field->{'outtype'}}{'fields'}}, { %$field };
	}
    }

    # loop through each of the output card types, starting with the primary type
    # grab any to_title entries for the primary type and add these to the secondary entries
    for my $type (sort { $b eq $itype } keys %oc) {
	my $new_title;
	# look for and use any title replacements
	if (my @found = grep { $_->{'as_title'}} @{$oc{$type}{'fields'}}) {
	    @found > 1 and die "More than one 'as_title' keywords found for type '$type' - please report";
	    $new_title = $found[0]->{'as_title'};
	    debug "\t\tnew title for exploded card type '$type':  $new_title";
	}

	# add any supplemental title additions
	my $added_title = myjoin('', map { $_->{'to_title'} } @{$oc{$type}{'fields'}});
	$oc{$type}{'title'} = ($new_title || $norm_card->{'title'} || 'Untitled') . $added_title;

	for (qw/tags notes folder modified created icon pwhistory/) {
	    $oc{$type}{$_} = $norm_card->{$_}	if exists $norm_card->{$_} and defined $norm_card->{$_} and $norm_card->{$_} ne '';
	}
    }

    my @k = keys %oc;
    if (@k > 1) {
	$npre_explode++; $npost_explode += @k;
	debug "\tcard type '$itype' exploded into ", scalar @k, " cards of type: @k"
    }

    return \%oc;
}

# Adds custom fields to the pif_table
#
sub add_custom_fields {
    my $card_field_specs = shift;

    for my $type (keys %$card_field_specs) {
	for my $cfs (@{$card_field_specs->{$type}{'fields'}}) {
	    if (exists $cfs->[CFS_OPTS]{'custfield'}) {
		my $outtype = $cfs->[CFS_OPTS]{'type_out'} || $card_field_specs->{$type}{'type_out'} || $type;
		add_new_field($outtype, $cfs->[CFS_FIELD], @{$cfs->[CFS_OPTS]{'custfield'}});
	    }
	}
    }
}

1;
