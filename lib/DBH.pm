use strict;
use warnings;
package DBH;
use base 'Exporter';
our @EXPORT = '$dbh';

use DBI;
our $dbh = DBI->connect("dbi:SQLite:retreatcenter.db")
    or die "cannot connect $DBI::errstr:(";

1;
