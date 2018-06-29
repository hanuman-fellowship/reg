use strict;
use warnings;
package DB::XAccountPayment;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS xaccount_payment;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE xaccount_payment (
    id
    xaccount_id
    person_id
    what
    amount
    type
    user_id
    the_date
    time
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
