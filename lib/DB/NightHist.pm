use strict;
use warnings;
package DB::NightHist;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS night_hist;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE night_hist (
    id
    member_id
    reg_id
    num_nights
    action
    user_id
    the_date
    time
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO night_hist
(id, member_id, reg_id, num_nights, action, user_id, the_date, time) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
