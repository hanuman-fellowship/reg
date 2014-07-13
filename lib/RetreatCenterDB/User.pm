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
__PACKAGE__->has_many(rides => 'RetreatCenterDB::Ride', 'driver_id',
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

sub inactive {
    my ($self) = @_;
    return $self->password() eq '-no login-';
}

sub numbers {
    my ($self) = @_;
    return ($self->office && $self->cell)? "s are"
          :                                " is"
          ;
}

1;
__END__
overview - This contains the information for users of Reg.
    Username, password, personal colors, etc.
bg - RGB values for background
cell - cell phone number
email - email address
fg - RGB values for foreground
first - first name
hide_mmi - should MMI programs be hidden from you?
id - unique id
last - last name
link - RGB values for links
office - office phone number
password - password - in clear text :(
txt_msg_email - email address to send a text message to this person
username - the login name
