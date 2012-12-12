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
use Util qw/
    penny
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
sub cash_disp {
    penny(shift->cash());
}
sub chk_disp {
    penny(shift->chk());
}
sub credit_disp {
    penny(shift->credit());
}
sub online_disp {
    penny(shift->online());
}
1;
__END__
cash - 
chk - 
credit - 
date_end - 
date_start - 
id - unique id
online - 
sponsor - 
time - 
user_id - foreign key to user
