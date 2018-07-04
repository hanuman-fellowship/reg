use strict;
use warnings;
package DB::Leader;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS leader;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE leader (
    id
    person_id
    public_email
    url
    image
    biography
    assistant
    l_order
    just_first
    inactive
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO leader
(id, person_id, public_email, url, image, biography, assistant, l_order, just_first, inactive) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
