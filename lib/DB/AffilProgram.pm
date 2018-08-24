use strict;
use warnings;
package DB::AffilProgram;
use DBH;

sub order { 0 }

sub create {
    $dbh->do(<<"EOS");
DROP TABLE IF EXISTS affil_program;
EOS
    $dbh->do(<<"EOS");
CREATE TABLE affil_program (
a_id $idn,
p_id $idn
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<"EOS");
INSERT INTO affil_program
(a_id, p_id) 
VALUES
(?, ?)
EOS
}

1;
