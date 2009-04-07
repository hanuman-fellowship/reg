use strict;
use warnings;
package RetreatCenter::Controller::Rental;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.

use Date::Simple qw/
    date
    today
/;
use Time::Simple qw/
    get_time
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
    commify
    stash
    payment_warning
/;
use Global qw/
    %string
/;
use POSIX;
use Template;
use CGI qw/:html/;      # for Tr, td

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('list');
}

my %P;
my @mess;
sub _get_data {
    my ($c) = @_;

    %P = %{ $c->request->params() };
    $P{$_} = trim($P{$_}) for keys %P;
    @mess = ();
    $P{url} =~ s{^http://}{};
    if (empty($P{name})) {
        push @mess, "Name cannot be blank";
    }
    # dates are either blank or converted to d8 format
    for my $d (qw/ sdate edate contract_sent contract_received /) {
        my $fld = $P{$d};
        if ($d =~ /date/ && $fld !~ /\S/) {
            push @mess, "missing date field";
            next;
        }
        if ($d eq 'edate') {
            Date::Simple->relative_date(date($P{sdate}));
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
        $P{$d} = $dt? $dt->as_d8()
                   :     "";
    }
    TIME:
    for my $n (qw/start_hour end_hour/) {
        my $t = $P{$n};
        if (empty($t)) {
            my $sn = $n;
            $sn =~ s{_}{ };
            $sn =~ s{\b(\w)}{uc $1}eg;  # pretty good!
            push @mess, "Missing $sn";
            next;
        }
        my $tm = get_time($t);
        if (! $tm) {
            push @mess, Time::Simple->error();
        }
        $P{$n} = $tm->t24();
    }
    if (!@mess && $P{sdate} > $P{edate}) {
        push @mess, "End date must be after the Start date";
    }
    my $rental_ndays = 0;
    if (!@mess) {
        $rental_ndays = date($P{edate}) - date($P{sdate});
    }
    if ($P{email} && ! valid_email($P{email})) {
        push @mess, "Invalid email: $P{email}";
    }
    if (! $P{max} =~ m{^\d+$}) {
        push @mess, "Invalid maximum.";
    }
    if (! $P{deposit} =~ m{^\d+$}) {
        push @mess, "Invalid deposit.";
    }
    H_TYPE:
    for my $t (housing_types(1)) {
        my $npeople;
        if ($P{"n_$t"} !~ m{^\d*$}) {
            push @mess, "$string{$t}: Illegal quantity: " . $P{"n_$t"};
        }
        else {
            $npeople = $P{"h_$t"};
        }
        #
        # Attendance
        #
        if ($P{"att_$t"}) {
            my @terms = split m{\s*,\s*}, $P{"att_$t"};
            my $total_peeps = 0;
            TERM:
            for my $tm (@terms) {
                if ($tm !~ m{^(\d+)\s*c?\s*x\s*(\d+)}i) {
                    push @mess, "$string{$t}:"
                               ." Illegal attendance: " . $P{"att_$t"};
                    next H_TYPE;
                }
                my ($t_npeople, $t_ndays) = ($1, $2);
                $total_peeps += $t_npeople;

                # we may not have a valid $rental_ndays so be careful
                if (!@mess && $t_ndays > $rental_ndays) {
                    push @mess, "$string{$t}:"
                               ." Attendance > # days of rental: $t_ndays";
                }
            }
            # It IS okay to have more people in the 'attendance' field
            # than the '# of people' field.  Perhaps someone left early
            # and this changed the attendance tallies.  Like this:
            #
            # 2 people in a double the entire 5 days.
            # 3 people in triple.  1 leaves the 5 day program after 2 days.
            # We need this:
            #
            # Double    2    2x5, 2x3
            # Triple    3    1x2, 3x2
            #
            # If NO 'attendance' field at all - assume they stayed the
            # whole time. If there IS an attendance field you'll need to
            # specify even those who stayed the full time.
            #
            # the '# of people' field is used to determine the need
            # for room reservations.  It in combination with the 'attendance'
            # field is used for the invoice cost calculations.
            #
            if ($total_peeps < $P{"n_$t"}) {
                push @mess, "$string{$t}: "
                           ."Total people in non-blank attendance field"
                           ." < # of people";
            }
        }
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "rental/error.tt2";
    }
    # checkboxes are not sent at all if not checked
    #
    $P{linked}       = "" unless exists $P{linked};
    $P{tentative}    = "" unless exists $P{tentative};
    $P{mmc_does_reg} = "" unless exists $P{mmc_does_reg};
}

sub create : Local {
    my ($self, $c) = @_;

    stash($c,
        check_linked     => '',
        check_tentative  => "checked",
        form_action      => "create_do",
        section          => 1,   # web
        template         => "rental/create_edit.tt2",
        h_types          => [ housing_types(1) ],
        string           => \%string,
        housecost_opts   =>
            [ model($c, 'HouseCost')->search(
                {
                    inactive => { '!=' => 'yes' },
                },
                { order_by => 'name' },
            ) ],
        rental => {     # double faked object
            start_hour_obj => $string{rental_start_hour},
            end_hour_obj   => $string{rental_end_hour},
                # see comment in Program.pm in create().
        },
        check_mmc_does_reg => '',
    );
}

sub create_do : Local {
    my ($self, $c) = @_;

    _get_data($c);
    return if @mess;

    my $section = $P{section};
    delete $P{section};

    $P{lunches} = "";

    $P{glnum} = compute_glnum($c, $P{sdate});

    if ($P{contract_sent}) {
        $P{sent_by} = $c->user->obj->id;
    }
    if ($P{contract_received}) {
        $P{received_by} = $c->user->obj->id;
    }
    my $sum = model($c, 'Summary')->create({
        date_updated => tt_today($c)->as_d8(),
        who_updated  => $c->user->obj->id,
        time_updated => get_time()->t24(),
    });
    $P{summary_id} = $sum->id;
    $P{status} = "tentative";
    my $r = model($c, 'Rental')->create(\%P);
    my $id = $r->id();
    #
    # we must ensure that there are config records
    # out to the end date of this rental.
    #
    add_config($c, $P{edate});
    if ($P{mmc_does_reg}) {
        $c->response->redirect($c->uri_for("/program/parallel/$id"));
    }
    else {
        $c->response->redirect($c->uri_for("/rental/view/$id/$section"));
    }
}

sub create_from_proposal : Local {
    my ($self, $c, $proposal_id) = @_;

    my $proposal = model($c, 'Proposal')->find($proposal_id);

    _get_data($c);
    return if @mess;

    my $section = $P{section};
    delete $P{section};

    $P{lunches} = "";

    $P{glnum} = compute_glnum($c, $P{sdate});

    if ($P{contract_sent}) {
        $P{sent_by} = $c->user->obj->id;
    }
    if ($P{contract_received}) {
        $P{received_by} = $c->user->obj->id;
    }
    my $misc = $proposal->misc_notes();
    if (my $prov = $proposal->provisos()) {
        $misc =~ s{\s*$}{};      # trim the end
        $misc .= "\n\n$prov";
    }
    my $sum = model($c, 'Summary')->create({
        date_updated   => tt_today($c)->as_d8(),
        who_updated    => $c->user->obj->id,
        time_updated   => get_time()->t24(),

        special_needs  => $proposal->special_needs(),
        food_service   => $proposal->food_service(),
        miscellaneous  => $misc,
        leader_housing => $proposal->leader_housing(),

        # perhaps utilise other attributes from the proposal
        # in the creation of the Summary???
    });
    $P{summary_id}     = $sum->id();
    $P{coordinator_id} = $proposal->person_id();
    $P{cs_person_id}   = $proposal->cs_person_id();
    $P{status}         = "tentative";       # it is new.
    $P{proposal_id}    = $proposal_id;      # to link back to Proposal

    my $r = model($c, 'Rental')->create(\%P);
    my $rental_id = $r->id();
    #
    # update the proposal with the rental_id
    #
    $proposal->update({
        rental_id => $rental_id,
    });
    #
    # we must ensure that there are config records
    # out to the end date of this rental.
    #
    add_config($c, $P{edate});

    # are we done yet?
    #
    if ($P{mmc_does_reg}) {
        # no, make the parallel program
        #
        $c->response->redirect($c->uri_for("/program/parallel/$rental_id"));
    }
    else {
        # yes, so show the newly created rental
        #
        $c->response->redirect($c->uri_for("/rental/view/$rental_id/$section"));
    }
}

#
# there are several things to compute for the display
# update the balance in the record once you're done.
# and possibly reset the status.
#
sub view : Local {
    my ($self, $c, $id, $section) = @_;

    Global->init($c);
    $section ||= 1;
    my $rental = model($c, 'Rental')->find($id);

    my @payments = $rental->payments;
    my $tot_payments = 0;
    for my $p (@payments) {
        $tot_payments += $p->amount;
    }

    my $tot_other_charges = 0;
    my @charges = $rental->charges;
    for my $p (@charges) {
        $tot_other_charges += $p->amount;
    }

    my $ndays = date($rental->edate) - date($rental->sdate);
    my $hc    = $rental->housecost(); 
    my $min_lodging = int(0.75
                          * $rental->max
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
    my $att_days = 0;
    my @h_types = housing_types(1);
    TYPE:
    for my $t (@h_types) {
        my $nt = "n_$t";
        my $npeople = $rental->$nt || 0;
        $tot_people += $npeople;
        if ($hc->type eq 'Per Day') {
            $actual_lodging += $hc->$t * $npeople * $ndays;
        }
        else {
            # Total
            $actual_lodging += $hc->$t * $npeople;
        }
        my $t_max = type_max($t);
        next TYPE if !$t_max;
        my $needed = ceil($npeople/$t_max);
        my $count = $booking_count{$t} || 0;
        $colcov{$t} = ($needed < $count)? $less 
                     :($needed > $count)? $more
                     :                    $okay
                     ;
        my $meth = "att_$t";
        my $att = $rental->$meth();
        if (empty($att)) {
            $att_days += $npeople * $ndays;
        }
        else {
            my @terms = split m{\s*,\s*}, $att;
            for my $term (@terms) {
                my ($np, $nd) = split m{\s*x\s*}i, $term;
                $np =~ s{\s}{};
                my $children = $np =~ s{c}{}i;
                $att_days += $np * $nd;
            }
        }
    }
    my $lodging = ($min_lodging > $actual_lodging)? $min_lodging
                :                                   $actual_lodging;

    # Lunches
    my $lunch_charge = 0;
    my $lunches = $rental->lunches();
    if ($lunches =~ /1/) {
        $lunch_charge = $tot_people
                      * $string{lunch_charge}
                      * scalar($lunches =~ tr/1/1/);
    }

    my $status;
    if ($rental->tentative || ! $rental->contract_sent) {
        $status = "tentative";
    }
    elsif (! ($rental->contract_received() && $rental->payments() > 0)) {
        $status = "sent";
    }
    elsif (tt_today($c)->as_d8() > $rental->edate()) {
        if ($rental->balance() != 0) {
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
    $rental->update({
        status  => $status,
    });

    #
    # is there a proposal (as yet unlinked to a rental)
    # with the exact same name as this rental?
    # if so, we provide a link named "Link Proposal"
    # with which we can connect the two.
    #
    my @proposals = model($c, 'Proposal')->search({
        -or => [
            rental_id => 0,
            rental_id => undef,
        ],
        group_name => $rental->name(),
    });
    if (@proposals) {
        $c->stash->{link_proposal_id} = $proposals[0]->id();
    }

    stash($c,
        rental         => $rental,
        non_att_days   => $tot_people*$ndays - $att_days,
        daily_pic_date => $rental->sdate(),
        cal_param      => $rental->sdate_obj->as_d8() . "/1",
        colcov         => \%colcov,     # color of the coverage
        bookings       => \%bookings,
        clusters       => $clusters,
        h_types        => \@h_types,
        string         => \%string,
        lunch_charge   => $lunch_charge,
        charges        => \@charges,
        tot_other_charges => $tot_other_charges,
        payments       => \@payments,
        tot_payments   => $tot_payments,
        section        => $section,
        lunch_table    => lunch_table(
                              1,
                              $rental->lunches(),
                              $rental->sdate_obj(),
                              $rental->edate_obj(),
                              $rental->start_hour_obj(),
                          ),
        template       => "rental/view.tt2",
    );
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

    my $r = model($c, 'Rental')->find($id);
    stash($c,
        rental      => $r,
        edit_gl     => 1,
        form_action => "update_do/$id",
        section     => $section,
        h_types     => [ housing_types(1) ],
        string      => \%string,
        template    => "rental/create_edit.tt2",
        check_linked    => ($r->linked()   )? "checked": "",
        check_tentative => ($r->tentative())? "checked": "",
        check_mmc_does_reg => ($r->mmc_does_reg())? "checked": "",
        housecost_opts  =>
            [ model($c, 'HouseCost')->search(
                {
                    inactive => { '!=' => 'yes' },
                },
                { order_by => 'name' },
            ) ],
    );
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    _get_data($c);
    return if @mess;

    my $section = $P{section};
    delete $P{section};

    my $r = model($c, 'Rental')->find($id);
    my $names = "";
    my $lunches = "";
    if (  $r->sdate ne $P{sdate}
       || $r->edate ne $P{edate}
       || $r->max   <  $P{max}
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
        if (   $r->sdate eq $P{sdate}
            && $r->edate eq $P{edate}
        ) {
            @bookings = grep {
                            $_->meeting_place->max < $P{max}
                        }
                        @bookings;
        }
        $names = join '<br>', map { $_->meeting_place->name } @bookings;
        for my $b (@bookings) {
            $b->delete();
        }
        if ($r->max >= $P{max}) {
            # must have been a date
            $P{lunches} = "";
            $lunches = 1;
        }
        #
        # and perhaps add a few more config records.
        #
        add_config($c, $P{edate});
    }

    if ($P{contract_sent} ne $r->contract_sent) {
        $P{sent_by} = $c->user->obj->id;
    }
    if ($P{contract_sent}) {
        # no longer tentative so force it!
        $P{tentative} = "";
    }
    if ($P{contract_received} ne $r->contract_received) {
        $P{received_by} = $c->user->obj->id;
    }

    my $mmc_does_reg_b4 = $r->mmc_does_reg();      # before the update

    $r->update(\%P);
    if ($names || $lunches) {
        $c->stash->{names}    = $names;
        $c->stash->{lunches}  = $lunches;
        $c->stash->{rental}   = $r;
        $c->stash->{template} = "rental/mp_warn.tt2";
    }
    elsif (! $mmc_does_reg_b4 && $P{mmc_does_reg} && ! $r->program_id()) {
        $c->response->redirect($c->uri_for("/program/parallel/$id"));
    }
    else {
        $c->response->redirect($c->uri_for("/rental/view/$id/$section"));
    }
    # Note... if someone changes lunches, dates, and mmc_does_reg
    # all at the same time they are asking for trouble!
}

# what about the proposal that gave rise to this rental???
# at least make the rental_id field 0 in the proposal.
sub delete : Local {
    my ($self, $c, $id) = @_;

    my $r = model($c, 'Rental')->find($id);

    # multiple bookings
    model($c, 'Booking')->search({
        rental_id => $id,
    })->delete();

    # the summary
    $r->summary->delete();

    # and the rental itself
    # does this cascade to rental payments???
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
    stash($c,
        message  => payment_warning($c),
        amount   => (tt_today($c)->as_d8() >= $r->edate)? $r->balance()
                    :                                     $r->deposit(),
        rental   => $r,
        template => "rental/pay_balance.tt2",
    );
}

sub pay_balance_do : Local {
    my ($self, $c, $id) = @_;

    my $amt = $c->request->params->{amount};
    my $type = $c->request->params->{type};

    my $today = tt_today($c);
    my $now_date = $today->as_d8();
    if (tt_today($c)->as_d8() eq $string{last_deposit_date}) {
        $now_date = (tt_today($c)+1)->as_d8();
    }
    my $now_time = get_time()->t24();

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
    $c->response->redirect($c->uri_for("/rental/view/$id/2"));
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
    if (empty($first) && empty($last)) {
        $r->update({
            coordinator_id => 0,
        });
        $c->response->redirect($c->uri_for("/rental/view/$id/2"));
        return;
    }
    my ($person) = model($c, 'Person')->search({
                       first => $first,
                       last  => $last,
                   });
    if ($person) {
        $r->update({
            coordinator_id => $person->id,
        });
        $c->response->redirect($c->uri_for("/rental/view/$id/2"));
    }
    else {
        $c->stash->{template} = "rental/no_coord.tt2";
    }
}

sub contract_signer_update : Local {
    my ($self, $c, $id) = @_;

    $c->stash->{rental} = model($c, 'Rental')->find($id);
    $c->stash->{template} = "rental/contract_signer_update.tt2";
}
sub contract_signer_update_do : Local {
    my ($self, $c, $id) = @_;

    my $r = model($c, 'Rental')->find($id);
    my $first = trim($c->request->params->{first});
    my $last  = trim($c->request->params->{last});
    if (empty($first) && empty($last)) {
        $r->update({
            cs_person_id => 0,
        });
        $c->response->redirect($c->uri_for("/rental/view/$id/2"));
        return;
    }
    my ($person) = model($c, 'Person')->search({
                       first => $first,
                       last  => $last,
                   });
    if ($person) {
        $r->update({
            cs_person_id => $person->id,
        });
        $c->response->redirect($c->uri_for("/rental/view/$id/2"));
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
    my $now_time = get_time()->t24();

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
    $c->stash->{lunch_table}
        = lunch_table(0,
                      $r->lunches,
                      $r->sdate_obj,
                      $r->edate_obj,
                      $r->start_hour_obj(),
          );
    $c->stash->{template} = "rental/update_lunch.tt2";
}

sub update_lunch_do : Local {
    my ($self, $c, $id) = @_;

    %P = %{ $c->request->params() };
    my $r = model($c, 'Rental')->find($id);
    my $ndays = $r->edate_obj - $r->sdate_obj;
    my $l = "";
    for my $n (0 .. $ndays) {
        $l .= (exists $P{"d$n"})? "1": "0";
    }
    $r->update({
        lunches => $l,
    });
    $c->response->redirect($c->uri_for("/rental/view/$id/1"));
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
    my @h_opts = ();
    HOUSE:
    for my $h (model($c, 'House')->search({
                   inactive => '',
                   bath     => $bath,
                   tent     => $tent,
                   center   => $center,
                   max      => { '>=', $max },
               },
               { order_by => 'priority' }
              ) 
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

        push @h_opts,
                 "<option value=" 
                 . $h_id
                 . ">"
                 . $h->name
                 . (($h->max == $max)? "": " - R")
                 . "</option>\n"
                 ;
    }
    my @R_opts   = grep { /- R/ } @h_opts;
    my @noR_opts = grep { ! /- R/ } @h_opts;
    $c->stash->{house_opts} = join '', @noR_opts, @R_opts;
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

    # since we could have multiple houses at once
    # we have to mess around.
    # the param could be either an array ref or a scalar.?
    #
    my @chosen_house_ids = ();
    my $chid = $c->request->params->{chosen_house_id};
    if (ref($chid)) {
        @chosen_house_ids = @$chid;
    }
    else {
        @chosen_house_ids = $chid;
    }
    if (! @chosen_house_ids) {
        $c->response->redirect($c->uri_for("/rental/view/$rental_id/1"));
        return;
    }
    for my $h_id (@chosen_house_ids) {
        my $h = model($c, 'House')->find($h_id);
        my $max = $h->max;
        my $r = model($c, 'Rental')->find($rental_id);
        my $sdate = $r->sdate;
        my $edate1 = date($r->edate) - 1;
        $edate1 = $edate1->as_d8();
        model($c, 'RentalBooking')->create({
            rental_id  => $rental_id,
            date_start => $sdate,
            date_end   => $edate1,
            house_id   => $h_id,
            h_type     => $h_type,
        });
        model($c, 'Config')->search({
            house_id => $h_id,
            the_date => { 'between' => [ $sdate, $edate1 ] },
        })->update({
            sex        => 'R',
            cur        => $max,
            curmax     => $max,
            program_id => 0,
            rental_id  => $rental_id,
        });
    }
    $c->response->redirect($c->uri_for("/rental/view/$rental_id/1"));
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
    $c->response->redirect($c->uri_for("/rental/view/$rental_id/1"));
}

sub contract : Local {
    my ($self, $c, $id) = @_;

    my $rental = model($c, 'Rental')->find($id);
    my $cs = ($rental->contract_signer() || $rental->coordinator());
    #
    # check that the rental is ready for contract generation
    #
    my @mess = ();
    if (! $cs) {
        push @mess, "Contracts need a coordinator or a contract signer.";
    }
    elsif (empty($cs->addr1())) {
        push @mess, $cs->first() . " " . $cs->last()
                    . " does not have an address.";
    }
    my @bookings = $rental->bookings();
    if (! @bookings) {
        push @mess, "There is no assigned meeting place.";
    }
    my $hc_name = $rental->housecost->name();
    if (! $hc_name =~ m{rental}i) {
        push @mess, "The housing cost must have 'Rental' in its name.";
    }
    if ($rental->lunches() =~ m{1} && $hc_name !~ m{lunch}i) {
        push @mess, "Housing Cost must include Lunch";
    }
    if ($rental->lunches() !~ m{1} && $hc_name =~ m{lunch}i) {
        push @mess, "Housing Cost includes Lunch but no lunches provided";
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>", @mess;
        $c->stash->{template} = "rental/error.tt2";
        return;
    }
    #
    # assume the contract is sent the same day it is generated.
    #
    $rental->update({
        contract_sent => today()->as_d8(),
        sent_by       => $c->user->obj->id,
        status        => "sent",
    });
    my $html = "";
    my $tt = Template->new({
        INCLUDE_PATH => 'root/static/templates/letter',
        EVAL_PERL    => 0,
    });
    my %stash = (
        today  => today(),
        signer => $cs,
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
    $c->response->redirect($c->uri_for("/rental/view/$rental_id/1"));
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
    $c->response->redirect($c->uri_for("/rental/view/$rental_id/1"));
}

sub view_summary : Local {
    my ($self, $c, $id) = @_;

    my $rental = model($c, 'Rental')->find($id);
    $c->stash->{rental} = $rental;
    $c->stash->{daily_pic_date} = $rental->sdate();
    $c->stash->{summary} = $rental->summary();
    $c->stash->{template} = "rental/view_summary.tt2";
}

#
# provide a Back button at the bottom but
# exclude it when printing!
#
sub invoice : Local {
    my ($self, $c, $id) = @_;

    Global->init($c);
    my $rental = model($c, 'Rental')->find($id);
    my $ndays = $rental->edate_obj() - $rental->sdate_obj();
    my $hc = $rental->housecost();
    my $max = $rental->max();
    my $html = <<"EOH";
<html>
<head>
</head>
<body>
EOH
    $html .= "<h1>Invoice for "
          .  $rental->name()
          .  "<br>"
          .  $rental->sdate_obj->format("%b %e, %Y")
          .  " to "
          .  $rental->edate_obj->format("%b %e, %Y")
          .  "</h1>\n";
    $html .= <<"EOH";
<h2>Housing Charges</h2>
<ul>
<table cellpadding=8 border=1>
<tr>
<th align=right>Type</th>
<th>Cost<br>Per Night</th>
<th># of<br>People</th>
<th># of<br>Nights</th>
<th>Total</th>
</tr>
EOH
    my $tot_housing_charge = 0;
    my $tot_people = 0;
    H_TYPE:
    for my $type (housing_types(1)) {
        my $meth = "n_$type";
        my $n = $rental->$meth();
        $meth = "att_$type";
        my $att = $rental->$meth();
        next H_TYPE if empty($n) && empty($att);
        $tot_people += $n;
        my @attendance = ();
        if (! empty($att)) {
            my @terms = split m{\s*,\s*}, $att;
            for my $term (@terms) {
                my ($npeople, $ndays) = split m{\s*x\s*}i, $term;
                $npeople =~ s{\s}{};
                my $children = $npeople =~ s{c}{}i;
                push @attendance, [ $npeople, $ndays, $children ];
            }
        }
        my $type_shown = 0;
        my $cost = $hc->$type();
        my $show_cost = $cost;
        my $s = $string{$type};
        if (! @attendance) {
            #
            # No special attendance - so use the '# of people'
            # to determine the costs.  This is hopefully the normal case.
            #
            $html .= Tr(th({ -align => 'right'}, [ $s ]),
                        td({ -align => 'right'},
                           [ $show_cost, $n, $ndays,
                             commify($n * $cost * $ndays)
                           ]
                          )
                       );
            $tot_housing_charge += $n * $cost * $ndays;
            $type_shown = 1;
        }
        if ($type_shown) {
            $s = "";
            $show_cost = "";
        }
        #
        # now for the exceptions
        #
        for my $a (sort {
                       $b->[1] <=> $a->[1]
                   }
                   @attendance
        ) {
            my ($np, $nd, $children) = @$a;
            my $factor = 1;
            if ($children) {
                $np = "$np child";
                $np .= "ren" if $np > 1;
                $factor = .5;
            }
            my $subtot = int($np * $cost * $factor * $nd);
            $html .= Tr(th({ -align => 'right'}, [ $s ]),
                        td({ -align => 'right'},
                           [ $show_cost, $np, $nd, commify($subtot) ]
                          )
                       );
            $tot_housing_charge += $subtot;
            $s = "";
            $show_cost = "";
        }
    }
    $html .= Tr(th({ -align => 'right'}, [ "Total" ]),
                td({ -align => 'right'},
                   [ "", $tot_people, "", '$' . commify($tot_housing_charge)
                   ]
                  )
               );
    $html .= <<"EOH";
</table>
EOH
    my $dorm_rate = $hc->dormitory();
    my $min_lodging = int(0.75
                          * $max
                          * $ndays
                          * $dorm_rate
                         );
    if ($tot_housing_charge < $min_lodging) {
        my $s = commify($min_lodging);
        $html .= <<"EOH";
<div style="width: 500">
<p>
However, the <i>minimum</i> lodging cost was contractually agreed to be
3/4 times the maximum ($max) times $ndays nights at the dormitory rate
of \$$dorm_rate per night which comes to a total of \$$s.
</div>
EOH
        $tot_housing_charge = $min_lodging;
    }
    $html .= "</ul>\n";

    my $extra_hours = 0;
    my $start = $rental->start_hour_obj();
    my $end   = $rental->end_hour_obj();
    my $extime = "";
    my $tr_extra = "";
    my $diff = get_time("1600") - $start;
    if ($diff > 0) {
        $extra_hours += $diff/60;
        $extime .= "started at " . $start->ampm() . " (before 4:00 pm)";
    }
    $diff = $end - get_time("1300");
    if ($diff > 0) {
        $extra_hours += $diff/60;
        $extime .= " and " if $extime;
        $extime .= "ended at " . $end->ampm() . " (after 1:00 pm)";
    }
    my $eh = $extra_hours
             * $tot_people
             * $string{extra_hours_charge}
             ;
    my $extra_hours_charge = sprintf("%d", int($eh));
    my $rounded = "";
    if ($eh != int($eh)) {
        $rounded = " (rounded down)";
    }
    if ($extra_hours) {
        my $pl = ($extra_hours == 1)? "": "s";
        $extra_hours = sprintf("%.2f", $extra_hours);
        my $s = commify($extra_hours_charge);
        $html .= <<"EOH";
<h2>Extra Time Charge</h2>
<div style="width: 500">
<ul>
Since the rental $extime
there is an extra time charge of
$extra_hours hour$pl for $tot_people people
at \$$string{extra_hours_charge}
per hour = \$$s$rounded.
</div>
</ul>
EOH
        $tr_extra = "<tr><th align=right>Extra Time</th><td align=right>$s</td></tr>";
    }

    my @charges = $rental->charges();
    my $tot_other_charges = 0;
    my $tr_other = "";
    if (@charges) {
        $html .= <<"EOH";
<h2>Other Charges</h2>
<ul>
<table cellpadding=8 border=1>
<tr>
<th>Amount</th>
<th align=left>What</th>
</tr>
EOH
        for my $ch (@charges) {
            $tot_other_charges += $ch->amount;
            $html .= "<tr>"
                  .  "<td align=right>" . commify($ch->amount()) . "</td>"
                  .  "<td>" . $ch->what()   . "</td>"
                  .  "</tr>\n"
                  ;
        }
        $html .= "<tr><td align=right>\$"
              .  commify($tot_other_charges)
              .  "</td><td>Total</td></tr>\n";
        $html .= "</table></ul>\n";
        $tr_other = "<tr><th align=right>Other</th><td align=right>"
                  . commify($tot_other_charges)
                  . "</td></tr>";
    }
    my $tot_charges = $tot_housing_charge
                    + $extra_hours_charge
                    + $tot_other_charges
                    ;
    my $st = commify($tot_charges);
    my $sh = commify($tot_housing_charge);
    $html .= <<"EOH";
<h2>Total Charges</h2>
<ul>
<table cellpadding=8 border=1>
<tr><th align=right>Housing</th><td align=right>$sh</td></tr>
$tr_extra
$tr_other
<tr><th align=right>Total</th><td>\$$st</td></tr>
</table>
</ul>
EOH
    my $tot_payments = 0;
    my @payments = $rental->payments();
    if (@payments) {
        $html .= <<"EOH";
<h2>Total Payments</h2>
<ul>
<table cellpadding=8 border=1>
<tr>
<th>Date</th>
<th>Amount</th>
</tr>
EOH
        for my $p (@payments) {
            $html .= "<tr>"
                  .  "<td>" . $p->the_date_obj() . "</td>"
                  .  "<td align=right>" . commify($p->amount()) . "</td>"
                  .  "</tr>\n"
                  ;
            $tot_payments += $p->amount();
        }
        my $s = commify($tot_payments);
        $html .= <<"EOH";
<tr>
<td>Total</td>
<td align=right>\$$s</td>
</tr>
</table>
</ul>
EOH
    }

    my $balance = $tot_charges - $tot_payments;
    my $sb = commify($balance);
    if ($sb == 0) {
        $sb = "Paid in Full";
    }
    else {
        $sb = "\$$sb";
    }
    $html .= <<"EOH";
<h2>Balance</h2>
<ul>
    $sb
</ul>
</body>
</html>
EOH
    #
    # update the balance here this will help determine
    # the status of the rental.  hopefully we don't need
    # to compute the balance elsewhere.  If a new charge
    # is added we'll need to change the balance and the
    # status - but to do that all we need to is ask for
    # invoice.  is this okay?  it is awkward to compute
    # the balance in several places.  make convenience sub???
    #
    # the balance is computed when creating the invoice.
    # the status is set when viewing the rental.
    #
    $rental->update({
        balance => $balance,
    });
    $c->res->output($html);
}

sub link_proposal : Local {
    my ($self, $c, $rental_id, $proposal_id) = @_;
    
    # proposal id in rental
    model($c, 'Rental')->find($rental_id)->update({
        proposal_id => $proposal_id,
    });
    # rental id in proposal
    my $prop = model($c, 'Proposal')->find($proposal_id);
    $prop->update({
        rental_id => $rental_id,
    });
    # ensure that the people on the proposal are transmitted
    # hack it by reaching into Proposal :(!
    # an acceptable exception to our discipline, yes?
    #
    if (! $prop->person_id()) {
        RetreatCenter::Controller::Proposal::_transmit($c, $proposal_id);
    }
    if (! empty($prop->cs_last()) && ! $prop->cs_person_id()) {
        RetreatCenter::Controller::Proposal::_cs_transmit($c, $proposal_id);
    }
    $c->response->redirect($c->uri_for("/rental/view/$rental_id/1"));
}

sub duplicate : Local {
    my ($self, $c, $rental_id) = @_;

    my $orig_r = model($c, 'Rental')->find($rental_id);

    #
    # what should be cleared and entered differently?
    #
    # we will duplicate the summary (in duplicate_do).
    #
    $orig_r->set_columns({
        id      => undef,
        sdate   => "",
        edate   => "",
        glnum   => "", 
        balance => 0,
        status  => "",
        lunches => "",

        tentative  => "yes",
        program_id => 0,
        summary_id => 0,

        contract_sent     => "",
        contract_received => "",
        sent_by           => "",
        received_by       => "",
    });
    for my $ht (housing_types(1)) {
        $orig_r->set_columns({
            "n_$ht"   => "",
            "att_$ht" => "",
        });
    }
    stash($c,
        dup_message => " - <span style='color: red'>Duplication</span>",
            # see comment in Program.pm
        rental => $orig_r,
        section => 1,
        housecost_opts =>
            [ model($c, 'HouseCost')->search(
                undef,
                { order_by => 'name' },
            ) ],
        h_types            => [ housing_types(1) ],
        string             => \%string,
        check_tentative    => "checked",
        check_linked       => ($orig_r->linked())? "checked": "",
        form_action        => "duplicate_do/$rental_id",
        template           => "rental/create_edit.tt2",
        check_mmc_does_reg => ($orig_r->mmc_does_reg())? "checked": "",
    );
}

sub duplicate_do : Local {
    my ($self, $c, $old_id) = @_;

    _get_data($c);
    return if @mess;

    my $section = $P{section};
    delete $P{section};

    $P{lunches} = "";

    $P{glnum} = compute_glnum($c, $P{sdate});

    # get the old rental and the old summary
    # so we can duplicate the summary.  and get the
    # contact person and contract signer ids.
    #
    my ($old_rental)    = model($c, 'Rental')->find($old_id);
    my ($old_summary) = $old_rental->summary();

    my $sum = model($c, 'Summary')->create({
        $old_summary->get_columns(),        # to dup the old ...
        id => undef,                        # with a new id
        date_updated => tt_today($c)->as_d8(),   # and new update status info
        who_updated  => $c->user->obj->id,
        time_updated => get_time()->t24(),
    });


    # now we can create the new dup'ed rental
    # with the coordinator and contract signer ids from the old.
    #
    my $new_r = model($c, 'Rental')->create({
        summary_id => $sum->id,
        %P,
        coordinator_id => $old_rental->coordinator_id(),
        cs_person_id   => $old_rental->cs_person_id(),
    });
    my $id = $new_r->id();

    #
    # we must ensure that we have config records
    # out to the end of this rental + 30 days, say.
    #
    add_config($c, date($P{edate}) + 30);

    if ($P{mmc_does_reg}) {
        # we need to create a parallel program for the dup'ed rental.
        #
        $c->response->redirect($c->uri_for("/program/parallel/$id"));
    }
    else {
        $c->response->redirect($c->uri_for("/rental/view/$id/1"));
    }
}

1;
