use strict;
use warnings;
package RetreatCenterDB::Event;
use base qw/DBIx::Class/;

use Date::Simple qw/date/;
use Time::Simple qw/get_time/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('event');
__PACKAGE__->add_columns(qw/
    id
    name
    descr
    sdate
    edate
    sponsor
    organization_id
    max
    pr_alert
    user_id
    the_date
    time
/);
__PACKAGE__->set_primary_key(qw/id/);

# user who created
__PACKAGE__->belongs_to(user => 'RetreatCenterDB::User', 'user_id');

# organization
__PACKAGE__->belongs_to(organization   => 'RetreatCenterDB::Organization', 'organization_id');

# bookings
__PACKAGE__->has_many(bookings => 'RetreatCenterDB::Booking', 'event_id');

# blocks
__PACKAGE__->has_many(blocks => 'RetreatCenterDB::Block',
                      'event_id',
                      {
                          join     => 'house',
                          prefetch => 'house',
                          order_by => 'house.name',
                      }
                     );

sub the_date_obj {
    my ($self) = @_;
    return date($self->the_date);
}
sub time_obj { get_time(shift->time); }
sub sdate_obj {
    my ($self) = @_;
    return date($self->sdate);
}
sub edate_obj {
    my ($self) = @_;
    return date($self->edate);
}
sub descr_br {
    my ($self) = @_;
    my $descr = $self->descr;
    $descr =~ s{\r?\n}{<br>\n}g;
    $descr;
}

sub show {
    my ($self) = @_;
    return "<a href='/event/view/"
          . $self->id
          . "'>"
          . $self->name
          . "</a>";
}

sub count {
    my ($self) = @_;
    "";     # no count
}

sub title {
    my ($self) = @_;
    $self->descr;       # for the calendar
}

# will we have cancelled events?  that attr appeared in programs first.
sub cancelled {
    my ($self) = @_;
    return 0;
}

sub link {
    my ($self) = @_;
    return "/event/view/" . $self->id();
}
sub event_type {
    return "event";
}
sub Event_type {
    return "Event";
}

1;
__END__
overview - Something is happening at the center/school/institute that is not a Program or Rental.
    Events appear on the Calendar (or the Master calendar).  Events can reserve Meeting Spaces
    and can have Blocks to reserve Houses.
descr - longer description of the event
edate - end date
id - unique id
max - Max number of people (used for choosing a Meeting Place).
name - short name of the event
organization_id - foreign key to organization.
    The organization determines which calendar the event appears on.
pr_alert - This event has an effect on PRs.  This column contains
    text to 'pop up' when a person registers for a PR whose dates
    overlap with this event's dates.
sdate - start date
sponsor - obsolete - superceded by organization
user_id - which user added this event?
the_date - date the event was created
time - time the event was created
