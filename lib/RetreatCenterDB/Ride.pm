use strict;
use warnings;
package RetreatCenterDB::Ride;

use base qw/DBIx::Class/;

use Date::Simple qw/
    date
/;
use Time::Simple;
use Global qw/
    %string
/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('ride');
__PACKAGE__->add_columns(qw/
    id
    rider_id
    driver_id
    from_to
    pickup_date
    airport
    carrier
    flight_num
    flight_time
    cost
    comment
    paid_date
/);
__PACKAGE__->set_primary_key(q/id/);

__PACKAGE__->belongs_to(driver => 'RetreatCenterDB::User',   'driver_id');
__PACKAGE__->belongs_to(rider  => 'RetreatCenterDB::Person', 'rider_id');

sub pickup_date_obj {
    return date(shift->pickup_date()) || "";
}
sub paid_date_obj {
    return date(shift->paid_date()) || "";
}
sub flight_time_obj {
    return Time::Simple->new(shift->flight_time()) || "";
}
sub type_sh {
    my ($self) = @_;
    return $string{"payment_" . $self->type()};
}

1;
