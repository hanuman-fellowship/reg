use strict;
use warnings;
package RetreatCenterDB::Booking;
use base qw/DBIx::Class/;

use Date::Simple qw/date/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('booking');
__PACKAGE__->add_columns(qw/
    id
    meet_id
    rental_id
    program_id
    event_id
    sdate
    edate
    breakout
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to('meeting_place' =>  'RetreatCenterDB::MeetingPlace',
                        'meet_id');

# one of these 3 are non-zero
__PACKAGE__->belongs_to('rental' =>  'RetreatCenterDB::Rental',  'rental_id');
__PACKAGE__->belongs_to('program' => 'RetreatCenterDB::Program', 'program_id');
__PACKAGE__->belongs_to('event' =>   'RetreatCenterDB::Event',   'event_id');

sub sdate_obj {
    my ($self) = @_;
    return date($self->sdate);
}

sub edate_obj {
    my ($self) = @_;
    return date($self->edate);
}

1;
