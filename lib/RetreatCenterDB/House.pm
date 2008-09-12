use strict;
use warnings;
package RetreatCenterDB::House;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('house');
__PACKAGE__->add_columns(qw/
    id
    name
    max
    bath
    tent
    center
    priority
    x
    y
    cluster_id
    cluster_order
    inactive
    disp_code
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to(cluster => 'RetreatCenterDB::Cluster', 'cluster_id');

sub name_disp {
    my ($self) = @_;
    my $name = $self->name();
    $name =~ s{(\d{3})[BH]+$}{$1};
    $name;
}

1;
