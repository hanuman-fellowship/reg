use strict;
use warnings;
package DB::UserRole;
use DBH '$dbh';

sub order { 1 }     # but no init()

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS user_role;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE user_role (
user_id integer,
role_id integer
)
EOS
}

sub init {
    return;     # see User
}

1;
