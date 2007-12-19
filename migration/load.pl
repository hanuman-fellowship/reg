#!/usr/bin/perl
use strict;
use warnings;
use DBI;

my $dbh = DBI->connect("dbi:SQLite:retreatcenter.db")
    or die "oh no\n";

my $af_sql = "insert into affils values(?, ?)";
my $af_sth = $dbh->prepare($af_sql)
    or die "no prep affil\n";
my $p_sql = "insert into people values(". ("?," x 23) . "?)";
my $p_sth = $dbh->prepare($p_sql)
    or die "no prep people\n";
my $ap_sql = "insert into affil_people values(?, ?)";
my $ap_sth = $dbh->prepare($ap_sql)
    or die "no prep affil_people\n";

my @flds;

open my $affils, "<", "affils"
    or die "cannot open affils: $!\n";
my %affil_id;
my ($code, $value, $n);
while (<$affils>) {
    chomp;
    ++$n;
    ($code, $value) = split /\|/;
    next if $code eq '9' || $code eq '8';       # has its own column now
    $af_sth->execute($n, $value);
    $affil_id{$code} = $n;
}
close $affils;
open my $people, "<", "people"
    or die "cannot open people: $!\n";
$n = 0;
$|++;
while (<$people>) {
    chomp;
    ++$n;
    print "$n\r";
    @flds = split /\|/;
    if (@flds == 24) {
        push @flds, "";
    }
    for my $dt (@flds[18,19,21..23]) {
        my ($m, $d, $y) = $dt =~ m{(..)/(..)/(..)};
        if ($dt eq "  /  /  ") {
            $dt = "        ";
        }
        elsif ($y < 70) {
            $y = "20$y";
        }
        else {
            $y = "19$y";
        }
        $dt = "$y$m$d";
    }
    $affils = $flds[20];
    $affils =~ s{8}{};
    my ($mailings) = ($affils =~ s{9}{})? "": "yes";
    $p_sth->execute(@flds[0..14, 16..19, 21..24], $mailings);
    my %seen;
    for my $a (grep {!$seen{$_}++} split //, $affils) {
        if (exists $affil_id{$a}) {
            $ap_sth->execute($affil_id{$a}, $flds[16]);
        }
        else {
            print "no affil letter $a??\n";
        }
    }
}
print "\n";
close $people;
=comment
    ? alltrim(last)  + t + ; 0
	  alltrim(first) + t + ; 1
      alltrim(sanskrit) + t + ;
	  alltrim(addr1) + t + ;
	  alltrim(addr2) + t + ;
	  alltrim(city) + t + ;
	  alltrim(st_prov) + t + ;
	  alltrim(zip_post) + t + ;
	  alltrim(country) + t + ;
	  alltrim(akey) + t + ;
	  alltrim(tel_home) + t + ;
	  alltrim(tel_work) + t + ;
	  alltrim(tel_cell) + t + ;
	  alltrim(email) + t + ;
	  alltrim(sex) + t + ;
	  alltrim(name_pref) + t + ; 15
	  alltrim(str(id)) + t + ; 16
	  alltrim(str(id_sps)) + t + ; 17
	  dtoc(date_updat) + t + ; 18
	  dtoc(date_entrd) + t + ; 19
	  alltrim(affil) + t + ; 20
	  dtoc(date_hf) + t + ; 21
	  dtoc(date_path) + t + ; 22
	  dtoc(date_lm) + t + ; 23
	  alltrim(comment)
=cut
