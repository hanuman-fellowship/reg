use strict;
use warnings;
package RetreatCenterDB::Ride;

use base qw/DBIx::Class/;

use Date::Simple qw/
    date
/;
use Global qw/
    %string
/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('ride');
__PACKAGE__->add_columns(qw/
    id
    rider_id
    driver_id
    pickup_date
    pickup_time
    pickup_location
    dropoff_location
    cost
    type
/);
__PACKAGE__->set_primary_key(q/id/);

__PACKAGE__->belongs_to(driver => 'RetreatCenterDB::User',   'driver_id');
__PACKAGE__->belongs_to(rider  => 'RetreatCenterDB::Person', 'rider_id');

sub pickup_date_obj {
    my ($self) = @_;
    return date($self->pickup_date()) || "";
}
sub type_sh {
    my ($self) = @_;
    return $string{"payment_" . $self->type()};
}

1;
