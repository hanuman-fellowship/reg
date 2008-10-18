#!/usr/local/ActivePerl-5.8/bin/perl
use strict;
use warnings;

open my $mlist, "<", "new/people.txt"
    or die "no people.txt\n";
open my $clean, ">", "clean";

my (@flds, $id, $sps_id, %id_for);
while (<$mlist>) {
    next unless /\S/;
    @flds = split /\|/; 
    ($id, $sps_id) = @flds[16,17];
    if (exists $id_for{$id}) {
        print "$id - dup id for: @flds[0..2] and $id_for{$id}\n";
        print "sps id is $sps_id\n";
    }
    else {
        $id_for{$id} = "@flds[0..2]";
        print {$clean} $_;
    }
} 
seek($mlist, 0, 0);
while (<$mlist>) {
    @flds = split /\|/; 
    ($sps_id) = $flds[17];
    next unless $sps_id;
    if (! exists $id_for{$id}) {
        print "$id - no such partner id\n";
    }
} 
close $mlist;
close $clean;
