use strict;
use warnings;
package RetreatCenterDB::Leader;
use base qw/DBIx::Class/;

# Load required DBIC stuff
__PACKAGE__->load_components(qw/PK::Auto Core/);
# Set the table name
__PACKAGE__->table('leader');
# Set columns in table
__PACKAGE__->add_columns(qw/
    id
    person_id
    public_email
    url
    image
    biography
/);
# Set the primary key for the table
__PACKAGE__->set_primary_key(qw/id/);

# relationships
__PACKAGE__->has_many(leader_program => 'RetreatCenterDB::LeaderProgram',
                      'l_id');
__PACKAGE__->many_to_many(programs => 'leader_program', 'program');

__PACKAGE__->belongs_to('person' => 'RetreatCenterDB::Person', 'person_id');

1;
