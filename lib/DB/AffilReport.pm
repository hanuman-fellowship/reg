use strict;
use warnings;
package DB::AffilReport;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS affil_reports;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE affil_reports (
    affiliation_id
    report_id
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO affil_reports
(affiliation_id, report_id) 
VALUES
(?, ?)
EOS
}

1;
