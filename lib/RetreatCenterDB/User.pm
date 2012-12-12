use strict;
use warnings;
package RetreatCenterDB::User;

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('user');
__PACKAGE__->add_columns(qw/
    id
    username
    password
    email
    first
    last
    bg
    fg
    link
    office
    cell
    txt_msg_email
    hide_mmi
/);
__PACKAGE__->set_primary_key('id');

__PACKAGE__->has_many(user_role => 'RetreatCenterDB::UserRole', 'user_id');
__PACKAGE__->many_to_many(roles => 'user_role', 'role',
                          { order_by => 'fullname' },
                         );
__PACKAGE__->has_many('rides' => 'RetreatCenterDB::Ride', 'driver_id',
                      { order_by => 'pickup_date desc' },
                     );
# ??? several tables have foreign keys
# to this user table - should we have relationships here
# reflecting that?  cascade deletes?

sub name_email {
    my ($self) = @_;
    return $self->name() . ' <' . $self->email() . '>';
}

sub name {
    my ($self) = @_;
    return $self->first() . ' ' . $self->last();
}

sub numbers {
    my ($self) = @_;
    return ($self->office && $self->cell)? "s are"
          :                                " is"
          ;
}

1;
__END__
bg - 
cell - 
email - 
fg - 
first - 
hide_mmi - 
id - unique id
last - 
link - 
office - 
password - 
txt_msg_email - 
username - 
