use strict;
use warnings;
package RetreatCenterDB::RentalPayment;
use base qw/DBIx::Class/;

use Date::Simple qw/
    date
/;
use Time::Simple qw/
    get_time
/;
use Global qw/
    %string
/;

#
# very similar to reg_payment
# need some kind of hierarchy???
#
__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('rental_payment');
__PACKAGE__->add_columns(qw/
    id
    rental_id
    user_id
    the_date
    time
    amount
    type
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to('rental' => 'RetreatCenterDB::Rental', 'rental_id');
__PACKAGE__->belongs_to('user' => 'RetreatCenterDB::User', 'user_id');

sub the_date_obj {
    my ($self) = @_;
    return date($self->the_date);
}

# the following methods are for deposits.
sub name {
    my ($self) = @_;
    my $r = $self->rental;
    if ($r->coordinator_id) {
        my $p = $r->coordinator;
        return $p->last . ", " . $p->first;
    }
    else {
        return $r->name . " - Coordinator";
    }
}

sub link {
    my ($self) = @_;
    return "/rental/view/" . $self->rental_id() . "/3";
        # 3 above for the finance tab
}

# in Rentals link, plink are the same
sub plink {
    my ($self) = @_;
    return "/rental/view/" . $self->rental_id();
}

# same as name???   Need a leader name instead?
sub pname {
    my ($self) = @_;
    return $self->rental->name();
}

sub glnum {
    my ($self) = @_;
    return $self->rental->glnum();
}

sub type_sh {
    my ($self) = @_;
    return $string{"payment_" . $self->type()};
}

sub time_obj {
    my ($self) = @_;
    return get_time($self->time());
}

1;
