use strict;
use warnings;
package RetreatCenterDB::Donation;
use base qw/DBIx::Class/;

use Date::Simple qw/date/;

# Load required DBIC stuff
__PACKAGE__->load_components(qw/PK::Auto Core/);
# Set the table name
__PACKAGE__->table('donation');
# Set columns in table
__PACKAGE__->add_columns(qw/
    id
    person_id
    project_id
    date_donate
    amount

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

sub date_donate_obj {
    my ($self) = @_;
    date($self->date_donate) || "";
}
sub date_d_obj {
    my ($self) = @_;
    date($self->date_d) || "";
}

1;
