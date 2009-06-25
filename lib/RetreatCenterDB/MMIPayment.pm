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

__PACKAGE__->belongs_to('person'       => 'RetreatCenterDB::Person',
                        'person_id');
__PACKAGE__->belongs_to('registration' => 'RetreatCenterDB::Registration',
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
          :($type eq '3')? "Application Fee"
          :($type eq '4')? "Registration Fee"
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

1;
