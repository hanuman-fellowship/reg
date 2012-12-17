use strict;
use warnings;
package RetreatCenterDB::ProgramCluster;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('program_cluster');
__PACKAGE__->add_columns(qw/
    program_id
    cluster_id
    seq
/);
__PACKAGE__->set_primary_key(qw/
    program_id
    cluster_id
/);

__PACKAGE__->belongs_to(program => 'RetreatCenterDB::Program', 'program_id');
__PACKAGE__->belongs_to(cluster => 'RetreatCenterDB::Cluster', 'cluster_id');

1;
__END__
overview - A mapping table between cluster and program
    by which programs can reserve housing clusters so that
    other programs and rentals can't access the houses
    in those clusters.  Or at least, they won't be offered them.
    A lodging FORCE or a Block can always get at them.
cluster_id - foreign key to cluster
program_id - foreign key to program
seq - obsolete?  I don't see it used anywhere.
