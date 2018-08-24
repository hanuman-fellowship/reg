use strict;
use warnings;
package DB::SponsHist;
use DBH;

sub order { 0 }

sub create {
    $dbh->do(<<"EOS");
DROP TABLE IF EXISTS spons_hist;
EOS
    $dbh->do(<<"EOS");
CREATE TABLE spons_hist (
id integer primary key auto_increment,
member_id integer,
date_payment text,
valid_from text,
valid_to text,
amount text,
general text,
user_id integer,
the_date text,
time text,
type text,
transaction_id integer
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<"EOS");
INSERT INTO spons_hist
(id, member_id, date_payment, valid_from, valid_to, amount, general, user_id, the_date, time, type, transaction_id) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
