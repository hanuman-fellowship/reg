#!/usr/bin/env perl -w
use strict;
use vars '%lookup', '@ISA', '@EXPORT';
use Exporter;
@ISA = qw/Exporter/;
@EXPORT = qw/%lookup/;

open IN, "config/lookup.txt"
	or die "cannot open config/lookup.txt: $!\n";
while (<IN>) {
	chomp;
	my ($k, $v) = split /\t+/;
	$lookup{$k} = $v;
}
close IN;

1;
