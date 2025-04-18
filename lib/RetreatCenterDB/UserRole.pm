use strict;
use warnings;
package RetreatCenterDB::UserRole;

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('user_role');
__PACKAGE__->add_columns(qw/
    user_id
    role_id
/);

__PACKAGE__->belongs_to(user => 'RetreatCenterDB::User', 'user_id');
__PACKAGE__->belongs_to(role => 'RetreatCenterDB::Role', 'role_id');

1;
__END__
overview - A mapping table to enable Users to have multiple Roles.
role_id - foreign key to role
user_id - foreign key to user
