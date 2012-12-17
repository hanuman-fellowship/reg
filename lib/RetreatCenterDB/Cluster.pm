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
overview - Houses are grouped into Clusters (via the cluster_id on House).
    Each cluster has a type - indoors, outdoors, special, or resident.
    There is a DailyPic view for each cluster type.
    The view only includes houses whose cluster is of that type.
    See the Global.pm module - it initializes global hashes for accessing the clusters
    and houses within them.
cl_order - What order should this cluster be presented in the Cluster View?
id - unique id
name - a descriptive name for the category
type - indoors, outdoors, special, or resident
