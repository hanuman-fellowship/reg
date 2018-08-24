use strict;
use warnings;
package DB::Session;
use DBH;

sub order { 1 }

sub create {
    $dbh->do(<<"EOS");
DROP TABLE IF EXISTS sessions;
EOS
    $dbh->do(<<"EOS");
CREATE TABLE sessions (
    id char(72) primary key not null,
    session_data text null,
    expires integer(11) null
)
EOS
}

sub init {
}

1;
