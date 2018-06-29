use strict;
use warnings;
package DB::ConfHistory;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS conf_history;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE conf_history (
    id
    reg_id
    note
    user_id
    the_date
    time
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO conf_history
(id, reg_id, note, user_id, the_date, time) 
VALUES
(?, ?, ?, ?, ?, ?)
EOS
}

1;
