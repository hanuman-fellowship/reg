use strict;
use warnings;
package DB::Project;
use DBH '$dbh';

sub order { 0 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS project;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE project (
id integer primary key autoincrement,
descr text,
glnum text
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
