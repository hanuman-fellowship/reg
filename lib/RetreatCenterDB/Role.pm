use strict;
use warnings;
package RetreatCenterDB::Role;

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('roles');
__PACKAGE__->add_columns(qw/id role/);
__PACKAGE__->set_primary_key('id');

# has_many():
#   args:
#     1) Name of relationship, DBIC will create accessor with this name
#     2) Name of the model class referenced by this relationship
#     3) Column name in *foreign* table
__PACKAGE__->has_many(map_user_role => 'RetreatCenterDB::UserRole', 'role_id');

1;
