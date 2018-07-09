use strict;
use warnings;
package DB::MMIPayment;
use DBH '$dbh';

sub order { 0 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS mmi_payment;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE mmi_payment (
id integer primary key autoincrement,
person_id integer,
amount text,
glnum text,
the_date text,
type text,
deleted text,
reg_id integer,
note text
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
