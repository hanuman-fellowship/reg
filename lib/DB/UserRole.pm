use strict;
use warnings;
package DB::UserRole;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS user_role;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE user_role (
    user_id
    role_id
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO user_role
(user_id, role_id) 
VALUES
(?, ?)
EOS
}

1;
