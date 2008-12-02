use strict;
use warnings;
package RetreatCenter::Controller::Rental;
use base 'Catalyst::Controller';

use Date::Simple qw/
    date
/;
use Util qw/
    trim
    empty
    compute_glnum
    valid_email
    model
    meetingplace_table
    lunch_table
    add_config
    type_max
    max_type
    housing_types
    tt_today
/;
use Global qw/
    %string
/;
use POSIX;
use Template;

use lib '../../';       # so you can do a perl -c here.

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('list');
}

sub create : Local {
    my ($self, $c) = @_;

    $c->stash->{check_linked}      = "";
    $c->stash->{check_tentative}   = "checked";
    $c->stash->{housecost_opts} =
        [ model($c, 'HouseCost')->search(
            undef,
            { order_by => 'name' },
        ) ];
    $c->stash->{rental} = {     # double faked object
        housecost => { name => "Default" },
    };
    $c->stash->{form_action} = "create_do";
    $c->stash->{section}     = 3;   # lodging
    $c->stash->{template}    = "rental/create_edit.tt2";
}

my %hash;
my @mess;
sub _get_data {
    my ($c) = @_;

    %hash = %{ $c->request->params() };
    $hash{$_} =~ s{^\s*|\s*$}{}g for keys %hash;
    @mess = ();
    $hash{url} =~ s{^http://}{};
    $hash{email} = trim($hash{email});
    if (empty($hash{name})) {
        push @mess, "Name cannot be blank";
    }
    # dates are either blank or converted to d8 format
    for my $d (qw/ sdate edate contract_sent contract_received /) {
        my $fld = $hash{$d};
        if ($d =~ /date/ && $fld !~ /\S/) {
            push @mess, "missing date field";
            next;
        }
        if ($d eq 'edate') {
            Date::Simple->relative_date(date($hash{sdate}));
        }
        my $dt = date($fld);
        if ($d eq 'edate') {
            Date::Simple->relative_date();
        }
        if ($fld && ! $dt) {
            # tell them which date field is wrong???
            push @mess, "Invalid date: $fld";
            next;
        }
        $hash{$d} = $dt? $dt->as_d8()
                   :     "";
    }
    TIME:
    for my $t ($hash{start_hour}, $hash{end_hour}) {
        next TIME if empty($t);
        if ($t !~ m{\d+} || ($t < 1 || 12 < $t)) {
            push @mess, "Illegal time: $t";
        }
    }
    if (!@mess && $hash{sdate} > $hash{edate}) {
        push @mess, "End date must be after the Start date";
    }
    my $ndays = 0;
    if (!@mess) {
        $ndays = date($hash{edate}) - date($hash{sdate});
    }
    if ($hash{email} && ! valid_email($hash{email})) {
        push @mess, "Invalid email: $hash{email}";
    }
    if (! $hash{max} =~ m{^\d+$}) {
        push @mess, "Invalid maximum.";
    }
    if (! $hash{deposit} =~ m{^\d+$}) {
        push @mess, "Invalid deposit.";
    }
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
        my $s = $f;
        $s =~ s{^n_}{};
        if (! ($hash{$f} =~ m{^\d*$})) {
            $s =~ s{_}{ };
            $s =~ s{\b(\w)}{\u$1}g;
            $s =~ s{Dble}{Double};
            push @mess, "Illegal quantity for $s: $hash{$f}";
        }
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "rental/error.tt2";
    }
    $hash{linked}    = "" unless exists $hash{linked};
    $hash{tentative} = "" unless exists $hash{tentative};
}

sub create_do : Local {
    my ($self, $c) = @_;

    _get_data($c);
    return if @mess;

    delete $hash{section};      # irrelevant

    $hash{lunches} = "";

    $hash{glnum} = compute_glnum($c, $hash{sdate});

    if ($hash{contract_sent}) {
        $hash{sent_by} = $c->user->obj->id;
    }
    if ($hash{contract_received}) {
        $hash{received_by} = $c->user->obj->id;
    }
    my $sum = model($c, 'Summary')->create({
        date_updated => tt_today($c)->as_d8(),
        who_updated  => $c->user->obj->id,
        time_updated => sprintf "%02d:%02d", (localtime())[2, 1],
    });
    $hash{summary_id} = $sum->id;
    my $r = model($c, 'Rental')->create(\%hash);
    my $id = $r->id();
    #
    # we must ensure that there are config records
    # out to the end date of this rental.
    #
    add_config($c, $hash{edate});
    $c->response->redirect($c->uri_for("/rental/view/$id/3"));
}

