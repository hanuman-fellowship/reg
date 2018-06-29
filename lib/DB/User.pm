use strict;
use warnings;
package DB::User;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS user;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE user (
    id
    username
    password
    email
    first
    last
    bg
    fg
    link
    office
    cell
    txt_msg_email
    hide_mmi
    locked
    expiry_date
    nfails
    last_login_date
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO user
(id, username, password, email, first, last, bg, fg, link, office, cell, txt_msg_email, hide_mmi, locked, expiry_date, nfails, last_login_date) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
