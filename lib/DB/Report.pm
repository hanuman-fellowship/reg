use strict;
use warnings;
package DB::Report;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS reports;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE reports (
    id
    descrip
    format
    zip_range
    rep_order
    nrecs
    update_cutoff
    end_update_cutoff
    last_run
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
