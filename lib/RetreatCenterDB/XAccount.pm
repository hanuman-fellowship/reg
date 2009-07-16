use strict;
use warnings;
package RetreatCenterDB::XAccount;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('xaccount');
__PACKAGE__->add_columns(qw/
    id
    descr
    glnum
    mmc
/);
# Set the primary key for the table
__PACKAGE__->set_primary_key(qw/id/);
__PACKAGE__->has_many(payments => 'RetreatCenterDB::XAccountPayment',
                      'xaccount_id',
                      { order_by => 'id desc' });

1;
