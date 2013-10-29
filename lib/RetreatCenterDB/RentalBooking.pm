use strict;
use warnings;
package RetreatCenterDB::RentalBooking;
use base qw/DBIx::Class/;

use Date::Simple qw/
    date
/;

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

__PACKAGE__->belongs_to(rental => 'RetreatCenterDB::Rental', 'rental_id');
__PACKAGE__->belongs_to(house  => 'RetreatCenterDB::House',  'house_id');

sub date_start_obj {
    my ($self) = @_;
    date($self->date_start) || "";
}
sub date_end_obj {
    my ($self) = @_;
    date($self->date_end) || "";
}

1;
__END__
overview - A rental booking reserves a house (all beds) for the rental.
    The table name probably should have been 'rental_house' and the
    model RentalHouse.
date_start - date house first needed
date_end - date house last needed (the day before the end date of the rental)
h_type - housing type - see the h_type field of Registration
house_id - foreign key to house
rental_id - foreign key to rental
