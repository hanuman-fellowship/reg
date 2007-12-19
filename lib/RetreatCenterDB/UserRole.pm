use strict;
use warnings;
package RetreatCenterDB::UserRole;

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('user_roles');
__PACKAGE__->add_columns(qw/user_id role_id/);
__PACKAGE__->set_primary_key(qw/user_id role_id/);

# belongs_to():
#   args:
#     1) Name of relationship, DBIC will create accessor with this name
#     2) Name of the model class referenced by this relationship
#     3) Column name in *this* table
__PACKAGE__->belongs_to(user => 'RetreatCenterDB::User', 'user_id');

# belongs_to():
#   args:
#     1) Name of relationship, DBIC will create accessor with this name
#     2) Name of the model class referenced by this relationship
#     3) Column name in *this* table
__PACKAGE__->belongs_to(role => 'RetreatCenterDB::Role', 'role_id');

1;
