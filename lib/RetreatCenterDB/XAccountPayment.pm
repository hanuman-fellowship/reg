use strict;
use warnings;
package RetreatCenterDB::XAccountPayment;
use base qw/DBIx::Class/;

use Date::Simple qw/date/;

#
# very similar to reg_payment
# need some kind of hierarchy???
#
__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('xaccount_payment');
__PACKAGE__->add_columns(qw/
    id
    xaccount_id
    person_id
    what
    amount
    type
    user_id
    the_date
    time
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to('xaccount' => 'RetreatCenterDB::XAccount', 'xaccount_id');
__PACKAGE__->belongs_to('person' => 'RetreatCenterDB::Person', 'person_id');
__PACKAGE__->belongs_to('user' => 'RetreatCenterDB::User', 'user_id');

sub the_date_obj {
    my ($self) = @_;
    return date($self->the_date);
}

1;
