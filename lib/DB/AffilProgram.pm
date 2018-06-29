use strict;
use warnings;
package DB::AffilProgram;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS affil_program;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE affil_program (
    a_id
    p_id
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO affil_program
(a_id, p_id) 
VALUES
(?, ?)
EOS
}

1;
