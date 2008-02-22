use strict;
use warnings;
package RetreatCenterDB::SponsHist;
use base qw/DBIx::Class/;

use Date::Simple qw/date/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('spons_hist');
__PACKAGE__->add_columns(qw/
    id
    member_id
    date_payment
    amount
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to('member' => 'RetreatCenterDB::Member', 'member_id');

sub date_payment_obj {
    my ($self) = @_;
    date($self->date_payment) || "";
}

1;
