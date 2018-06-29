use strict;
use warnings;
package DB::Issue;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS issue;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE issue (
    id
    priority
    title
    notes
    date_entered
    date_closed
    user_id
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO issue
(id, priority, title, notes, date_entered, date_closed, user_id) 
VALUES
(?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
