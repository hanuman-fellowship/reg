use strict;
use warnings;
package RetreatCenterDB::RequestedMMIPayment;
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
__PACKAGE__->table('req_mmi_payment');
__PACKAGE__->add_columns(qw/
    id
    person_id
    amount
    for_what
    the_date
    reg_id
    note
    code
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

sub for_what_disp {
    my ($self) = @_;

    my $what = $self->for_what();
    return ($what eq '1')? "Tuition"
          :($what eq '2')? "Meals and Lodging"
          :($what eq '3')? "Application Fee"
          :($what eq '4')? "Registration Fee"
          :($what eq '6')? "STRF"
          :($what eq '7')? "Recordings"
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

sub amount_disp {
    my ($self) = @_;
    penny($self->amount());
}

1;
__END__
overview - Payments for MMI programs can be sent to the registrant so
    they can pay online via authorize.net.  When the payment is made
    at authorize.net it is brought in automatically by Reg.
amount - dollar amount
code - a generated code sent to the person to identify the payment request
for_what - Tuition, Meals and Lodging, STRF, Recordings, Other
id - unique id
note - the reason for the charge
person_id - foreign key to person
reg_id - foreign key to registration
the_date - the date the request was sent
