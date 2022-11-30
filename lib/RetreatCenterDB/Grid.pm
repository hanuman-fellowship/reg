use strict;
use warnings;
package RetreatCenterDB::Grid;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('grid');
__PACKAGE__->add_columns(qw/
    rental_id
    house_id
    bed_num
    name
    notes
    occupancy
    cost
/);
__PACKAGE__->set_primary_key(qw/
    rental_id
    house_id
/);

__PACKAGE__->belongs_to(rental => 'RetreatCenterDB::Rental', 'rental_id');
__PACKAGE__->belongs_to(house  => 'RetreatCenterDB::House',  'house_id');

1;
__END__
overview - A Grid record represents a person assigned to a room
    and bed for the duration of a rental.  They may not be present
    for every night.
bed_num - bed number
cost - total cost for the duration of the rental
house_id - foreign key to house
name - the person's name
notes - email address, other notes
occupancy - a series of 0s and 1s representing presence each night
rental_id - foreign key to rental
