use strict;
use warnings;
package DB::Project;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS project;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE project (
    id
    descr
    glnum
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO project
(id, descr, glnum) 
VALUES
(?, ?, ?)
EOS
}

1;
