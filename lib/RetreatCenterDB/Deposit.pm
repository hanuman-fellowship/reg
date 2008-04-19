use strict;
use warnings;
package RetreatCenterDB::Deposit;
use base qw/DBIx::Class/;

use Date::Simple qw/date/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('deposit');
__PACKAGE__->add_columns(qw/
    id
    user_id
    the_date
    time
    cash
    chk
    credit
    online
    total
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to('user' => 'RetreatCenterDB::User', 'user_id');

sub the_date_obj {
    my ($self) = @_;
    return date($self->the_date);
}

1;
