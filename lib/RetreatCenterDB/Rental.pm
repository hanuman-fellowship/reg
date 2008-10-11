use strict;
use warnings;
package RetreatCenterDB::Rental;
use base qw/DBIx::Class/;

use Global qw/%string/;
use Util qw/
    expand
    tt_today
/;
use Date::Simple qw/
    date
/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('rental');
__PACKAGE__->add_columns(qw/
    id
    name
    title
    subtitle
    glnum
    sdate
    edate
    url
    webdesc
    linked
    phone
    email
    comment
    housecost_id
    n_single_bath
    n_single
    n_dble_bath
    n_dble
    n_triple
    n_quad
    n_dormitory
    n_economy
    n_center_tent
    n_own_tent
    n_own_van
    n_commuting
    max

    balance

    contract_sent
    sent_by
    contract_received
    received_by
    tentative

    start_hour
    end_hour

    coordinator_id
    lunches
    status
    deposit
    summary_id
/);
# Set the primary key for the table
__PACKAGE__->set_primary_key(qw/id/);

# housing cost
__PACKAGE__->belongs_to(housecost => 'RetreatCenterDB::HouseCost',
                        'housecost_id');
# summary
__PACKAGE__->belongs_to('summary' => 'RetreatCenterDB::Summary', 'summary_id');

# coordinator
__PACKAGE__->belongs_to(coordinator => 'RetreatCenterDB::Person',
                        'coordinator_id');

# users
__PACKAGE__->belongs_to(sent_by => 'RetreatCenterDB::User',
                        'sent_by');
__PACKAGE__->belongs_to(received_by => 'RetreatCenterDB::User',
                        'received_by');

# payments
__PACKAGE__->has_many(payments => 'RetreatCenterDB::RentalPayment',
                      'rental_id',
                      { order_by => "id desc" });

# charges
__PACKAGE__->has_many(charges => 'RetreatCenterDB::RentalCharge',
                      'rental_id',
                      { order_by => "id desc" });

# bookings
__PACKAGE__->has_many(bookings => 'RetreatCenterDB::Booking', 'rental_id');

sub future_rentals {
    my ($class, $c) = @_;
    my @rentals = $c->model('RetreatCenterDB::Rental')->search(
        { sdate    => { '>=',    tt_today($c)->as_d8() } },
        { order_by => [ 'sdate', 'edate' ] },
    );
    @rentals;
}
sub sdate_obj {
    my ($self) = @_;
    return date($self->sdate) || "";
}
sub edate_obj {
    my ($self) = @_;
    return date($self->edate) || "";
}
sub contract_sent_obj {
    my ($self) = @_;
    return date($self->contract_sent) || "";
}
sub contract_received_obj {
    my ($self) = @_;
    return date($self->contract_received) || "";
}
sub link {
    my ($self) = @_;
    return "/rental/view/" . $self->id;
}
sub webdesc_br {
    my ($self) = @_;
    my $webdesc = $self->webdesc;
    $webdesc =~ s{\r?\n}{<br>\n}g;
    $webdesc;
}
sub comment_br {
    my ($self) = @_;
    my $comment = $self->comment;
    $comment =~ s{\r?\n}{<br>\n}g;
    $comment;
}
sub extradays {     # see Program->dates()
    return 0;
}
sub desc {
	my ($self) = @_;
	my $desc = expand($self->webdesc);
	return "" unless $desc;
	"<span class='event_desc'>$desc</span><br>";
}
sub weburl {
    my ($self) = @_;
    my $url = $self->url;
    return "" unless $url;
    return "<span class='event_website'>$string{website}: <a href='http://$url' target='_blank'>$url</a></span><br>";
}
sub email_str {
	my ($self) = @_;
	my $email = $self->email;
	return "" unless $email;
	return "<span class='event_email'>$string{email}: ".
		   "<a href='mailto:$email'>$email</a></span><br>";
}
sub phone_str {
	my ($self) = @_;
	my $phone = $self->phone;
	return "" unless $phone;
	"<span class='event_phone'>$string{phone}: $phone</span><br>";
}
sub title1 {
    my ($self) = @_;
    my $title = $self->title;
    my $url = $self->url;
    $title = "<a href='http://$url' target=_blank>$title</a>" if $url;
    $title;
}
sub title2 {
    my ($self) = @_;
    my $subtitle = $self->subtitle;
    return "" unless $subtitle;
    "<span class='event_subtitle'>$subtitle</span><br>";
}
#
# invoke the Program method by the same name.
# Rentals also have sdate and edate methods.
# no extradays but that's okay.
#
sub dates {
	my ($self) = @_;
	return RetreatCenterDB::Program::dates($self);
}
sub dates_tr {
	my ($self) = @_;
	return RetreatCenterDB::Program::dates_tr($self);
}
sub dates_tr2 {
	my ($self) = @_;
	return RetreatCenterDB::Program::dates_tr2($self);
}
sub count {
    my ($self) = @_;
    my $count = 0;
    for my $f (qw/
        n_single_bath
        n_single
        n_dble_bath
        n_dble
        n_triple
        n_quad
        n_dormitory
        n_economy
        n_center_tent
        n_own_tent
        n_own_van
        n_commuting
    /) {
        my $n = $self->$f;
        $count += $n if $n;
    }
    $count;
}
sub status_td {
    my ($self) = @_;
    my $status = $self->status;
    my $color = sprintf "#%02x%02x%02x",
                        $string{"rental_$status\_color"} =~ m{\d+}g;
    return "<td align=center bgcolor=$color>\u$status</td>";
}

#
# does this rental occur in the summer?
# i.e. are center tents available?
#
sub summer {
    my ($self) = @_;
    
    my $sdate = date($self->sdate);
    my $m = $sdate->month();
    return 5 <= $m && $m <= 10;
}

sub meeting_spaces {
    my ($self) = @_;

    my @places = map { $_->meeting_place->name } $self->bookings;
    if (@places == 1) {
        return $places[0];
    }
    elsif (@places == 2) {
        return "$places[0] and $places[1]";
    }
    else {
        my $last = pop @places;
        return join ", ", @places, " and $last";
    }
}

sub start_hour_disp {
    my ($self) = @_;
    my $h = $self->start_hour;
    $h ||= 4;
    _hour_disp($h);
}
sub end_hour_disp {
    my ($self) = @_;
    my $h = $self->end_hour;
    $h ||= 1;
    _hour_disp($h);
}

sub _hour_disp {
    my ($h) = @_;
    my $ampm = "pm";
    if (8 <= $h && $h <= 11) {
        $ampm = "am";
    }
    return "$h:00 $ampm";

}

#
# is the Seminar House one of the 
# main meeting places?
#
sub seminar_house {
    my ($self) = @_;
    for my $b ($self->bookings()) {
        if ($b->meeting_place->name =~ m{seminar\s+house}i) {
            return 1;
        }
    }
    return 0;
}

1;
