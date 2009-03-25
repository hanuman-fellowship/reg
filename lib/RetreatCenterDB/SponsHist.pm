use strict;
use warnings;
package RetreatCenterDB::SponsHist;
use base qw/DBIx::Class/;

use Date::Simple qw/
    date
/;
use Time::Simple qw/
    get_time
/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('spons_hist');
__PACKAGE__->add_columns(qw/
    id
    member_id
    date_payment
    amount
    general
    user_id
    the_date
    time
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to('member' => 'RetreatCenterDB::Member', 'member_id');
__PACKAGE__->belongs_to('who'    => 'RetreatCenterDB::User',   'user_id');

sub date_payment_obj {
    my ($self) = @_;
    date($self->date_payment) || "";
}
sub the_date_obj {
    my ($self) = @_;
    date($self->the_date) || "";
}
sub time_obj {
    my ($self) = @_;
    return get_time($self->time());
}

1;
