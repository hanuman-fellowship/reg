use strict;
use warnings;
package DB::ProgramDoc;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS program_doc;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE program_doc (
    id
    program_id
    title
    suffix
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO program_doc
(id, program_id, title, suffix) 
VALUES
(?, ?, ?, ?)
EOS
}

1;
