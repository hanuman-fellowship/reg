use strict;
use warnings;
package DBH;
use base 'Exporter';
our @EXPORT = '$dbh';

use DBI;
our $dbh = DBI->connect(undef, "sahadev", "JonB")
    or die "cannot connect $DBI::errstr:(";

1;
