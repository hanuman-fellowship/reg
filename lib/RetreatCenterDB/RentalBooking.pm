use strict;
use warnings;
package RetreatCenterDB::RentalBooking;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('rental_booking');
__PACKAGE__->add_columns(qw/
    rental_id
    date_start
    date_end
    house_id
    h_type
/);
__PACKAGE__->set_primary_key(qw/
    rental_id
    house_id
/);

__PACKAGE__->belongs_to('rental' => 'RetreatCenterDB::Rental', 'rental_id');
__PACKAGE__->belongs_to('house'  => 'RetreatCenterDB::House',  'house_id');

1;
__END__
date_end - 
date_start - 
h_type - 
house_id - foreign key to house
rental_id - foreign key to rental
