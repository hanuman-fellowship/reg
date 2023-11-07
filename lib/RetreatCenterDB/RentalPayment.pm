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
use Util qw/
    penny
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
    transaction_id
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to(rental => 'RetreatCenterDB::Rental', 'rental_id');
__PACKAGE__->belongs_to(user   => 'RetreatCenterDB::User', 'user_id');

sub the_date_obj {
    my ($self) = @_;
    return date($self->the_date);
}

# the following methods are for deposits.
sub name {
    my ($self) = @_;
    my $r = $self->rental;
    my $p;
    if ($r->coordinator_id) {
        $p = $r->coordinator;
    }
    elsif ($r->cs_person_id) {
        $p = $r->contract_signer;
    }
    if ($p) {
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

sub amount_disp {
    my ($self) = @_;
    return penny($self->amount());
}

1;
__END__
overview - A payment to a Rental.
amount - dollar amount
id - unique id
rental_id - foreign key to rental
the_date - date the payment was made
time - time the payment was made
transaction_id - transaction id of online payment
type - D (credit), C (check), S (cash), O (online)
user_id - foreign key to user - the user who entered the payment