sub _h24 {
    my ($s) = @_;

    my ($h) = $s =~ m{(\d+)};
    if ($h && 1 <= $h && $h <= 7) {
        $h += 12;
    }
    $h;
}

#
# there are several things to compute for the display
# update the balance in the record once you're done.
# and possible reset the status.
#
sub view : Local {
    my ($self, $c, $id, $section) = @_;

    Global->init($c);
    $section ||= 1;
    my $r = model($c, 'Rental')->find($id);

    my @payments = $r->payments;
    my $tot_payments = 0;
    for my $p (@payments) {
        $tot_payments += $p->amount;
    }

    my $tot_charges = 0;

    my $tot_other_charges = 0;
    my @charges = $r->charges;
    for my $p (@charges) {
        $tot_other_charges += $p->amount;
    }
    $tot_charges += $tot_other_charges;

    my $ndays = date($r->edate) - date($r->sdate);
    my $hc    = $r->housecost; 
    my $min_lodging = int(0.75
                          * $r->max
                          * $ndays
                          * $hc->dormitory
                         );
    my (%bookings, %booking_count);
    for my $b (model($c, 'RentalBooking')->search({
                   rental_id => $id,
               })
    ) {
        my $h_name = $b->house->name;
        my $h_type = $b->h_type;
        $bookings{$h_type} .= ("&nbsp;"x2)
                            . "<a href=/rental/del_booking/$id/"
                            . $b->house_id
                            . qq! onclick="return confirm('Okay to Delete booking of $h_name?');"!
                            . ">"
                            . $h_name
                            . "</a>,"
                            ;
        ++$booking_count{$h_type};
    }
    for my $t (keys %bookings) {
        chop $bookings{$t};     # final comma
        $bookings{$t} = ("&nbsp;"x3) . $bookings{$t};   # space after Add
    }
    #
    # now which clusters are assigned to this rental?
    #
    my @clusters = model($c, 'RentalCluster')->search({
                       rental_id => $id,
                   });
    my $clusters = "";
    for my $cl (@clusters) {
        my $cl_name = $cl->cluster->name;
        $clusters .= ("&nbsp;"x2)
                  .  "<a href=/rental/cluster_delete/$id/"
                  .  $cl->cluster_id
                  . qq! onclick="return confirm('Okay to Delete booking of cluster $cl_name?');"!
                  .  ">"
                  .  $cl_name
                  .  "</a>,"
                  ;
    }
    chop $clusters;     # final comma
    if ($clusters) {
        $clusters = ("&nbsp;"x3) . $clusters;   # space after Add
    }
    my %colcov;
    my $actual_lodging = 0;
    my $tot_people = 0;
    my $fmt = "#%02x%02x%02x";
    my $less = sprintf($fmt, $string{cov_less_color} =~ m{(\d+)}g);
    my $more = sprintf($fmt, $string{cov_more_color} =~ m{(\d+)}g);
    my $okay = sprintf($fmt, $string{cov_okay_color} =~ m{(\d+)}g);
    TYPE:
    for my $t (housing_types()) {
        next TYPE if $t eq "unknown";
        my $nt = "n_$t";
        my $npeople = $r->$nt || 0;
        $tot_people += $npeople;
        if ($hc->type eq 'Perday') {
            $actual_lodging += $hc->$t * $npeople * $ndays;
        }
        else {
            # Total
            $actual_lodging += $hc->$t * $npeople;
        }
        my $t_max = type_max($t);
        next TYPE if $t_max == 0;;
        my $needed = ceil($npeople/$t_max);
        my $count = $booking_count{$t} || 0;
        $colcov{$t} = ($needed < $count)? $less 
                     :($needed > $count)? $more
                     :                    $okay
                     ;
    }
    my $lodging = ($min_lodging > $actual_lodging)? $min_lodging
                :                                   $actual_lodging;

    $tot_charges += $lodging;

    my $extra_hours = 0;
    my $start = _h24($r->start_hour);
    my $end   = _h24($r->end_hour);
    if ($start && $start < 16) {
        $extra_hours += 16 - $start;
    }
    if ($end && 13 < $end) {
        $extra_hours += $end - 13;
    }
    my $extra_hours_charge = $extra_hours
                           * $tot_people
                           * $string{extra_hours_charge};

    $tot_charges += $extra_hours_charge;

    my $balance = $tot_charges - $tot_payments;

    # Lunches
    my $lunch_charge = 0;
    my $lunches = $r->lunches;
    if ($lunches =~ /1/) {
        $lunch_charge = $tot_people
                      * $string{lunch_charge}
                      * scalar($lunches =~ tr/1/1/);
        $tot_charges += $lunch_charge;
    }

    my $status;
    if ($r->tentative) {
        $status = "tentative";
    }
    elsif (! ($r->contract_sent())) {
        $status = "new";
    }
    elsif (! ($r->contract_received() && $r->payments() > 0)) {
        $status = "sent";
    }
    elsif (tt_today($c)->as_d8() > $r->edate()) {
        if ($balance != 0) {
            $status = "due";
        }
        else {
            $status = "done";
        }
    }
    else {
        $status = "received";
    }
    # ??? needed each view??? 
    # a rental_booking may have been done
    # housing costs could have changed...
    # the program might be finished.
    $r->update({
        balance => $balance,
        status  => $status,
    });

    $c->stash->{rental}         = $r;
    $c->stash->{daily_pic_date} = $r->sdate();
    $c->stash->{colcov}         = \%colcov;     # color of the coverage
    $c->stash->{bookings}       = \%bookings;
    $c->stash->{clusters}       = $clusters;
    $c->stash->{min_lodging}    = $min_lodging;
    $c->stash->{actual_lodging} = $actual_lodging;
    $c->stash->{lodging}        = $lodging;
    $c->stash->{extra_time}     = $extra_hours_charge;
    $c->stash->{lunch_charge}   = $lunch_charge;
    $c->stash->{charges}        = \@charges;
    $c->stash->{tot_other_charges} = $tot_other_charges;
    $c->stash->{tot_charges}    = $tot_charges;
    $c->stash->{payments}       = \@payments;
    $c->stash->{tot_payments}   = $tot_payments;
    $c->stash->{section}        = $section;
    $c->stash->{lunch_table}    = lunch_table(1, $r->lunches,
                                              $r->sdate_obj, $r->edate_obj);
    $c->stash->{template}       = "rental/view.tt2";
}

