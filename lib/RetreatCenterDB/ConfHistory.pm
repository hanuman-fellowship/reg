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

__PACKAGE__->belongs_to(registration => 'RetreatCenterDB::Registration', 'reg_id');
__PACKAGE__->belongs_to(user => 'RetreatCenterDB::User', 'user_id');

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
overview - This table keeps track of the confirmation notes
    that were sent to a registrant.  Good for knowing what and when
    they were informed via the confirmation letter.
id - unique id
note - The text of the note that was sent in a confirmation letter.
reg_id - foreign key to registration
the_date - the date the history item was added
time - the time the history item was added
user_id - foreign key to user
