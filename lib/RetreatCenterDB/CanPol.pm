use strict;
use warnings;
package RetreatCenterDB::CanPol;
use base qw/DBIx::Class/;

# Load required DBIC stuff
__PACKAGE__->load_components(qw/PK::Auto Core/);
# Set the table name
__PACKAGE__->table('canpol');
# Set columns in table
__PACKAGE__->add_columns(qw/
    id
    name
    policy
/);
# Set the primary key for the table
__PACKAGE__->set_primary_key(qw/id/);

#
# Set relationships:
#
__PACKAGE__->has_many(programs => 'RetreatCenterDB::Program', 'canpol_id', 
    { order_by => 'descrip' });

1;
