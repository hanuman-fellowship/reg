use strict;
use warnings;

package HousingNames;

use base 'Exporter';
our @EXPORT = qw/
    %housing_name
/;

# these also exist in Configuration > Strings
# get them from there?
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
    dble_cabin  => 'Double in Cabin',
    single      => 'Single',
    single_bath => 'Single w/ Bath',
    single_cabin => 'Single in Cabin',
    whole_cottage => 'Whole Cottage',
    single_cottage1 => 'Single Cottage 1',
    dble_cottage1 => 'Double Cottage 1',
    single_cottage2 => 'Single Cottage 2',
    dble_cottage2 => 'Double Cottage 2',
);

1;
