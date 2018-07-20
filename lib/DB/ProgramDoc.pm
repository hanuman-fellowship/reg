use strict;
use warnings;
package DB::ProgramDoc;
use DBH '$dbh';

sub order { 0 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS program_doc;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE program_doc (
id integer primary key autoincrement,
program_id integer,
title text,
suffix text
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
