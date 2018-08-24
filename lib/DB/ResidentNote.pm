use strict;
use warnings;
package DB::ResidentNote;
use DBH;

sub order { 0 }

sub create {
    $dbh->do(<<"EOS");
DROP TABLE IF EXISTS resident_note;
EOS
    $dbh->do(<<"EOS");
CREATE TABLE resident_note (
id integer primary key auto_increment,
resident_id integer,
the_date text,
the_time text,
note text
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<"EOS");
INSERT INTO resident_note
(id, resident_id, the_date, the_time, note) 
VALUES
(?, ?, ?, ?, ?)
EOS
}

1;
