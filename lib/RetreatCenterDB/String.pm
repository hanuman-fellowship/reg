use strict;
use warnings;
package RetreatCenterDB::String;

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('string');
__PACKAGE__->add_columns(qw/
    the_key
    value
/);

__PACKAGE__->set_primary_key('the_key');

1;
