use strict;
use warnings;
package DB::RegPayment;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS reg_payment;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE reg_payment (
    id
    reg_id
    user_id
    the_date
    time
    amount
    type
    what
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
