use strict;
use warnings;
package RetreatCenterDB::Donation;
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

# Load required DBIC stuff
__PACKAGE__->load_components(qw/PK::Auto Core/);
# Set the table name
__PACKAGE__->table('donation');
# Set columns in table
__PACKAGE__->add_columns(qw/
    id
    person_id
    project_id
    the_date
    amount
    type
    who_d
    date_d
    time_d
/);
# Set the primary key for the table
__PACKAGE__->set_primary_key(qw/id/);

#
# Set relationships:
#
__PACKAGE__->belongs_to(person  => 'RetreatCenterDB::Person',  'person_id');
__PACKAGE__->belongs_to(project => 'RetreatCenterDB::Project', 'project_id');
__PACKAGE__->belongs_to(who     => 'RetreatCenterDB::User',    'who_d');

sub the_date_obj {
    my ($self) = @_;
    date($self->the_date) || "";
}
sub date_d_obj {
    my ($self) = @_;
    return date($self->date_d) || "";
}
sub time_d_obj {
    my ($self) = @_;
    return get_time($self->time_d());
}
sub name {
    my ($self) = @_;
    my $per = $self->person;
    return $per->last . ", " . $per->first;
}
sub pname {
    my ($self) = @_;
    return $self->project->descr();
}
sub link {
    my ($self) = @_;
    return "/person/view/" . $self->person_id;
}
sub glnum {
    my ($self) = @_;
    return $self->project->glnum();
}
sub type_sh {
    my ($self) = @_;
    return $string{"payment_" . $self->type()};
}

1;
__END__
overview - Monies received from a person for a particular project.
    This is mostly obsolete - instead we are using Payments to Extra Accounts (XAccount).
amount - dollar amount
date_d - entry date
id - unique id
person_id - foreign key to person
project_id - foreign key to project
the_date - donation date
time_d - entry time
type - Check, Cash, Credit
who_d - who entered it - foreign key to user
