use strict;
use warnings;
package DB::LeaderProgram;
use DBH '$dbh';

sub order { 0 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS leader_program;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE leader_program (
l_id integer,
p_id integer
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO leader_program
(l_id, p_id) 
VALUES
(?, ?)
EOS
}

1;
