use strict;
use warnings;
package DB::Member;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS member;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE member (
    id
    category
    person_id
    date_general
    date_sponsor
    sponsor_nights
    date_life
    free_prog_taken
    total_paid
    voter
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
