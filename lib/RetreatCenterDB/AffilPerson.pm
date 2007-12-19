use strict;
use warnings;
package RetreatCenterDB::AffilPerson;
use base qw/DBIx::Class/;

# Load required DBIC stuff
__PACKAGE__->load_components(qw/PK::Auto Core/);
# Set the table name
__PACKAGE__->table('affil_people');
# Set columns in table
__PACKAGE__->add_columns(qw/
    a_id
    p_id
/);
# Set the primary key for the table
__PACKAGE__->set_primary_key(qw/a_id p_id/);

#
# Set relationships:
#
__PACKAGE__->belongs_to(person => 'RetreatCenterDB::Person', 'p_id');
__PACKAGE__->belongs_to(affil  => 'RetreatCenterDB::Affil',  'a_id');


1;
