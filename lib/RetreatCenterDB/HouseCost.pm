use strict;
use warnings;
package RetreatCenterDB::HouseCost;
use base qw/DBIx::Class/;

# Load required DBIC stuff
__PACKAGE__->load_components(qw/PK::Auto Core/);
# Set the table name
__PACKAGE__->table('housecost');
# Set columns in table
__PACKAGE__->add_columns(qw/
    id
    name
    single
    double
    triple
    quad
    dormitory
    economy
    center_tent
    own_tent
    own_van
    commuting
    unknown
    single_bath
    double_bath
    type
/);
# Set the primary key for the table
__PACKAGE__->set_primary_key(qw/id/);

#
# Set relationships:
#
__PACKAGE__->has_many(programs => 'RetreatCenterDB::Program', 'housecost_id', 
    { order_by => 'title' });

1;
