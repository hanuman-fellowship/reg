use strict;
use warnings;
package RetreatCenterDB::Organization;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('organization');
__PACKAGE__->add_columns(qw/
    id
    name
    abbrev
    on_prog_cal
/);
__PACKAGE__->set_primary_key(qw/id/);

1;
