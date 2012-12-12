use strict;
use warnings;
package RetreatCenterDB::MeetingPlace;
use base qw/DBIx::Class/;

use Date::Simple qw/date/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('meeting_place');
__PACKAGE__->add_columns(qw/
    id
    abbr
    name
    max
    disp_ord
    sleep_too
    color
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->has_many(bookings => 'RetreatCenterDB::Booking', 'meet_id');

1;
__END__
abbr - 
color - 
disp_ord - 
id - unique id
max - 
name - 
sleep_too - 
