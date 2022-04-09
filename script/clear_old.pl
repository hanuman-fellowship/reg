#!/usr/bin/env perl
use strict;
use warnings;

chdir '/var/Reg/backup' or die "no chdir";
my @files = `ls -1t`;
chomp @files;
my @to_delete = splice @files, 10;
print scalar(localtime), "\n";
print "In /var/Reg/backup deleting @to_delete\n";
for my $f (@to_delete) {
    unlink $f or print "could not unlink $f: $!\n";
}
