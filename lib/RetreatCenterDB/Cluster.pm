use strict;
use warnings;
package RetreatCenterDB::Cluster;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('cluster');
__PACKAGE__->add_columns(qw/
    id
    name
    color
    x
    y
/);
__PACKAGE__->set_primary_key(qw/id/);

sub color_bg {
    my ($self) = @_;
    sprintf("#%02x%02x%02x", $self->color =~ m{\d+}g);
}

1;
