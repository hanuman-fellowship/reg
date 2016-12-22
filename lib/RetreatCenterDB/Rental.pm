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
    commify
    d3_to_hex
    housing_types
/;
use Date::Simple qw/
    date
    today
/;
use Time::Simple qw/
    get_time
/;
#use Net::Ping;

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
    rental_follows
    refresh_days
    cancelled

    fixed_cost_houses
    fch_encoded

    grid_stale
    pr_alert

    arrangement_sent
    arrangement_by
/);
    # the program_id, proposal_id above are just for jumping back and forth
    # so no belongs_to relationship needed

# Set the primary key for the table
__PACKAGE__->set_primary_key(qw/id/);

# housing cost
__PACKAGE__->belongs_to(housecost => 'RetreatCenterDB::HouseCost',
                        'housecost_id');
# summary
__PACKAGE__->belongs_to(summary => 'RetreatCenterDB::Summary', 'summary_id');

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
__PACKAGE__->belongs_to(arrangement_by => 'RetreatCenterDB::User',
                        'arrangement_by');

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

sub seminar_house_sleeping {
    my ($self) = @_;
    for my $b ($self->rental_bookings) {
        if ($b->house->name =~ /^SH/) {
            return 1;
        }
    }
    return 0;
}

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
sub arrangement_sent_obj {
    my ($self) = @_;
    return date($self->arrangement_sent) || "";
}
sub link {
    my ($self) = @_;
    return "/rental/view/" . $self->id();
}
sub event_type {
    return "rental";
}
sub rental_type {
    my ($self) = @_;
    my $type = "";
    if ($self->cancelled()) {
        $type .= "Cancelled ";
    }
    else {
        if ($self->program_id) {
            $type .= "Hybrid ";
        }
        if ($self->linked) {
            $type .= "<span style='color: green'>w</span> ";
        }
    }
    chop $type;
    return $type;
}
# see also - sub meeting_spaces
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

    my $ndays = ($self->edate_obj() - $self->sdate_obj()) || 1;
        # || 1 for Rentals that are only one day - everyone commutes
        # but they do eat.
    my $max = $self->expected() || $self->max();
    my $fname = get_grid_file($self->grid_code());
    my $in;
    if (! open($in, "<", $fname)) {
        if ($self->program_id) {
            return (0 x ($ndays+1));
        }
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
        my @peeps = split m{\&|\band\b}i, $name;
        my $np = @peeps;
        my @nights = split m{\|}, $line;
        for my $i (0 .. $#counts) {
            $counts[$i] += $np * $nights[$i];
        }
    }
    close $in;
    if ($tot_cost == 0) {
        if ($self->program_id) {
            # for hybrids the count is solely from the program registrations
            return (0 x ($ndays+1));
        }
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

    if ($self->cancelled()) {
        # it has been cancelled - ignore the web grid
        return 0;
    }
    my $prog_count = 0;
    if ($self->program_id()) {
        # Hybrid counts come from the program and also the web grid.
        #
        $prog_count = $self->program->count();
    }
    # the count is the population count when
    # the maximum number of people were present.
    #
    my @counts = $self->daily_counts();
    my $top = 0;
    for my $c (@counts) {
        if ($top < $c) {
            $top = $c;
        }
    }
    my $expected = $self->expected() || 0;
    if ($top > $expected) {
        return $top + $prog_count;
    }
    return $expected + $prog_count;
}
sub status_td {
    my ($self) = @_;
    my $status = $self->status();
    my $color = d3_to_hex($string{"rental_$status\_color"});
    return "<td align=center bgcolor=$color>\u$status</td>";
}

sub ndays_sent {
    my ($self) = @_;
    my $ndays = today() - $self->contract_sent_obj();
    if ($ndays == 0) {
        return "today";
    }
    elsif ($ndays == 1) {
        return "1 day ago";
    }
    else {
        return "$ndays days ago";
    }
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

# see also - sub meeting_places
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
    return d3_to_hex($self->color());
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
    commify($self->balance());
}

