use strict;
use warnings;
package DB::MakeUp;
use DBH;

sub order { 0 }

sub create {
    $dbh->do(<<"EOS");
DROP TABLE IF EXISTS make_up;
EOS
    $dbh->do(<<"EOS");
CREATE TABLE make_up (
house_id integer,
date_vacated text,
date_needed text,
refresh text
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<"EOS");
INSERT INTO make_up
(house_id, date_vacated, date_needed, refresh) 
VALUES
(?, ?, ?, ?)
EOS
}

1;
