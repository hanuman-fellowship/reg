use strict;
use warnings;
package DB::RegHistory;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS reg_history;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE reg_history (
    id
    reg_id
    the_date
    time
    user_id
    what
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO reg_history
(id, reg_id, the_date, time, user_id, what) 
VALUES
(?, ?, ?, ?, ?, ?)
EOS
}

1;
