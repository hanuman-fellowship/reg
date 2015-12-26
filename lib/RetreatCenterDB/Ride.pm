use strict;
use warnings;
package RetreatCenterDB::Ride;

use base qw/DBIx::Class/;

use Util qw/
    empty
    penny
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
    create_date
    create_time
    status
    luggage
    intl
    customs
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
sub create_date_obj {
    return date(shift->create_date()) || "";
}
sub create_time_obj {
    my ($self) = @_;
    my $t = $self->create_time();
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
           && ($self->cost() != 0 || $self->comment() =~ m{cancel}i)
           ;
}

sub cost_disp {
    my ($self) = @_;
    penny($self->cost());
}

1;
__END__
overview - People can request Rides to and/or from MMC.
airport - Which airport? SJC, SFO, OAK, or OTH (some non-airport place)
carrier - Which airline?
comment - free text
cost - dollar amount for the service
create_date - date the Ride was created
create_time - time the Ride was created
customs - are they going through Customs (for international flights)?
driver_id - foreign key to user
flight_num - Flight number
flight_time - Flight arrival/departure time
from_to - "From MMC" or "To MMC"
id - unique id
intl - Is this an international flight?
luggage - a description of the number and size of the person's luggage
paid_date - date the ride was paid for
pickup_date - date to be picked up
pickup_time - time to be picked up
rider_id - foreign key to person
sent_date - date the confirmation letter was sent
shuttle - which shuttle?  They are numbered from 1 to 10.
status - a short free text field describing the status of the ride (complete, need to pay, cancelled, etc)
type - payment type - D (Credit) C (Check) S (Cash) O (Online)
