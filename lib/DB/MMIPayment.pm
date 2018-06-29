use strict;
use warnings;
package DB::MMIPayment;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS mmi_payment;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE mmi_payment (
    id
    person_id
    amount
    glnum
    the_date
    type
    deleted
    reg_id
    note
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO mmi_payment
(id, person_id, amount, glnum, the_date, type, deleted, reg_id, note) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
