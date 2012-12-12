use strict;
use warnings;
package RetreatCenterDB::Cluster;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('cluster');
__PACKAGE__->add_columns(qw/
    id
    name
    type
    cl_order
/);
__PACKAGE__->set_primary_key(qw/id/);

1;
__END__
cl_order - 
id - unique id
name - 
type - 
