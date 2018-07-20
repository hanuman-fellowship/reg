use strict;
use warnings;
package DB::Member;
use DBH '$dbh';

sub order { 0 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS member;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE member (
id integer primary key autoincrement,
category text,
person_id integer,
date_general text,
date_sponsor text,
sponsor_nights text,
date_life text,
free_prog_taken text,
total_paid text,
voter text
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO member
(id, category, person_id, date_general, date_sponsor, sponsor_nights, date_life, free_prog_taken, total_paid, voter) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
