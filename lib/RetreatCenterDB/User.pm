use strict;
use warnings;
package RetreatCenterDB::User;

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('user');
__PACKAGE__->add_columns(qw/
    id
    username
    password
    email
    first
    last
/);
__PACKAGE__->set_primary_key('id');

__PACKAGE__->has_many(user_role => 'RetreatCenterDB::UserRole', 'user_id');
__PACKAGE__->many_to_many(roles => 'user_role', 'role',
                          { order_by => 'fullname' },
                         );
# ??? several tables have foreign keys
# to user table - should we have relationships here
# reflecting that?  cascade deletes?

1;
