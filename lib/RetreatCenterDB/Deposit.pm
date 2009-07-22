use strict;
use warnings;
package RetreatCenterDB::Deposit;
use base qw/DBIx::Class/;

use Date::Simple qw/
    date
/;
use Time::Simple qw/
    get_time
/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('deposit');
__PACKAGE__->add_columns(qw/
    id
    user_id
    time
    date_start
    date_end
    cash
    chk
    credit
    online
    sponsor
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to('user' => 'RetreatCenterDB::User', 'user_id');

sub date_start_obj {
    my ($self) = @_;
    return date($self->date_start());
}
sub date_end_obj {
    my ($self) = @_;
    return date($self->date_end());
}
sub time_obj {
    my ($self) = @_;
    return get_time($self->time());
}
1;
