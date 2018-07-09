use strict;
use warnings;
package DB::XAccountPayment;
use DBH '$dbh';

sub order { 0 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS xaccount_payment;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE xaccount_payment (
id integer primary key autoincrement,
xaccount_id integer,
person_id integer,
what text,
amount text,
type text,
user_id integer,
the_date text,
time text
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO xaccount_payment
(id, xaccount_id, person_id, what, amount, type, user_id, the_date, time) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
