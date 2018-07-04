use strict;
use warnings;
package DB::Block;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS block;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE block (
    id
    house_id
    sdate
    edate
    nbeds
    npeople
    reason
    comment
    allocated
    user_id
    the_date
    time
    rental_id
    program_id
    event_id
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO block
(id, house_id, sdate, edate, nbeds, npeople, reason, comment, allocated, user_id, the_date, time, rental_id, program_id, event_id) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
