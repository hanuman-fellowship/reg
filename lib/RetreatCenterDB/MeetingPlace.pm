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
    cost
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->has_many(bookings => 'RetreatCenterDB::Booking', 'meet_id');

1;
__END__
overview - A place reserved by a Program, Rental or Event for group gatherings.
    The reservations are made by creating Booking records.
abbr - A short name for the place.
color - RGB values for displaying the Meeting Place on the Calendar.
cost - dollar cost of reserving this place
disp_ord - What vertical space in the calendar?
id - unique id
max - Maximum # of people that can be accomodated.
name - Long name for the place.
sleep_too - Can this place be converted into a dorm for sleeping?
