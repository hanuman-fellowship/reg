use strict;
use warnings;
package DBH;
use base 'Exporter';
our @EXPORT = '$dbh';

our $dbh;

use DBI;

sub init {
    finis();
    $dbh = DBI->connect($ENV{DBI_DSN}, "sahadev", "JonB")
        or die "cannot connect $DBI::errstr:(";
}

sub finis {
    $dbh->disconnect() if $dbh;
}

1;
