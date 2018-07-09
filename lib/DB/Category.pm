use strict;
use warnings;
package DB::Category;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS category;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE category (
id integer primary key autoincrement,
name char(20)
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO category
(name) 
VALUES
(?)
EOS
    while (my $line = <DATA>) {
        chomp $line;
        my (@fields) = split /\|/, $line, -1;
        $sth->execute(@fields);
    }
}

1;

__DATA__
Normal
Resident
Intern
Temporary
