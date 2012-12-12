use strict;
use warnings;
package RetreatCenterDB::ConfHistory;
use base qw/DBIx::Class/;

use Date::Simple qw/
    date
/;
use Time::Simple qw/
    get_time
/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('conf_history');
__PACKAGE__->add_columns(qw/
    id
    reg_id
    note
    user_id
    the_date
    time
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to('registration' => 'RetreatCenterDB::Registration', 'reg_id');
__PACKAGE__->belongs_to('user' => 'RetreatCenterDB::User', 'user_id');

sub the_date_obj {
    my ($self) = @_;
    return date($self->the_date);
}

sub time_obj {
    my ($self) = @_;
    get_time($self->time());
}

1;
__END__
id - unique id
note - 
reg_id - foreign key to registration
the_date - 
time - 
user_id - foreign key to user
