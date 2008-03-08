use strict;
use warnings;
package RetreatCenterDB::NightHist;
use base qw/DBIx::Class/;

use Date::Simple qw/date/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('night_hist');
__PACKAGE__->add_columns(qw/
    id
    member_id
    reg_id
    num_nights
    action
    user_id
    the_date
    time
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to('member' => 'RetreatCenterDB::Member', 'member_id');
__PACKAGE__->belongs_to('registration' => 'RetreatCenterDB::Registration', 'reg_id');
__PACKAGE__->belongs_to('who'    => 'RetreatCenterDB::User',   'user_id');

sub the_date_obj {
    my ($self) = @_;
    date($self->the_date()) || "";
}

sub action_str {
    my ($self) = @_;
    my $n = $self->action();
    return ($n == 1)? "Set Nights"
          :($n == 2)? "Take Nights"
          :($n == 3)? "Clear Free Program"
          :           "Take Free Program";
}

1;
