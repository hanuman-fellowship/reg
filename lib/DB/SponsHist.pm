use strict;
use warnings;
package DB::SponsHist;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS spons_hist;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE spons_hist (
    id
    member_id
    date_payment
    valid_from
    valid_to
    amount
    general
    user_id
    the_date
    time
    type
    transaction_id
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO spons_hist
(id, member_id, date_payment, valid_from, valid_to, amount, general, user_id, the_date, time, type, transaction_id) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
