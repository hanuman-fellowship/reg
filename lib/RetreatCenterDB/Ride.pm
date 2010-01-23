use strict;
use warnings;
package RetreatCenterDB::Ride;

use base qw/DBIx::Class/;

use Util qw/
    empty
/;

use Date::Simple qw/
    date
/;
use Time::Simple qw/
    get_time
/;
use Global qw/
    %string
/;
use Algorithm::LUHN qw/
    is_valid
/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('ride');
__PACKAGE__->add_columns(qw/
    id
    rider_id
    driver_id
    from_to
    pickup_date
    pickup_time
    airport
    carrier
    flight_num
    flight_time
    cost
    type
    comment
    paid_date
    sent_date
    shuttle
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
sub sent_date_obj {
    return date(shift->sent_date()) || "";
}
sub flight_time_obj {
    my ($self) = @_;
    my $t = $self->flight_time();
    return empty($t)? ""
           :          get_time($t);
}
sub pickup_time_obj {
    my ($self) = @_;
    my $t = $self->pickup_time();
    return empty($t)? ""
           :          get_time($t);
}
sub type_sh {
    my ($self) = @_;
    return $string{"payment_" . $self->type()};
}
sub name {
    my ($self) = @_;
    my $rider = $self->rider;
    return $rider->last() . ", " . $rider->first();
}
sub link {
    my ($self) = @_;
    return "/ride/view/" . $self->id();
}
sub complete {
    my ($self) = @_;
    my $rider = $self->rider();
    return    $self->driver_id() != 0
           && ! empty($self->pickup_date())
           && ! empty($self->from_to())
           && ! empty($self->carrier())
           && ! empty($self->flight_num())
           && ! empty($self->flight_time())
           && $self->cost() != 0
# Don't require the Credit Card info before sending the confirmation letter...
#           && ! empty($rider->cc_number()) 
#           && ! empty($rider->cc_expire()) 
#           && ! empty($rider->cc_code()) 
#           && is_valid($rider->cc_number())
}

1;
