#!/usr/bin/perl
use strict;
use warnings;
use DBI;

my $dbh = DBI->connect("dbi:SQLite:retreatcenter.db")
    or die "oh no\n";
my $sth = $dbh->prepare("insert into string values (?, ?);");

open my $strs, "<", "strings.txt"
    or die "cannot open strings.txt: $!\n";
my ($key, $value);
while (<$strs>) {
    chomp;
    ($key, $value) = split /\t+/;
    $sth->execute($key, $value);
}
close $strs;
