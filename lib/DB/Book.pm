use strict;
use warnings;
package DB::Book;
use DBH;

sub order { 0 }

sub create {
    $dbh->do(<<"EOS");
DROP TABLE IF EXISTS book;
EOS
    $dbh->do(<<"EOS");
CREATE TABLE book (
id $pk,
title varchar(255) $sdn,
author varchar(255) $sdn,
publisher varchar(255) $sdn,
location varchar(255) $sdn,
subject varchar(255) $sdn,
description text $sdn,
media tinyint $idn
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<"EOS");
INSERT INTO book
(id, title, author, publisher, location, subject, description, media) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