sub send_grid_data {
    my ($rental) = @_;
    
    #my $p = Net::Ping->new();
    #if (!$p->ping("mountmadonna.org")) {
    #    return;     # don't even try
    #}
    my $code = $rental->grid_code() . ".txt";
    open my $gd, ">", "/tmp/$code"
        or die "cannot create /tmp/$code: $!\n";
    print {$gd} "name " . $rental->name() . "\n";
    print {$gd} "id " . $rental->id() . "\n";
    my $coord = $rental->coordinator();
    if ($coord) {
        print {$gd} "first " . $coord->first() . "\n";
        print {$gd} "last " . $coord->last() . "\n";
    }
    else {
        print {$gd} "first \n";     # just leave them blank
        print {$gd} "last \n";
    }
    print {$gd} "sdate " . $rental->sdate() . "\n";
    print {$gd} "edate " . $rental->edate() . "\n";
    my $sd = substr($rental->sdate(), 4, 4);        # MMDD
    my $winter = ! (   $string{center_tent_start} <= $sd
                    && $sd                        <= $string{center_tent_end});
    my $hc = $rental->housecost();
    print {$gd} "housecost_type " . $hc->type() . "\n";
    HTYPE:
    for my $t (housing_types(1)) {
        if ($winter && $t eq 'center_tent') {
            next HTYPE;
            # see comment below about center_tent sites
            # being used during the winter.
        }
        print {$gd} "$t " . $hc->$t() . "\n";
    }
    # quick hack for fixed cost houses
    #
    print {$gd} "fixed_cost_houses ", $rental->fixed_cost_houses(), "\n";
    print {$gd} "fch_encoded ", $rental->fch_encoded(), "\n";

    for my $b ($rental->rental_bookings()) {
        my $house = $b->house;
        print {$gd}
                    $house->id()
            . "|" . $house->name_disp()
            . "|" . $house->max()
            . "|" . ($house->bath()    eq 'yes'? 1: 0)
            . "|" . ($house->tent()    eq 'yes'? 1: 0)
            . "|" . ((!$winter && $house->center()  eq 'yes')? 0: 1)
            . "\n"
            ;
            # the trickyness with $winter and center tents
            # was needed because of this:
            # for a BIG rental in April we may want to use
            # tent sites that are normally reserved for own tents.
            # we permit this - and, when sending the grid to
            # www.mountmadonna.org we morph center tent sites to own tent sites.
            # clear?
            #
    }
    close $gd;
    my $ftp = Net::FTP->new($string{ftp_site}, Passive => $string{ftp_passive})
        or die "cannot connect to $string{ftp_site}";    # not die???
    $ftp->login($string{ftp_login}, $string{ftp_password})
        or die "cannot login ", $ftp->message; # not die???
    $ftp->cwd($string{ftp_grid_dir}) or die "cwd";
    $ftp->ascii() or die "ascii";
    $ftp->put("/tmp/$code", $code) or die "put";
    $ftp->quit();
    unlink "/tmp/$code";
    $rental->update({
        grid_stale => '',
    });
}

sub set_grid_stale {
    my ($rental) = @_;
    $rental->update({
        grid_stale => 'yes',
    });
}


1;
__END__
overview - A rental is created when some other organization wants
    to rent the meeting space and housing at MMC.  These events are not
    sponsored nor advertised by the center.  Housing assignments are
    made by the coordinator by filling in a form on the global web.
    This information is brought into Reg periodically.
arrangement_sent - date that the arrangement letter was sent
arrangement_by - who sent the arrangement letter
balance - the outstanding balance
cancelled - boolean - was this rental cancelled?  Set/Unset by a menu link.
color - RGB values for the DailyPic display.
comment - free text describing the rental
contract_received - date the contract was received
contract_sent - date the contract was sent out
coordinator_id - foreign key to person
cs_person_id - foreign key to person
deposit - how much deposit is required?
edate - date the rental ends
email - email address for the rental to put on the little web page (if desired)
end_hour - time the rental will end (and people will leave)
expected - how many people are expected?
fch_encoded - the encoded form of fixed_cost_houses
fixed_cost_houses - lines describing houses with a fixed cost.
    designed specifically for economy dorms where there is only
    a pad on the floor.
glnum - a General Ledger number computed from the sdate
grid_code - a hard to guess code for the grid URL
grid_stale - is the web grid in need of refreshing?
housecost_id - foreign key to housecost
housing_note - free text describing any issues with the rental housing
id - unique id
linked - should this rental be included on the online Event calendar?
lunches - an encoded (essentially binary) field for when lunches are requested.
max - the maximum number of people expected.  this is used
    to determine the financial obligation of the renter.
mmc_does_reg - will we be doing registration for this event?
    if so, a parallel hybrid program will be created.
name - a brief name of the rental for internal purposes
phone - phone number for the web page, if wanted
pr_alert - This rental has an effect on PRs.  This column contains
    text to 'pop up' when a person registers for a PR whose dates
    overlap with this rentals's dates.
program_id - foreign key to program
proposal_id - foreign key to proposal
received_by - foreign key to user
refresh_days - what days should the bedding be refreshed?
    This is an encoded field similar to lunches.
    This is used for longer term rentals.
rental_follows - does another rental follow this one?
    used in generating the make up list.
sdate - date the rental starts
sent_by - foreign key to user
staff_ok - has the staff okayed this rental?
start_hour - time the rental begins
status - tentative, sent, received, due, done
subtitle - secondary description of the rental for the web
summary_id - foreign key to summary
tentative - has this rental not been confirmed yet?
    checked at first, unchecked automatically when a contract is sent out.
title - primary description of the rental for the web
url - a URL of the rental for the web
webdesc - a longer description of the rental for the web.
