#!/usr/bin/env perl
use strict;
use warnings;

my @files = `ls -1t /var/Reg/backup`;
chomp @files;
my @to_delete = splice @files, 10;
print scalar(localtime), "\n";
print "in /var/Reg/backup deleting @to_delete\n";
for my $f (@to_delete) {
    unlink $f or print "could not unlink $f: $!\n";
}
