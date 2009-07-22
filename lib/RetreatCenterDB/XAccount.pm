use strict;
use warnings;
package RetreatCenterDB::XAccount;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('xaccount');
__PACKAGE__->add_columns(qw/
    id
    descr
    glnum
    sponsor
/);
# Set the primary key for the table
__PACKAGE__->set_primary_key('id');

sub SPONSOR {
    my ($self) = @_;
    uc $self->sponsor();
}

1;
