use strict;
use warnings;
package DB::Report;
use DBH '$dbh';

sub order { 0 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS reports;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE reports (
id integer primary key autoincrement,
descrip text,
format text,
zip_range text,
rep_order text,
nrecs text,
update_cutoff text,
end_update_cutoff text,
last_run text
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO reports
(id, descrip, format, zip_range, rep_order, nrecs, update_cutoff, end_update_cutoff, last_run) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
