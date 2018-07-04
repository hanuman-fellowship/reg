use strict;
use warnings;
package DB::AffilPerson;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS affil_people;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE affil_people (
    a_id
    p_id
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO affil_people
(a_id, p_id) 
VALUES
(?, ?)
EOS
}

1;
