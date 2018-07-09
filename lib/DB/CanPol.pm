use strict;
use warnings;
package DB::CanPol;
use DBH '$dbh';

sub order { 1 }

sub create {
    $dbh->do(<<'EOS');
DROP TABLE IF EXISTS canpol;
EOS
    $dbh->do(<<'EOS');
CREATE TABLE canpol (
id integer primary key autoincrement,
name varchar(50),
policy varchar(300)
)
EOS
}

sub init {
    my $sth = $dbh->prepare(<<'EOS');
INSERT INTO canpol
(name, policy) 
VALUES
(?, ?)
EOS
    while (my $line = <DATA>) {
        chomp $line;
        my (@fields) = split /\|/, $line, -1;
        $sth->execute(@fields);
    }
}

1;

__DATA__
Default|<p>If you cancel there is no refund at all. &nbsp;Sorry.</p>
Special|<p>You will be refunded ALL of your money. &nbsp;No questions asked.</p>
