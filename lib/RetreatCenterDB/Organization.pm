use strict;
use warnings;
package RetreatCenterDB::Organization;
use base qw/DBIx::Class/;
use Util qw/
    d3_to_hex
/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('organization');
__PACKAGE__->add_columns(qw/
    id
    name
    on_prog_cal
    color
/);
__PACKAGE__->set_primary_key(qw/id/);

sub bgcolor {
    my ($self) = @_;

    return d3_to_hex($self->color);
}

1;
