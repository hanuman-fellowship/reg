use strict;
use warnings;
package RetreatCenterDB::RentalCluster;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('rental_cluster');
__PACKAGE__->add_columns(qw/
    rental_id
    cluster_id
/);
__PACKAGE__->set_primary_key(qw/
    rental_id
    cluster_id
/);

__PACKAGE__->belongs_to('rental'  => 'RetreatCenterDB::Rental',  'rental_id');
__PACKAGE__->belongs_to('cluster' => 'RetreatCenterDB::Cluster', 'cluster_id');

1;
__END__
cluster_id - foreign key to cluster
rental_id - foreign key to rental
