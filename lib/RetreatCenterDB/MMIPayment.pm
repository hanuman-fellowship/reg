use strict;
use warnings;
package RetreatCenterDB::MMIPayment;
use base qw/DBIx::Class/;

use Date::Simple qw/
    date
/;
use Global qw/
    %string
/;
use Util qw/
    penny
/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('mmi_payment');
__PACKAGE__->add_columns(qw/
    id
    person_id
    amount
    glnum
    the_date
    type
    deleted
    reg_id
    note
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to(person       => 'RetreatCenterDB::Person',
                        'person_id');
__PACKAGE__->belongs_to(registration => 'RetreatCenterDB::Registration',
                        'reg_id');

sub the_date_obj {
    my ($self) = @_;
    return date($self->the_date);
}

sub name {
    my ($self) = @_;
    my $per = $self->person;
    if (! $per) {
        return "Unknown";
    }
    return $per->last . ", " . $per->first;
}

sub for_what {
    my ($self) = @_;

    my $type = substr($self->glnum(), 0, 1);
    return ($type eq '1')? "Tuition"
          :($type eq '2')? "Meals and Lodging"
          :($type eq '3')? "Admin Fee"
          :($type eq '4')? "Clinic Fee"
          :                "Other"
          ;
}

sub pname {
    my ($self) = @_;
    if ($self->reg_id) {
        return $self->registration->program->name();
    }
    else {
        return "unknown MMI Program";
    }
}

sub link {
    my ($self) = @_;
    if ($self->reg_id) {
        return "/registration/view/" . $self->reg_id();
    }
    else {
        return "/person/view/" . $self->person_id();
    }
}

sub plink {
    my ($self) = @_;
    return "#";     # no where to go?
}

sub type_sh {
    my ($self) = @_;
    return $string{"payment_" . $self->type()};
}

sub amount_disp {
    my ($self) = @_;
    penny($self->amount());
}

1;
__END__
overview - A payment by a person to a registration in an MMI program.
amount - how much $?
deleted - an obsolete attribute?  was it ever used?
glnum - A General Ledger number for this payment - calculated by Util::calc_mmi_glnum().
id - unique id
note - a few words describing the purpose of the payment
person_id - foreign key to person
reg_id - foreign key to registration
the_date - when was it entered?
type - cash/credit/check/online
