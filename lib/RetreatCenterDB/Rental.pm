use strict;
use warnings;
package RetreatCenterDB::Rental;
use base qw/DBIx::Class/;

use Global qw/%string/;
use Util qw/
    tt_today
    places
    gptrim
    get_grid_file
    penny
/;
use Date::Simple qw/
    date
/;
use Time::Simple qw/
    get_time
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

    max
    expected

    balance

    contract_sent
    sent_by
    contract_received
    received_by
    tentative

    start_hour
    end_hour

    coordinator_id
    cs_person_id
    lunches
    status
    deposit
    summary_id

    mmc_does_reg
    program_id
    proposal_id

    color
    housing_note

    grid_code

    staff_ok
/);
    # the program_id, proposal_id above are just for jumping back and forth
    # so no belongs_to relationship needed

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
# program (maybe)
__PACKAGE__->belongs_to(program => 'RetreatCenterDB::Program', 'program_id');

# contract signer
__PACKAGE__->belongs_to(contract_signer => 'RetreatCenterDB::Person',
                        'cs_person_id');

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

# blocks
__PACKAGE__->has_many(blocks => 'RetreatCenterDB::Block',
                      'rental_id',
                      {
                          join     => 'house',
                          prefetch => 'house',
                          order_by => 'house.name'
                      }
                     );

# rental_bookings
__PACKAGE__->has_many(rental_bookings => 'RetreatCenterDB::RentalBooking',
                      'rental_id',
                      {
                          join     => 'house',
                          prefetch => 'house',
                          order_by => 'house.name'
                      }
                     );

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
sub any_lunches {
    my ($self) = @_;
    return $self->lunches() =~ m{1};
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
    return "/rental/view/" . $self->id();
}
sub event_type {
    return "rental";
}
sub meeting_places {
    my ($self, $breakout) = @_;
    places($self, $breakout);
}
sub extradays {     # see Program->dates()
    return 0;
}
sub desc {
	my ($self) = @_;
	my $desc = gptrim($self->webdesc);
	return "" unless $desc;
	"<span class='event_desc'>$desc</span>";
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
#
# returns an array of counts for each day of the rental
# if the web grid is not there or is empty use the
# count (as below) or failing that, the maximum.
#
sub daily_counts {
    my ($self) = @_;

    my $ndays = $self->edate() - $self->sdate();
    my $max = $self->expected() || $self->max();
    my $fname = get_grid_file($self->grid_code());
    my $in;
    if (! open($in, "<", $fname)) {
        return (($max) x ($ndays+1));
    }
    #
    # we take care of the final day below
    # the web grid does not have a # for that last day
    #
    my @counts = (0) x $ndays;
    my $tot_cost = 0;
    LINE:
    while (my $line = <$in>) {
        chomp $line;
        if ($line =~ s{(\d+)$}{}) {
            my $cost = $1;
            if (! $cost) {
                next LINE;
            }
            $tot_cost += $cost;
        }
        my $name = "";
        if ($line =~ s{^\d+\|\d+\|([^|]*)\|}{}) {
            $name = $1;
        }
        my $np = $name =~ tr/&/&/;
        ++$np;
        my @nights = split m{\|}, $line;
        for my $i (0 .. $#counts) {
            $counts[$i] += $np * $nights[$i];
        }
    }
    close $in;
    if ($tot_cost == 0) {
        return (($max) x ($ndays+1));
    }
    #
    # on the last day
    # the people who slept the night before will have breakfast
    # and maybe lunch.
    #
    push @counts, $counts[-1];
    return @counts;
}
sub count {
    my ($self) = @_;
    if ($self->expected()) {
        return $self->expected();
    }
    my @counts = $self->daily_counts();
    my $top = 0;
    for my $c (@counts) {
        if ($top < $c) {
            $top = $c;
        }
    }
    return $top;
}
sub status_td {
    my ($self) = @_;
    my $status = $self->status();
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

sub start_hour_obj {
    my ($self) = @_;
    get_time($self->start_hour());
}
sub end_hour_obj {
    my ($self) = @_;
    get_time($self->end_hour());
}
sub color_bg {
    my ($self) = @_;
    return sprintf("#%02x%02x%02x", $self->color() =~ m{(\d+)}g);
}
sub housing_note_trim {
    my ($self) = @_;
    gptrim($self->housing_note());
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

sub balance_disp {
    my ($self) = @_;
    penny($self->balance());
}

1;
