use strict;
use warnings;
package RetreatCenterDB::Registration;
use base qw/DBIx::Class/;

# Load required DBIC stuff
__PACKAGE__->load_components(qw/PK::Auto Core/);
# Set the table name
__PACKAGE__->table('registration');
# Set columns in table
__PACKAGE__->add_columns(qw/
    id
    person_id
    program_id
    referral
    adsource
    kids
    comment
    confnote
    h_type
    h_name
    perday
    work_study
    manual
    carpool
    hascar
    arrived
    total
    date_postmark
    balance
    cancelled
    date_start
    date_end
    status
    ceu_license
/);
# Set the primary key for the table
__PACKAGE__->set_primary_key(qw/id/);

#
# Set relationships:
#
__PACKAGE__->belongs_to(person   => 'RetreatCenterDB::Person', 'person_id');
__PACKAGE__->belongs_to(program  => 'RetreatCenterDB::Program','program_id');

1;
