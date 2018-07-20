use strict;
use warnings;
package DB::RegPayment;
use DBH '$dbh';

sub order { 0 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS reg_payment;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE reg_payment (
id integer primary key autoincrement,
reg_id integer,
user_id integer,
the_date text,
time text,
amount text,
type text,
what text
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO reg_payment
(id, reg_id, user_id, the_date, time, amount, type, what) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
