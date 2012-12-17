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
    descr
/);
__PACKAGE__->set_primary_key(q/id/);

__PACKAGE__->has_many(user_role => 'RetreatCenterDB::UserRole', 'role_id');
__PACKAGE__->many_to_many(users => 'user_role', 'user',
                          { order_by => 'first' });

sub descr_br {
    my ($self) = @_;
    my $descr = $self->descr;
    $descr =~ s{\r?\n}{<br>\n}g;
    $descr;
}

1;
__END__
overview - Users have a variety of roles which grant them access to areas of Reg.
descr - A longer description of purpose of the role.
fullname - a display version of the role column
id - unique id
role - a short key describing the role
