use strict;
use warnings;
package RetreatCenterDB::MMIPayment;
use base qw/DBIx::Class/;

use Date::Simple qw/
    date
/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('mmi_payment');
__PACKAGE__->add_columns(qw/
    id
    person_id
    amount
    gl
    payment_date
    cash
    deleted
    reg_id
    note
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to('person'       => 'RetreatCenterDB::Person',
                        'person_id');
__PACKAGE__->belongs_to('registration' => 'RetreatCenterDB::Registration',
                        'reg_id');

sub payment_date_obj {
    my ($self) = @_;
    return date($self->payment_date);
}

sub cash_disp {
    my ($self) = @_;

    my $cash = $self->cash();
    return ($cash eq 'D')? "Credit Card"
          :($cash eq 'C')? "Check"
          :($cash eq '$')? "Cash"
          :                "Online"
          ;
}

sub for_what {
    my ($self) = @_;

    my $type = substr($self->gl(), 0, 1);
    return ($type eq '1')? "Tuition"
          :($type eq '2')? "Meals and Lodging"
          :($type eq '3')? "Application Fee"
          :($type eq '4')? "Registration Fee"
          :                "Other"
          ;
}

1;
