use strict;
use warnings;
package DB::Book;
use DBH '$dbh';

sub order { 0 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS book;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE book (
id integer primary key autoincrement,
title text,
author text,
publisher text,
location text,
subject text,
description text,
media text
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO book
(id, title, author, publisher, location, subject, description, media) 
VALUES
(?, ?, ?, ?, ?, ?, ?, ?)
EOS
}

1;
