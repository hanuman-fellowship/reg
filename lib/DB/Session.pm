use strict;
use warnings;
package DB::Session;
use DBH '$dbh';

sub order { 0 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS sessions;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE sessions (
    id
    session_data
    expires
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO sessions
(id, session_data, expires) 
VALUES
(?, ?, ?)
EOS
}

1;
