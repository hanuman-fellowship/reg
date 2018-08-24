use strict;
use warnings;
package DBH;
use base 'Exporter';
our @EXPORT = qw/
    $dbh
    $idn
    $sdn
    $pk
/;

our ($dbh, $idn, $sdn, $pk);

use DBI;

sub init {
    finis();
    $dbh = DBI->connect($ENV{DBI_DSN}, "sahadev", "JonB")
        or die "cannot connect $DBI::errstr:(";
    $idn = "not null default 0";
    $sdn = "not null default ''";
    $pk = "integer primary key auto_increment not null";
}

sub finis {
    $dbh->disconnect() if $dbh;
}

1;
