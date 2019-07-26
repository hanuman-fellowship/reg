use strict;
use warnings;
package RetreatCenterDB::XAccountPayment;
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
__PACKAGE__->table('xaccount_payment');
__PACKAGE__->add_columns(qw/
    id
    xaccount_id
    person_id
    what
    amount
    type
    user_id
    the_date
    time
    transaction_id
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to(xaccount => 'RetreatCenterDB::XAccount', 'xaccount_id');
__PACKAGE__->belongs_to(person   => 'RetreatCenterDB::Person', 'person_id');
__PACKAGE__->belongs_to(user     => 'RetreatCenterDB::User', 'user_id');

sub the_date_obj {
    my ($self) = @_;
    return date($self->the_date());
}

sub name {
    my ($self) = @_;

    my $per = $self->person;
    if ($per) {
        return $per->last . ", " . $per->first;
    }
    else {
        return "???";
    }
}

sub link {
    my ($self) = @_;
    return "/person/view/" . $self->person_id();
}

sub plink {
    my ($self) = @_;
    return "/xaccount/view/" . $self->xaccount_id();
}

sub pname {
    my ($self) = @_;
    return $self->xaccount->descr();
}

sub glnum {
    my ($self) = @_;
    return $self->xaccount->glnum();
}

sub type_sh {
    my ($self) = @_;
    $string{"payment_" . $self->type()};
}

sub time_obj {
    my ($self) = @_;
    return get_time($self->time());
}

sub amount_disp {
    my ($self) = @_;
    penny($self->amount());
}

1;
__END__
overview - People can make Payments to XAccounts.  An XAccountPayment record is created.
amount - dollar amount
id - unique id
person_id - foreign key to person
the_date - date of the payment
time - time of the payment
transaction_id - authorize.net transaction id for online payments
type - C (Check) D (Credit) O (Online) S (Cash)
user_id - foreign key to user
what - optional description of what the payment was for
xaccount_id - foreign key to xaccount