sub list : Local {
    my ($self, $c) = @_;

    Global->init($c);
    my $today = tt_today($c)->as_d8();
    $c->stash->{rentals} = [
        model($c, 'Rental')->search(
            { edate => { '>=', $today } },
            { order_by => 'sdate' },
        )
    ];
    $c->stash->{rent_pat} = "";
    $c->stash->{template} = "rental/list.tt2";
}

sub listpat : Local {
    my ($self, $c) = @_;

    my $rent_pat = $c->request->params->{rent_pat};
    if (empty($rent_pat)) {
        $c->forward('list');
        return;
    }
    my $cond;
    if ($rent_pat =~ m{(^[fs])(\d\d)}i) {
        my $seas = $1;
        my $year = $2;
        $seas = lc $seas;
        if ($year > 70) {
            $year += 1900;
        }
        else {
            $year += 2000;
        }
        my ($d1, $d2);
        if ($seas eq 'f') {
            $d1 = $year . '1001';
            $d2 = ($year+1) . '0331';
        }
        else {
            $d1 = $year . '0401';
            $d2 = $year . '0930';
        }
        $cond = {
            sdate => { 'between' => [ $d1, $d2 ] },
        };
    }
    elsif ($rent_pat =~ m{((\d\d)?\d\d)}) {
        my $year = $1;
        if ($year > 70 && $year <= 99) {
            $year += 1900;
        }
        elsif ($year < 70) {
            $year += 2000;
        }
        $cond = {
            sdate => { 'between' => [ "${year}0101", "${year}1231" ] },
        };
    }
    else {
        my $pat = $rent_pat;
        $pat =~ s{\*}{%}g;
        $cond = {
            name => { 'like' => "${pat}%" },
        };
    }
    $c->stash->{rentals} = [
        model($c, 'Rental')->search(
            $cond,
            { order_by => 'sdate desc' },
        )
    ];
    $c->stash->{rent_pat} = $rent_pat;
    $c->stash->{template} = "rental/list.tt2";
}

