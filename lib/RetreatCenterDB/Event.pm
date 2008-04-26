use strict;
use warnings;
package RetreatCenterDB::Event;
use base qw/DBIx::Class/;

use Date::Simple qw/date/;
use DateRange;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('event');
__PACKAGE__->add_columns(qw/
    id
    name
    descr
    sdate
    edate
    sponsor
    user_id
    the_date
    time
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to('user' => 'RetreatCenterDB::User', 'user_id');

# bookings
__PACKAGE__->has_many(bookings => 'RetreatCenterDB::Booking', 'event_id');

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
    return DateRange->new($self->sdate_obj, $self->edate_obj);
}
sub link {
    my ($self) = @_;
    return "/event/view/" . $self->id;
}

sub the_date_obj {
    my ($self) = @_;
    return date($self->the_date);
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

1;
