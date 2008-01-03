use strict;
use warnings;
package RetreatCenterDB::Affil;
use base qw/DBIx::Class/;

# Load required DBIC stuff
__PACKAGE__->load_components(qw/PK::Auto Core/);
# Set the table name
__PACKAGE__->table('affils');
# Set columns in table
__PACKAGE__->add_columns(qw/
    id
    descrip
/);
# Set the primary key for the table
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->has_many(affil_person => 'RetreatCenterDB::AffilPerson', 'a_id');
__PACKAGE__->many_to_many(persons => 'affil_person', 'person');

1;