sub update : Local {
    my ($self, $c, $id, $section) = @_;

    my $p = model($c, 'Rental')->find($id);
    $c->stash->{rental} = $p;
    $c->stash->{"check_linked"}    = ($p->linked()   )? "checked"
                                        :               "";
    $c->stash->{"check_tentative"} = ($p->tentative())? "checked"
                                        :               "";
    $c->stash->{housecost_opts} =
        [ model($c, 'HouseCost')->search(
            undef,
            { order_by => 'name' },
        ) ];
    for my $w (qw/ sdate edate /) {
        $c->stash->{$w} = date($p->$w) || "";
    }
    $c->stash->{edit_gl}     = 1;
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{section}     = $section;
    $c->stash->{template}    = "rental/create_edit.tt2";
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    _get_data($c);
    return if @mess;

    my $section = $hash{section};
    delete $hash{section};

    my $r = model($c, 'Rental')->find($id);
    my $names = "";
    my $lunches = "";
    if (  $r->sdate ne $hash{sdate}
       || $r->edate ne $hash{edate}
       || $r->max   <  $hash{max}
    ) {
        # we have changed the dates of the rental or the max
        # and need to invalidate/remove any bookings for meeting spaces.
        # and lunches no longer apply...
        my @bookings = model($c, 'Booking')->search({
            rental_id => $id,
        });
        #
        # if only the max changed then we can keep the bookings
        # of meeting places that are still able to accomodate
        # the new max.
        #
        if (   $r->sdate eq $hash{sdate}
            && $r->edate eq $hash{edate}
        ) {
            @bookings = grep {
                            $_->meeting_place->max < $hash{max}
                        }
                        @bookings;
        }
        $names = join '<br>', map { $_->meeting_place->name } @bookings;
        for my $b (@bookings) {
            $b->delete();
        }
        if ($r->max >= $hash{max}) {
            # must have been a date
            $hash{lunches} = "";
            $lunches = 1;
        }
        #
        # and perhaps add a few more config records.
        #
        add_config($c, $hash{edate});
    }

    if ($hash{contract_sent} ne $r->contract_sent) {
        $hash{sent_by} = $c->user->obj->id;
    }
    if ($hash{contract_sent}) {
        # no longer tentative so force it!
        $hash{tentative} = "";
    }
    if ($hash{contract_received} ne $r->contract_received) {
        $hash{received_by} = $c->user->obj->id;
    }

    $r->update(\%hash);
    if ($names || $lunches) {
        $c->stash->{names}    = $names;
        $c->stash->{lunches}  = $lunches;
        $c->stash->{rental}   = $r;
        $c->stash->{template} = "rental/mp_warn.tt2";
    }
    else {
        $c->response->redirect($c->uri_for("/rental/view/"
                               . $r->id . "/$section"));
    }
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    my $r = model($c, 'Rental')->find($id);

    # bookings
    model($c, 'Booking')->search({
        rental_id => $id,
    })->delete();

    # the rental itself
    model($c, 'Rental')->search({
        id => $id,
    })->delete();

    $c->response->redirect($c->uri_for('/rental/list'));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

sub pay_balance : Local {
    my ($self, $c, $id) = @_;

    my $r = model($c, 'Rental')->find($id);
    $c->stash->{amount} = (tt_today($c)->as_d8() >= $r->edate)? $r->balance()
                         :                                      $r->deposit()
                         ;
    $c->stash->{rental} = $r;
    $c->stash->{template} = "rental/pay_balance.tt2";
}

sub pay_balance_do : Local {
    my ($self, $c, $id) = @_;

    my $amt = $c->request->params->{amount};
    my $type = $c->request->params->{type};

    my $today = tt_today($c);
    my $now_date = $today->as_d8();
    my ($hour, $min) = (localtime())[2, 1];
    my $now_time = sprintf "%02d:%02d", $hour, $min;

    model($c, 'RentalPayment')->create({

        rental_id => $id,
        amount    => $amt,
        type      => $type,

        user_id  => $c->user->obj->id,
        the_date => $now_date,
        time     => $now_time,
    });
    $c->response->redirect($c->uri_for("/rental/view/$id/3"));
}

sub meetingplace_update : Local {
    my ($self, $c, $id) = @_;

    my $r = $c->stash->{rental} = model($c, 'Rental')->find($id);
    $c->stash->{meetingplace_table}
        = meetingplace_table($c, $r->max, $r->sdate,
                             $r->edate, $r->bookings());
    $c->stash->{template} = "rental/meetingplace_update.tt2";
}

sub meetingplace_update_do : Local {
    my ($self, $c, $id) = @_;

    my $r = model($c, 'Rental')->find($id);
    my @cur_mps;
    my %seen = ();
    for my $k (sort keys %{$c->request->params}) {
        #
        # keys are like this:
        #     mp45
        # or
        #     mpbr23
        # all mp come before any mpbr
        #
        my ($d) = $k =~ m{(\d+)};
        my $br = ($k =~ m{br})? 'yes': '';
        push @cur_mps, [ $d, $br ] unless $seen{$d}++;
    }
    # delete all old bookings and create the new ones.
    model($c, 'Booking')->search(
        { rental_id => $id },
    )->delete();
    for my $mp (@cur_mps) {
        model($c, 'Booking')->create({
            meet_id    => $mp->[0],
            program_id => 0,
            rental_id  => $id,
            event_id   => 0,
            sdate      => $r->sdate,
            edate      => $r->edate,
            breakout   => $mp->[1],
        });
    }
    # show the rental again - with the updated meeting places
    $c->response->redirect($c->uri_for("/rental/view/$id/4"));
}

sub coordinator_update : Local {
    my ($self, $c, $id) = @_;

    $c->stash->{rental} = model($c, 'Rental')->find($id);
    $c->stash->{template} = "rental/coordinator_update.tt2";
}
sub coordinator_update_do : Local {
    my ($self, $c, $id) = @_;

    my $r = model($c, 'Rental')->find($id);
    my $first = trim($c->request->params->{first});
    my $last  = trim($c->request->params->{last});
    my ($person) = model($c, 'Person')->search({
                       first => $first,
                       last  => $last,
                   });
    if ($person) {
        $r->update({
            coordinator_id => $person->id,
        });
        $c->response->redirect($c->uri_for("/rental/view/$id/4"));
    }
    else {
        $c->stash->{template} = "rental/no_coord.tt2";
    }
}

sub new_charge : Local {
    my ($self, $c, $id) = @_;

    $c->stash->{rental} = model($c, 'Rental')->find($id);
    $c->stash->{template} = "rental/new_charge.tt2";
}
sub new_charge_do : Local {
    my ($self, $c, $id) = @_;

    my $amount = trim($c->request->params->{amount});
    my $what   = trim($c->request->params->{what});
    
    my @mess = ();
    if (empty($amount)) {
        push @mess, "Missing Amount";
    }
    if ($amount !~ m{^-?\d+$}) {
        push @mess, "Illegal Amount: $amount";
    }
    if (empty($what)) {
        push @mess, "Missing What";
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>", @mess;
        $c->stash->{template} = "registration/error.tt2";
        return;
    }

    my $today = tt_today($c);
    my $now_date = $today->as_d8();
    my ($hour, $min) = (localtime())[2, 1];
    my $now_time = sprintf "%02d:%02d", $hour, $min;

    model($c, 'RentalCharge')->create({
        rental_id => $id,
        amount    => $amount,
        what      => $what,

        user_id   => $c->user->obj->id,
        the_date  => $now_date,
        time      => $now_time,
    });
    $c->response->redirect($c->uri_for("/rental/view/$id/3"));
}

sub update_lunch : Local {
    my ($self, $c, $id) = @_;

    my $r = model($c, 'Rental')->find($id);
    $c->stash->{rental} = $r;
    $c->stash->{lunch_table} = lunch_table(0, $r->lunches,
                                          $r->sdate_obj, $r->edate_obj);
    $c->stash->{template} = "rental/update_lunch.tt2";
}

sub update_lunch_do : Local {
    my ($self, $c, $id) = @_;

    %hash = %{ $c->request->params() };
    my $r = model($c, 'Rental')->find($id);
    my $ndays = $r->edate_obj - $r->sdate_obj + 1;
    my $l = "";
    for my $n (0 .. $ndays-1) {
        $l .= (exists $hash{"d$n"})? "1": "0";
    }
    $r->update({
        lunches => $l,
    });
    $c->response->redirect($c->uri_for("/rental/view/$id/4"));
}

sub booking : Local {
    my ($self, $c, $id, $h_type) = @_;

    my $r = $c->stash->{rental} = model($c, 'Rental')->find($id);
    my $sdate = $r->sdate;
    my $edate1 = date($r->edate) - 1;
    $edate1 = $edate1->as_d8();     # could I put this on the above line???

    $c->stash->{h_type} = $h_type;
    my $bath   = ($h_type =~ m{bath}  )? "yes": "";
    my $tent   = ($h_type =~ m{tent}  )? "yes": "";
    my $center = ($h_type =~ m{center})? "yes": "";
    my $max    = type_max($h_type);
    #
    # look at a list of _possible_ houses for h_type.
    # ??? what order to present them in?  priority/resized?
    # consider cluster???  other bookings for this rental???
    #
    my $h_opts = "";
    my $n = 0;
    HOUSE:
    for my $h (model($c, 'House')->search({
                   inactive => '',
                   bath     => $bath,
                   tent     => $tent,
                   center   => $center,
                   max      => { '>=', $max },
               }) 
    ) {
        my $h_id = $h->id;
        #
        # is this house _completely_ available from sdate to edate1?
        # needs a thorough testing!
        #
        my @cf = model($c, 'Config')->search({
            house_id => $h_id,
            the_date => { 'between' => [ $sdate, $edate1 ] },
            cur      => { '>', 0 },
        });
        next HOUSE if @cf;        # nope

        $h_opts .= "<option value=" 
                 . $h_id
                 . ($h_opts eq ""? " selected": "")
                 . ">"
                 . $h->name
                 . "</option>"
                 ;
        ++$n;
    }
    $c->stash->{house_opts} = $h_opts;
    $c->stash->{n_opts} = $n;       # $n not always = # opts???
    $h_type =~ s{_(.)}{ \u$1};
    $c->stash->{disp_h_type} = (($h_type =~ m{^[aeiou]})? "an": "a")
                             . " '\u$h_type'";
    $c->stash->{template} = "rental/booking.tt2";
}

#
# actually make the booking
# add a RentalBooking record
# and update the sequence of Config records.
#
sub booking_do : Local {
    my ($self, $c, $rental_id, $h_type) = @_;
    my $chosen_house_id = $c->request->params->{chosen_house_id};
    my $h = model($c, 'House')->find($chosen_house_id);
    my $max = $h->max;
    my $r = model($c, 'Rental')->find($rental_id);
    my $sdate = $r->sdate;
    my $edate1 = date($r->edate) - 1;
    $edate1 = $edate1->as_d8();
    model($c, 'RentalBooking')->create({
        rental_id  => $rental_id,
        date_start => $sdate,
        date_end   => $edate1,
        house_id   => $chosen_house_id,
        h_type     => $h_type,
    });
    model($c, 'Config')->search({
        house_id => $chosen_house_id,
        the_date => { 'between' => [ $sdate, $edate1 ] },
    })->update({
        sex        => 'R',
        cur        => $max,
        curmax     => $max,
        program_id => 0,
        rental_id  => $rental_id,
    });
    $c->response->redirect($c->uri_for("/rental/view/$rental_id/3"));
}

sub del_booking : Local {
    my ($self, $c, $rental_id, $house_id) = @_;

    model($c, 'RentalBooking')->search({
        rental_id => $rental_id,
        house_id  => $house_id,
    })->delete();
    my $r = model($c, 'Rental')->find($rental_id);
    my $sdate = $r->sdate;
    my $edate1 = date($r->edate) - 1;
    $edate1 = $edate1->as_d8();
    my $h = model($c, 'House')->find($house_id);
    my $max = $h->max;
    model($c, 'Config')->search({
        house_id => $house_id,
        the_date => { 'between' => [ $sdate, $edate1 ] },
    })->update({
        sex        => 'U',
        cur        => 0,
        curmax     => $max,
        program_id => 0,
        rental_id  => $rental_id,
    });
    $c->response->redirect($c->uri_for("/rental/view/$rental_id/3"));
}

sub contract : Local {
    my ($self, $c, $id) = @_;

    my $rental = model($c, 'Rental')->find($id);
    my $html = "";
    my $tt = Template->new({
        INCLUDE_PATH => 'root/static/templates/letter',
        EVAL_PERL    => 0,
    });
    my %stash = (
        rental => $rental,
    );
    $tt->process(
        "rental_contract.tt2",# template
        \%stash,          # variables
        \$html,           # output
    );
    $c->res->output($html);
}

sub cluster_add : Local {
    my ($self, $c, $id) = @_;

    # get the date range from the rental
    # get all clusters
    # for each cluster:
    #     for each house in that cluster:
    #         for each config records of that house in the date range
    #             if cur != 0 the cluster is out.
    # all qualifying clusters go into the template
    #
    my $rental = model($c, 'Rental')->find($id);
    my $sdate = $rental->sdate();
    my $edate = $rental->edate();
    my @ok_clusters = ();
    CLUSTER:
    for my $cl (model($c, 'Cluster')->search(undef, { order_by => 'name' })) {
        for my $h (model($c, 'House')->search({ cluster_id => $cl->id })) {
            for my $cf (model($c, 'Config')->search({
                            house_id => $h->id,
                            the_date => { 'between', => [ $sdate, $edate ] },
                        })
            ) {
                if ($cf->cur() != 0) {
                    next CLUSTER;
                }
            }
        }
        push @ok_clusters, $cl;
    }
    $c->stash->{rental}   = $rental;
    $c->stash->{nclusters} = scalar(@ok_clusters);
    $c->stash->{clusters} = \@ok_clusters;
    $c->stash->{template} = "rental/cluster.tt2";
}

#
# for all chosen clusters:
#    mark the cluster for the rental
#    add all houses in that cluster to the rental bookings.
#    and update all the config records appropriately
#
sub cluster_add_do : Local {
    my ($self, $c, $rental_id) = @_;

    my $rental = model($c, 'Rental')->find($rental_id);
    my $sdate = $rental->sdate();
    my $edate1 = (date($rental->edate()) - 1)->as_d8();
                                            # they don't stay the last day!
    for my $cl_id (keys %{ $c->request->params()}) {
        $cl_id =~ s{^cl}{};
        model($c, 'RentalCluster')->create({
            rental_id  => $rental_id,
            cluster_id => $cl_id,
        });
        for my $h (model($c, 'House')->search({
                       cluster_id => $cl_id,
                   })
        ) {
            my $h_id = $h->id();
            my $h_max = $h->max();
            my $h_type = max_type($h_max, $h->bath(),
                                  $h->tent(), $h->center());
            model($c, 'RentalBooking')->create({
                rental_id  => $rental_id,
                house_id   => $h_id,
                date_start => $sdate,
                date_end   => $edate1,
                h_type     => $h_type,
            });
            model($c, 'Config')->search({
                house_id   => $h_id,
                the_date   => { 'between' => [ $sdate, $edate1 ] },
            })->update({
                sex        => 'R',
                cur        => $h_max,
                program_id => 0,
                rental_id  => $rental_id,
            });
        }
    }
    $c->response->redirect($c->uri_for("/rental/view/$rental_id/2"));
}

#
# remove the indicated RentalClust record
# for each house in the cluster
#     remove the RentalBooking record
#     adjust the config records for that house as well.
#
sub cluster_delete : Local {
    my ($self, $c, $rental_id, $cluster_id) = @_;

    my $rental = model($c, 'Rental')->find($rental_id);
    my $sdate = $rental->sdate();
    my $edate1 = (date($rental->edate()) - 1)->as_d8();
                                            # they don't stay the last day!
    model($c, 'RentalCluster')->search({
        rental_id  => $rental_id,
        cluster_id => $cluster_id,
    })->delete();
    for my $h (model($c, 'House')->search({
                   cluster_id => $cluster_id,
               })
    ) {
        my $h_id = $h->id();
        model($c, 'RentalBooking')->search({
            rental_id => $rental_id,
            house_id  => $h_id,
        })->delete();
        model($c, 'Config')->search({
            house_id => $h_id,
            the_date => { between => [ $sdate, $edate1 ] },
        })->update({
            sex => 'U',
            cur => 0,
            rental_id  => 0,
            program_id => 0,
        });
    }
    $c->response->redirect($c->uri_for("/rental/view/$rental_id/3"));
}

sub view_summary : Local {
    my ($self, $c, $id) = @_;

    my $rental = model($c, 'Rental')->find($id);
    $c->stash->{rental} = $rental;
    $c->stash->{daily_pic_date} = $rental->sdate();
    $c->stash->{summary} = $rental->summary();
    $c->stash->{template} = "rental/view_summary.tt2";
}

1;
