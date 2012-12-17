use strict;
use warnings;
package RetreatCenterDB::NightHist;
use base qw/DBIx::Class/;

use Date::Simple qw/
    date
/;
use Time::Simple qw/
    get_time
/;

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

__PACKAGE__->belongs_to(member => 'RetreatCenterDB::Member', 'member_id');
__PACKAGE__->belongs_to(registration => 'RetreatCenterDB::Registration', 'reg_id');
__PACKAGE__->belongs_to(who    => 'RetreatCenterDB::User',   'user_id');

sub the_date_obj {
    my ($self) = @_;
    return date($self->the_date()) || "";
}
sub time_obj {
    my ($self) = @_;
    return get_time($self->time());
}

sub action_str {
    my ($self) = @_;
    my $n = $self->action();
    return ($n == 1)? "Set Nights"
          :($n == 2)? "Take Nights"
          :($n == 3)? "Clear Free Program"
          :($n == 4)? "Take Free Program"
          :($n == 5)? "Set Free Program"
          :           "Unknown action";
}

1;
__END__
overview - This table records actions that affect a member's free nights and free program.
action - a number from 1 to 5 indicating the action
    <ol>
    <li>Set Nights
    <li>Take Nights
    <li>Clear Free Program
    <li>Take Free Program
    <li>Set Free Program
    </ol>
id - unique id
member_id - foreign key to member
num_nights - how many nights?
reg_id - foreign key to registration - i.e. for which program the nights were taken.
the_date - date this record was created
time - time this record was created
user_id - foreign key to user
