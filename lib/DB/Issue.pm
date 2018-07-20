use strict;
use warnings;
package DB::Issue;
use DBH '$dbh';

sub order { 0 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS issue;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE issue (
id integer primary key autoincrement,
priority text,
title text,
notes text,
date_entered text,
date_closed text,
user_id integer
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
