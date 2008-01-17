use strict;
use warnings;
package RetreatCenterDB::CanPol;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('canpol');
__PACKAGE__->add_columns(qw/
    id
    name
    policy
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->has_many(programs => 'RetreatCenterDB::Program', 'canpol_id', 
                      { order_by => 'name' });

1;
