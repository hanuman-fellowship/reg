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
    dorm
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to(meeting_place =>  'RetreatCenterDB::MeetingPlace',
                        'meet_id');

# one of these 3 are non-zero
__PACKAGE__->belongs_to(rental =>  'RetreatCenterDB::Rental',  'rental_id');
__PACKAGE__->belongs_to(program => 'RetreatCenterDB::Program', 'program_id');
__PACKAGE__->belongs_to(event =>   'RetreatCenterDB::Event',   'event_id');

sub sdate_obj {
    my ($self) = @_;
    return date($self->sdate);
}

sub edate_obj {
    my ($self) = @_;
    return date($self->edate);
}

sub date_range {
    my ($self) = @_;
    my $sdate = $self->sdate_obj();
    my $edate = $self->edate_obj();
    if ($sdate == $edate) {
        return $sdate->format("%b %e");
    }
    if ($sdate->month() eq $edate->month()) {
        return   $sdate->format("%b %e")
               . "-"
               . $edate->day();
    }
    return   $sdate->format("%b %e")
           . "-"
           . $edate->format("%b %e")
           ;
}

1;
__END__
overview - A record here reserves a meeting space for a program, rental, or event.
    All bookings take place in the Event controller.  A meeting space may be
    designated for sleeping as well - in which case there is a house
    with the same name as the abbreviation for the meeting place.
    If a booking is made for such a meeting space
    an automatic block on the similarily named house is created to prevent that
    housing from being used for sleeping.  And to confuse matters ... this block is not
    created if the booking is marked as a Dorm.
breakout - for a breakout space?
dorm - for a dorm?
edate - end date
event_id - foreign key to event
id - unique id
meet_id - foreign key to meeting_place
program_id - foreign key to program
rental_id - foreign key to rental
sdate - start date
