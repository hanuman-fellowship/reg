#!/usr/bin/perl
use strict;
use warnings;
use DBI;
my $dbh = DBI->connect("dbi:SQLite:retreatcenter.db")
    or die "oh no\n";

my $p_sql = "select name from program where id = ?";
my $p_sth = $dbh->prepare($p_sql) or die "no p_sql\n";

my $per_sql = "select id from people where first = ? and last = ?";
my $per_sth = $dbh->prepare($per_sql) or die "no per_sql\n";

my $insper_sql = "insert into people (id, first, last) values (?, ?, ?)";
my $insper_sth = $dbh->prepare($insper_sql) or die "no insper_sql\n";

open my $reg, "<", "new/curreg.txt"
    or die "no curreg\n";
my %map = qw/
    pid program_id
/;
my %hash;
while (<$reg>) {
    s{\r?\n}{};
    my ($k, $v) = split m{\t};
    $v =~ s{^\s*|\s*$}{}g;
    $k = $map{$k} if exists $map{$k};
    $hash{$k} = $v;
    if ($k eq 'ceusent') {
        processReg();
        %hash = ();
    }
}
close $reg;

sub processReg {
    $hash{comment} = "";
    $hash{comment} .= "$hash{'1comment'}\n" if $hash{'1comment'};
    $hash{comment} .= "$hash{'2comment'}\n" if $hash{'2comment'};
    $hash{comment} .= "$hash{'3comment'}\n" if $hash{'3comment'};
    $hash{confnote} = "";
    $hash{confnote} .= "$hash{'1note'}\n" if $hash{'1note'};
    $hash{confnote} .= "$hash{'2note'}\n" if $hash{'2note'};
    if ($hash{program_id}) {
        $p_sth->execute($hash{program_id});
        unless (my ($name) = $p_sth->fetchrow_array()) {
            print "*** bad program id: $hash{program_id}\n";
        }
    }
    else {
        print "*** no proper program id!\n";
    }
    # get or create the person record
    my $person_id;
    $per_sth->execute($hash{first}, $hash{last});
    if (($person_id) = $per_sth->fetchrow_array()) {
        #print "existing\n";
    }
    else {
        print "need to create $hash{first} $hash{last}???\n";
        #$insper_sth->execute(undef, $hash{first}, $hash{last});
        #$per_sth->execute($hash{first}, $hash{last});
        #($person_id) = $per_sth->fetchrow_array();
        #print "created\n";
    }
    #print "person id %person_id for $hash{first} $hash{last}\n";
}
