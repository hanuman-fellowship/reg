use strict;
use warnings;

package HousingNames;

use base 'Exporter';
our @EXPORT = qw/
    %housing_name
/;

our %housing_name = (
    commuting   => 'Commuting',
    own_van     => 'Own Van',
    own_tent    => 'Own Tent',
    center_tent => 'Center Tent',
    dormitory   => 'Dormitory',
    economy     => 'Economy',
    triple      => 'Triple',
    dble        => 'Double',
    dble_bath   => 'Double w/ Bath',
    single      => 'Single',
    single_bath => 'Single w/ Bath',
);

1;
