use strict;
use warnings;
package DB::Event;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS event;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE event (
    id
    name
    descr
    sdate
    edate
    sponsor
    organization_id
    max
    pr_alert
    user_id
    the_date
    time
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO event
(id, name, descr, sdate, edate, sponsor, organization_id, max, pr_alert, user_id, the_date, time) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
