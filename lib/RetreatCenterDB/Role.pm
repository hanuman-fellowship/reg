use strict;
use warnings;
package RetreatCenterDB::Role;

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('role');
__PACKAGE__->add_columns(qw/
    id
    role
    fullname
    desc
/);
__PACKAGE__->set_primary_key('id');

__PACKAGE__->has_many(user_role => 'RetreatCenterDB::UserRole', 'role_id');
__PACKAGE__->many_to_many(users => 'user_role', 'user');

sub desc_br {
    my ($self) = @_;
    my $desc = $self->desc;
    $desc =~ s{\r?\n}{<br>\n}g;
    $desc;
}

1;
