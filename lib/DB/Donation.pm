use strict;
use warnings;
package DB::Donation;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS donation;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE donation (
    id
    person_id
    project_id
    the_date
    amount
    type
    who_d
    date_d
    time_d
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO donation
(id, person_id, project_id, the_date, amount, type, who_d, date_d, time_d) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
