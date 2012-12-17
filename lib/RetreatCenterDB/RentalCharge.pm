use strict;
use warnings;
package RetreatCenterDB::RentalCharge;
use base qw/DBIx::Class/;

use Date::Simple qw/
    date
/;
use Time::Simple qw/
    get_time
/;
use Util qw/
    penny
/;

#
# very similar to reg_charge
# need some kind of hierarchy???  nyah.
#
__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('rental_charge');
__PACKAGE__->add_columns(qw/
    id
    rental_id
    amount
    what
    user_id
    the_date
    time
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to(rental => 'RetreatCenterDB::Rental', 'rental_id');
__PACKAGE__->belongs_to(user   => 'RetreatCenterDB::User',   'user_id');

sub the_date_obj {
    my ($self) = @_;
    return date($self->the_date);
}

sub time_obj {
    my ($self) = @_;
    return get_time($self->time());
}

sub amount_disp {
    my ($self) = @_;
    return penny($self->amount());
}

1;
__END__
overview - 
amount - 
id - unique id
rental_id - foreign key to rental
the_date - 
time - 
user_id - foreign key to user
what - 
