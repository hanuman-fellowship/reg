use strict;
use warnings;
package DB::AffilPerson;
use DBH;

sub order { 1 }

sub create {
    $dbh->do(<<"EOS");
DROP TABLE IF EXISTS affil_people;
EOS
    $dbh->do(<<"EOS");
CREATE TABLE affil_people (
a_id integer $idn,
p_id integer $idn
)
EOS
}

sub init {
    return;     # see Person
}

1;
