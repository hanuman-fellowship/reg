use strict;
use warnings;
package DB::Event;
use DBH;

sub order { 0 }

sub create {
    $dbh->do(<<"EOS");
DROP TABLE IF EXISTS event;
EOS
    $dbh->do(<<"EOS");
CREATE TABLE event (
id integer primary key auto_increment,
name text,
descr text,
sdate text,
edate text,
sponsor text,
organization_id integer,
max text,
pr_alert text,
user_id integer,
the_date text,
time text
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<"EOS");
INSERT INTO event
(id, name, descr, sdate, edate, sponsor, organization_id, max, pr_alert, user_id, the_date, time) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
