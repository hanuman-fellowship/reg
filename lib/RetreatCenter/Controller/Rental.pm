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
    lunch_table
    add_config
    type_max
    max_type
    housing_types
    tt_today
    commify
    stash
    payment_warning
    email_letter
    error
    other_reserved_cids
    reserved_clusters
    palette
    invalid_amount
    clear_lunch
    get_lunch
    get_grid_file
    check_makeup_new
    check_makeup_vacate
    refresh_table
    penny
    ensure_mmyy
    rand6
/;
use Global qw/
    %string
    %houses_in_cluster
    @clusters
    %house_name_of
/;
use HLog;
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
    # ensure the Rental name has mm/yy that matches the start date
    #
    $P{name} = ensure_mmyy($P{name}, date($P{sdate}));

    #
    # if a contract has been sent the rental is no longer tentative, yes?
    #
    if ($P{contract_sent}) {
        $P{tentative} = "";
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
    elsif (! empty($P{expected})) {
        if (! ($P{expected} =~ m{^\d+$})) {
            push @mess, "Invalid expected: $P{expected}.";
        }
    }
    if (! $P{deposit} =~ m{^\d+$}) {
        push @mess, "Invalid deposit.";
    }
    if (exists $P{glnum} && $P{glnum} !~ m{ \A [0-9A-Z]* \z }xms) {
        push @mess, "The GL Number must only contain digits and upper case letters.";
    }
    # checkboxes are not sent at all if not checked
    #
    $P{linked}       = "" unless exists $P{linked};
    $P{tentative}    = "" unless exists $P{tentative};
    $P{mmc_does_reg} = "" unless exists $P{mmc_does_reg};
    #$P{staff_ok}     = "" unless exists $P{staff_ok};
    $P{rental_follows} = "" unless exists $P{rental_follows};

    #
    # quick hack here - fixed cost houses
    #
    $P{fch_encoded} = "";
    LINE:
    for my $l (split /\&/, $P{fixed_cost_houses}) {
        my $cost;
        if ($l =~ s{ \A \s* \$ \s* (\d+) \s* for \s* }{}xms) {
            $cost = $1;
        }
        else {
            push @mess, "Invalid cost for fixed cost house line: $l";
            last LINE;
        }
        my (@house_names) = split /\s*,\s*/, $l;
        my @house_ids;
        for my $hn (@house_names) {
            $hn =~ s{ \A \s* | \s* \z }{}xmsg;      # trim it up to be sure
            my $hn2 = $hn;
            $hn2 =~ s{[*]}{%}xmsg;                  # * => % for wildcard
            my (@houses) = model($c, 'House')->search({
                               name => { -like => $hn2 },
                           });
            if (!@houses) {
                push @mess, "Invalid house '$hn' for fixed cost house line: $l";
                last LINE;
            }
            push @house_ids, map { $_->id } @houses;
        }
        $P{fch_encoded} .= "$cost @house_ids|";
    }
    $P{fch_encoded} =~ s{ \| \z }{}xms;
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "rental/error.tt2";
    }
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
        #check_staff_ok     => '',
        check_rental_follows => '',
    );
}

sub create_do : Local {
    my ($self, $c) = @_;

    _get_data($c);
    return if @mess;

    my $section = $P{section};
    delete $P{section};

    $P{lunches} = "";
    $P{refresh_days} = "";

    $P{glnum} = compute_glnum($c, $P{sdate});

    if ($P{contract_sent}) {
        $P{sent_by} = $c->user->obj->id;
    }
    if ($P{contract_received}) {
        $P{received_by} = $c->user->obj->id;
    }
    # create the summary from the template
    #
    my @prog = model($c, 'Program')->search({
        name => "MMC Template",
    });
    my @dup_summ = ();
    if (@prog) {
        my $template_sum = model($c, 'Summary')->find($prog[0]->summary_id());
        @dup_summ = $template_sum->get_columns(),
    }
    else {
        # could find no template - just make a blank summary
    }
    my $sum = model($c, 'Summary')->create({
        @dup_summ,
        # and then override the following:
        id           => undef,          # new id
        date_updated => tt_today($c)->as_d8(),
        who_updated  => $c->user->obj->id,
        time_updated => get_time()->t24(),
        gate_code => '',
        needs_verification => "yes",
    });

    $P{summary_id} = $sum->id();
    $P{status} = "tentative";
    $P{program_id} = 0;         # so it isn't NULL
    $P{grid_code} = rand6($c);

    my $r = model($c, 'Rental')->create(\%P);
    $r->set_grid_stale();
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
    $P{refresh_days} = "";

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
    if (my $sn = $proposal->special_needs()) {
        $misc =~ s{\s*$}{};      # trim the end
        $misc .= "\n\n$sn";
    }
    my $sum = model($c, 'Summary')->create({
        date_updated   => tt_today($c)->as_d8(),
        who_updated    => $c->user->obj->id,
        time_updated   => get_time()->t24(),

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
    $P{program_id} = 0;                     # so it isn't NULL

    $P{grid_code} = rand6($c);

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
# there are several things to compute for the display.
# update the balance in the record once you're done.
# and possibly reset the status.
#
sub view : Local {
    my ($self, $c, $rental_id, $section) = @_;

    Global->init($c);
    $section ||= 1;
    my $rental = model($c, 'Rental')->find($rental_id);
    if (! $rental) {
        error($c,
            "Rental not found.",
            "gen_error.tt2",
        );
        return;
    }

    my @payments = $rental->payments;
    my $tot_payments = 0;
    for my $p (@payments) {
        $tot_payments += $p->amount;
    }

    my $tot_other_charges = 0;
    my @charges = $rental->charges();
    for my $p (@charges) {
        $tot_other_charges += $p->amount;
    }

    my $ndays = date($rental->edate) - date($rental->sdate);
    my (%bookings, %booking_count);
    for my $b ($rental->rental_bookings()) {
        my $h_name = $b->house->name;
        my $h_type = $b->h_type;
        $bookings{$h_type} .=
            "<a href=/rental/del_booking/$rental_id/"
            .  $b->house_id
         .  qq! onclick="return confirm('Okay to Delete booking of $h_name?');"!
            .  ">"
            .  $h_name
            .  "</a>, "
            ;
        ++$booking_count{$h_type};
    }
    for my $t (keys %bookings) {
        $bookings{$t} =~ s{, $}{};     # final comma
    }

    my $status;
    if ($rental->tentative() || ! $rental->contract_sent()) {
        $status = "tentative";
    }
    elsif (! ($rental->contract_received() && $rental->payments() > 0)) {
        $status = "sent";
    }
    elsif (tt_today($c)->as_d8() > $rental->sdate()) {
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
    my $sdate = $rental->sdate();
    my $nmonths = date($rental->edate())->month()
                - date($sdate)->month()
                + 1;

    my @h_types = housing_types(0);
    my $clusters = join ', ',
                   map {
                       $_->name()
                   }
                   reserved_clusters($c, $rental_id, 'rental')
                   ;

    stash($c,
        ndays          => $ndays,
        rental         => $rental,
        pg_title       => $rental->name(),
        daily_pic_date => "indoors/$sdate",
        cluster_date   => $sdate,
        cal_param      => "$sdate/$nmonths",
        bookings       => \%bookings,
        h_types        => \@h_types,
        string         => \%string,
        charges        => \@charges,
        tot_other_charges => penny($tot_other_charges),
        payments       => \@payments,
        tot_payments   => penny($tot_payments),
        balance        => commify($rental->balance_disp()),
        section        => $section,
        lunch_table    => lunch_table(
                              1,
                              $rental->lunches(),
                              $rental->sdate_obj(),
                              $rental->edate_obj(),
                              $rental->start_hour_obj(),
                          ),
        refresh_table    => ($rental->edate()-$rental->sdate() >= 7)?
                                refresh_table(
                                              1,
                                              $rental->refresh_days(),
                                              $rental->sdate_obj(),
                                              $rental->edate_obj(),
                                ): "",
        clusters       => $clusters,
        template       => "rental/view.tt2",
    );
}

sub clusters : Local {
    my ($self, $c, $rental_id) = @_;

    my $rental = model($c, 'Rental')->find($rental_id);
    my $sdate = $rental->sdate();
    my $nmonths = date($rental->edate())->month()
                - date($sdate)->month()
                + 1;

    # clusters - available and reserved
    my ($avail, $res) = split /XX/, _get_cluster_groups($c, $rental_id);
    stash($c,
        daily_pic_date     => $sdate,
        cal_param          => "$sdate/$nmonths",
        rental             => $rental,
        available_clusters => $avail,
        reserved_clusters  => $res,
        template           => "rental/cluster.tt2",
    );
}

sub list : Local {
    my ($self, $c) = @_;

    Global->init($c);
    my $today = tt_today($c)->as_d8();
    stash($c,
        pg_title => "Rentals",
        rentals  => [
            # past due ones first
            model($c, 'Rental')->search(
                {   
                    edate => { '<', $today },
                    status => 'due',
                },
                { order_by => 'sdate' },
            ),
            model($c, 'Rental')->search(
                { edate => { '>=', $today } },
                { order_by => 'sdate' },
            ),
        ],
        rent_pat => "",
        template => "rental/list.tt2",
    );
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
    stash($c,
        pg_title => "Rentals",
        rentals  => [
            model($c, 'Rental')->search(
                $cond,
                { order_by => 'sdate desc' },
            )
        ],
        rent_pat => $rent_pat,
        template => "rental/list.tt2",
    );
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
        #check_staff_ok => ($r->staff_ok())? "checked": "",
        check_rental_follows => ($r->rental_follows())? "checked": "",
        housecost_opts  =>
            [ model($c, 'HouseCost')->search(
                {
                    -or => [
                        id       => $r->housecost_id,
                        inactive => { '!=' => 'yes' },
                    ],
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
    if ($P{start_hour} >= 1300) {
        # they won't be having lunch on their arrival day
        # since they arrive after lunch ends
        #
        clear_lunch();
        my ($event_start, $lunches) = get_lunch($c, $id, 'Rental');
        if ($lunches && substr($lunches, 0, 1) == 1) {
            error($c,
                  "Cannot have lunch since arrival time is after 1:00 pm!",
                  'gen_error.tt2');
            return;
        }
    }
    if (  $r->sdate ne $P{sdate}
       || $r->edate ne $P{edate}
    ) {
        # we have tried to change the dates of the rental.
        # prohibit this if there are ANY meeting place bookings
        # or rental housing bookings.
        #
        # if there ARE none such clear the lunches.
        #
        my @b = model($c, 'Booking')->search({
                    rental_id => $id,
                });
        if (@b) {
            error($c,
                  "Cannot change rental dates while any meeting places are reserved.",
                  'gen_error.tt2');
            return;
        }
        my @rb = model($c, 'RentalBooking')->search({
                     rental_id => $id,
                 });
        if (@rb) {
            error($c,
                  "Can't change rental dates while any rooms are reserved.",
                  'gen_error.tt2');
            return;
        }
        $P{lunches} = "";
        $P{refresh_days} = "";
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

    if (! $r->grid_code()) {
        # just in case it did not get set properly on creation
        #
        $P{grid_code} = rand6($c);
    }

    $r->update(\%P);
    $r->set_grid_stale();        # relevant things may have changed

    if (! $mmc_does_reg_b4 && $P{mmc_does_reg} && ! $r->program_id()) {
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
#
# prohibit a deletion if there are any existing
# RentalClusters or RentalBookings
#
sub delete : Local {
    my ($self, $c, $rental_id) = @_;

    my @clusters = model($c, 'RentalCluster')->search({
        rental_id => $rental_id,
    });
    my @houses = model($c, 'RentalBooking')->search({
        rental_id => $rental_id,
    });
    my @bookings = model($c, 'Booking')->search({
        rental_id => $rental_id,
    });

    if (@clusters || @houses || @bookings) {
        error($c,
              'You must first remove any assigned clusters,'
                  . ' houses, or meeting places.',
              'gen_error.tt2');
        return;
    }
    my $r = model($c, 'Rental')->find($rental_id);

    # first break any link from the Proposal to this Rental.
    #
    if (my $prop_id = $r->proposal_id()) {
        model($c, 'Proposal')->find($prop_id)->update({
            rental_id => 0,
        });
    }

    # the summary
    $r->summary->delete();

    # and the rental itself
    # does this cascade to rental payments???
    # - yes, because we have a relationship in place.
    # but not RentalClusters so the above ...
    #
    model($c, 'Rental')->search({
        id => $rental_id,
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

    if (tt_today($c)->as_d8() eq $string{last_deposit_date}) {
        error($c,
              'Since a deposit was just done'
                  . ' please make this payment tomorrow instead.',
              'gen_error.tt2');
        return;
    }
    my $r = model($c, 'Rental')->find($id);
    stash($c,
        message  => payment_warning('mmc'),
        amount   => (tt_today($c)->as_d8() >= $r->edate)? $r->balance()
                    :                                     $r->deposit(),
        rental   => $r,
        template => "rental/pay_balance.tt2",
    );
}

sub pay_balance_do : Local {
    my ($self, $c, $id) = @_;

    my $amount = trim($c->request->params->{amount});
    if (invalid_amount($amount)) {
        error($c,
            "Illegal Amount: $amount",
            "rental/error.tt2",
        );
        return;
    }
    my $type = $c->request->params->{type};

    # ??? check amount
    my $today = tt_today($c);
    my $now_date = $today->as_d8();
    if (tt_today($c)->as_d8() eq $string{last_deposit_date}) {
        $now_date = (tt_today($c)+1)->as_d8();
    }
    my $now_time = get_time()->t24();

    model($c, 'RentalPayment')->create({

        rental_id => $id,
        amount    => $amount,
        type      => $type,

        user_id  => $c->user->obj->id,
        the_date => $now_date,
        time     => $now_time,
    });
    $c->response->redirect($c->uri_for("/rental/view/$id/3"));
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
    my @person = model($c, 'Person')->search({
                       first => $first,
                       last  => $last,
                 });
    if (@person) {
        if (@person > 1) {
            stash($c,
                mess     => "More than one person named <a href='/person/search_do?pattern=$last+$first&field=last'>$first $last</a>!",
                template => "rental/error.tt2",
            );
            return;
        }
        $r->update({
            coordinator_id => $person[0]->id,
        });
        $r->set_grid_stale();
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
    my @person = model($c, 'Person')->search({
                       first => $first,
                       last  => $last,
                 });
    if (@person) {
        if (@person > 1) {
            stash($c,
                mess     => "More than one person named <a href='/person/search_do?pattern=$last+$first&field=last'>$first $last</a>!",
                template => "rental/error.tt2",
            );
            return;
        }
        $r->update({
            cs_person_id => $person[0]->id,
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
    if (invalid_amount($amount)) {
        push @mess, "Illegal Amount: $amount";
    }
    if (empty($what)) {
        push @mess, "Missing What";
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>", @mess;
        $c->stash->{template} = "rental/error.tt2";
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
                      $r->lunches(),
                      $r->sdate_obj(),
                      $r->edate_obj(),
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
    if (my $p_id = $r->program_id()) {
        my $p = model($c, 'Program')->find($p_id);
        if ($p) {
            $p->update({
                lunches => $l,
            });
        }
    }
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
    my $low_max =  $max ==  7? 4
                  :$max == 20? 8
                  :            $max;

    my %or_cids = other_reserved_cids($c, $r);
    my @or_cids = keys %or_cids;
    my @opt = ();
    if (@or_cids) {
        push @opt, cluster_id => { -not_in => \@or_cids };
    }

    #
    # look at a list of _possible_ houses for h_type.
    # ??? what order to present them in?  priority/resized?
    # no.   simple alphabetic sort.
    # consider cluster???  other bookings for this rental???
    #
    my $checks = "";
    my $Rchecks = "";
    my $nrooms = 0;
    HOUSE:
    for my $h (model($c, 'House')->search({
                   inactive => '',
                   bath     => $bath,
                   tent     => $tent,
                   center   => $center,
                   max      => { '>=', $low_max },
                   @opt,
               },
               { order_by => 'name' }
              ) 
    ) {
        my $h_id = $h->id;
        #
        # is this house _completely_ available from sdate to edate1?
        # needs a thorough testing!
        #
        my @cf = model($c, 'Config')->search({
            house_id => $h_id,
            the_date => { between => [ $sdate, $edate1 ] },
            cur      => { '>', 0 },
        });
        next HOUSE if @cf;        # nope

        my $s = "<input type=checkbox name=h$h_id value=$h_id> "
              . $h->name()
              ;
        if ($low_max <= $h->max() && $h->max() <= $max) {
            $checks .= "$s<br>";
        }
        else {
            $Rchecks .= "$s<br>";
        }
        ++$nrooms;
    }
    stash($c,
        nrooms      => $nrooms,
        checks      => $checks,
        Rchecks     => $Rchecks,
        disp_h_type => (($h_type =~ m{^[aeiou]})? "an": "a")
                                . " '$string{$h_type}'",
        template    => "rental/booking.tt2",
    );
}

#
# actually make the booking
# add a RentalBooking record
# and update the sequence of Config records.
# also check the makeup list.
#
sub booking_do : Local {
    my ($self, $c, $rental_id, $h_type) = @_;

    my $r = model($c, 'Rental')->find($rental_id);
    my $rname = $r->name();

    my $sdate = $r->sdate();
    my $edate1 = date($r->edate()) - 1;
    $edate1 = $edate1->as_d8();

    my @dates = ();
    if ($string{housing_log}) {
        my $sd = date($sdate);
        my $ed = date($edate1);
        for (my $d = $sd; $d <= $ed; ++$d) {
            push @dates, $d->as_d8();
        }
    }

    my @chosen_house_ids = sort { $a <=> $b } values %{$c->request->params()};
    if (! @chosen_house_ids) {
        $c->response->redirect($c->uri_for("/rental/view/$rental_id/1"));
        return;
    }
    for my $h_id (@chosen_house_ids) {
        my $h = model($c, 'House')->find($h_id);
        model($c, 'RentalBooking')->create({
            rental_id  => $rental_id,
            date_start => $sdate,
            date_end   => $edate1,
            house_id   => $h_id,
            h_type     => $h_type,
        });
        my $max = type_max($h_type);
        if ($max > $h->max()) {
            $max = $h->max();
            # can't have more beds than there are beds, right?
        }
        model($c, 'Config')->search({
            house_id => $h_id,
            the_date => { 'between' => [ $sdate, $edate1 ] },
        })->update({
            sex        => 'R',
            curmax     => $max,
            cur        => $max,
            program_id => 0,
            rental_id  => $rental_id,
        });
        # in the above we set cur and curmax to the
        # max of the type - so it looks like a resized room
        # occupied by the rental.  no space for anyone else.

        if ($string{housing_log}) {
            my $hname = $house_name_of{$h_id};
            for my $d (@dates) {
                hlog($c,
                     $hname, $d,
                     "book",
                     $h_id, $max, $max, 'R',
                     0, $rental_id,
                     $rname,
                );
            }
        }
        check_makeup_new($c, $h_id, $sdate);
    }
    $r->set_grid_stale();

    $c->response->redirect($c->uri_for("/rental/view/$rental_id/1"));
}

sub del_booking : Local {
    my ($self, $c, $rental_id, $house_id) = @_;

    my $r = model($c, 'Rental')->find($rental_id);
    my $h = model($c, 'House')->find($house_id);

    # is there someone in the room?
    # if so, you can't delete it!  they have to remove
    # that person first.
    #
    system("grab wait");        # make sure the local grids are current

    my $fgrid = get_grid_file($r->grid_code());
    my $error = "";
    if (open my $in, "<", $fgrid) {
        LINE:
        while (my $line = <$in>) {
            my ($h_id, $ignore, $person) = split /\|/, $line;
            if ($h_id == $house_id && $person) {
                $error = "Because the rental coordinator has assigned"
                       . " $person to "
                       . $h->name
                       . " it cannot be removed."
                       ;
                last LINE;
            }
        }
    }
    else {
        # the rental grid has never been saved on the web.
        # we can safely assume that no one is in this space.
    }
    if ($error) {
        error($c,
            $error,
            'rental/error.tt2',
        );
        return;
    }
    my $rname = $r->name();

    my $sdate = $r->sdate();
    my $edate1 = date($r->edate()) - 1;
    $edate1 = $edate1->as_d8();

    my @dates = ();
    if ($string{housing_log}) {
        my $sd = date($sdate);
        my $ed = date($edate1);
        for (my $d = $sd; $d <= $ed; ++$d) {
            push @dates, $d->as_d8();
        }
    }

    model($c, 'RentalBooking')->search({
        rental_id => $rental_id,
        house_id  => $house_id,
    })->delete();

    my $max = $h->max;
    model($c, 'Config')->search({
        house_id => $house_id,
        the_date => { 'between' => [ $sdate, $edate1 ] },
    })->update({
        sex        => 'U',
        curmax     => $max,
        cur        => 0,
        program_id => 0,
        rental_id  => 0,
    });

    if ($string{housing_log}) {
        my $hname = $house_name_of{$house_id};
        for my $d (@dates) {
            hlog($c,
                 $hname, $d,
                 "book_del",
                 $house_id, $max, 0, 'U',
                 0, 0,
                 $rname,
            );
        }
    }

    $r->set_grid_stale();

    check_makeup_vacate($c, $house_id, $sdate);

    $c->response->redirect($c->uri_for("/rental/view/$rental_id/1"));
}

# different stash than sub contract???
#
sub email_contract : Local {
    my ($self, $c, $rental_id) = @_;

    my $rental = model($c, 'Rental')->find($rental_id);
    if (! _contract_ready($c, $rental)) {
        return;
    }
    stash($c,
        rental   => $rental,
        template => "rental/email_contract.tt2",
    );
}

sub _contract_ready {
    my ($c, $rental) = @_;

    my $cs_id = ($rental->cs_person_id() || $rental->coordinator_id());
    my $cs = undef;
    if ($cs_id) {
        $cs = model($c, 'Person')->find($cs_id);
    }
    #
    # check that the rental is ready for contract generation
    #
    my @mess = ();
    if (! $cs) {
        push @mess, "Contracts need a coordinator or a contract signer.";
    }
    elsif (empty($cs->addr1())) {
        push @mess, $cs->name()
                    . " does not have an address.";
    }
    my @bookings = $rental->bookings();
    if (! @bookings) {
        push @mess, "There is no assigned meeting place.";
    }
    my $hc_name = $rental->housecost->name();
    if ($hc_name !~ m{rental}i) {
        push @mess, "The housing cost must have 'Rental' in its name.";
    }
    if ($rental->lunches() =~ m{1} && $hc_name !~ m{lunch}i) {
        push @mess, "The housing cost must have 'Lunch' in its name.";
    }
    if ($rental->lunches() !~ m{1} && $hc_name =~ m{lunch}i) {
        push @mess, "Housing Cost includes Lunch but no lunches provided.";
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>", @mess;
        $c->stash->{template} = "rental/error.tt2";
        return 0;
    }
    return 1;
}

sub contract : Local {
    my ($self, $c, $id, $email) = @_;

    my $rental = model($c, 'Rental')->find($id);
    if (! _contract_ready($c, $rental)) {
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
        INTERPOLATE  => 1,
        INCLUDE_PATH => 'root/static/templates/letter',
        EVAL_PERL    => 0,
    });
    my $ndays  = date($rental->edate()) - date($rental->sdate());
    my $agreed = $rental->max()
                 * $ndays
                 * $rental->housecost->dormitory()
                 ;
    my $min_due = int(.75* $agreed);
    my %stash = (
        today   => today(),
        email   => $email,
        signer  => ($rental->cs_person_id()? $rental->contract_signer()
                   :                        $rental->coordinator()),
        rental  => $rental,
        ndays   => $ndays,
        agreed  => commify($agreed),
        min_due => commify($min_due),
        deposit => commify($rental->deposit()),
        rental_lunch_cost => $string{rental_lunch_cost},
    );
    $tt->process(
        "rental_contract.tt2",# template
        \%stash,          # variables
        \$html,           # output
    ) or die "error in processing template: "
             . $tt->error();
    if ($email) {
        my @to = ();
        my @cc = ();
        my $em;
        if ($em = $c->request->params->{coord_email}) {
            push @to, $em;
        }
        if ($em = $c->request->params->{cs_email}) {
            push @to, $em;
        }
        if ($c->request->params->{cc}) {
            @cc = split m{[\s,]+}, $c->request->params->{cc};
        }
        # check @to, empty @cc?
        email_letter($c,
            from    => "$string{from_title} <$string{from}>",
            to      => \@to,
            cc      => \@cc,
            subject => "MMC Rental Contract with " . $rental->name(),
            html    => $html,
        );
        $c->response->redirect($c->uri_for("/rental/view/$id/1"));
    }
    else {
        $c->res->output($html);
    }
}

#
# reserve all houses in a cluster.
# this actually changes the config records
# for each house in the cluster.
#
# then refresh the view
#
sub reserve_cluster : Local {
    my ($self, $c, $rental_id, $cluster_id) = @_;

    my $rental = model($c, 'Rental')->find($rental_id);
    my $rname = $rental->name();

    my $sdate = $rental->sdate();
    my $edate1 = (date($rental->edate()) - 1)->as_d8();
                                    # they don't stay the last day!
    my @dates = ();
    if ($string{housing_log}) {
        my $sd = date($sdate);
        my $ed = date($edate1);
        for (my $d = $sd; $d <= $ed; ++$d) {
            push @dates, $d->as_d8();
        }
    }

    model($c, 'RentalCluster')->create({
        rental_id  => $rental_id,
        cluster_id => $cluster_id,
    });
    for my $h (@{$houses_in_cluster{$cluster_id}}) {
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
            curmax     => $h_max,
            cur        => $h_max,
            program_id => 0,
            rental_id  => $rental_id,
        });
        if ($string{housing_log}) {
            my $hname = $house_name_of{$h_id};
            for my $d (@dates) {
                hlog($c,
                     $hname, $d,
                     "clust",
                     $h_id, $h_max, $h_max, 'R',
                     0, $rental_id,
                     $rname,
                );
            }
        }
    }
    $rental->set_grid_stale();
    $c->response->redirect($c->uri_for("/rental/clusters/$rental_id"));
}

#
# 1 - remove the indicated RentalClust record
# 2 - for each house in the cluster
#         remove the RentalBooking record
#         adjust the config records for that house as well.
# NO NO - don't remove the rentalbooking records for each house
#         those houses may have already been reserved.
# then refresh the view.
#
sub cancel_cluster : Local {
    my ($self, $c, $rental_id, $cluster_id) = @_;

    my $rental = model($c, 'Rental')->find($rental_id);
    my $rname = $rental->name();

    my $sdate = $rental->sdate();
    my $edate1 = (date($rental->edate()) - 1)->as_d8();
                                    # they don't stay the last day!
    my @dates = ();
    if ($string{housing_log}) {
        my $sd = date($sdate);
        my $ed = date($edate1);
        for (my $d = $sd; $d <= $ed; ++$d) {
            push @dates, $d->as_d8();
        }
    }

    model($c, 'RentalCluster')->search({
        rental_id  => $rental_id,
        cluster_id => $cluster_id,
    })->delete();
    $c->response->redirect($c->uri_for("/rental/clusters/$rental_id"));
    return;
    # NO NO don't do the below
    HOUSE:
    for my $h (@{$houses_in_cluster{$cluster_id}}) {
        my $h_id = $h->id();
        my $h_max = $h->max();
        my ($rb) = model($c, 'RentalBooking')->search({
            rental_id => $rental_id,
            house_id  => $h_id,
        });
        next HOUSE if ! $rb;        # it was already cancelled individually

        $rb->delete();

        model($c, 'Config')->search({
            house_id => $h_id,
            the_date => { between => [ $sdate, $edate1 ] },
        })->update({
            sex    => 'U',
            curmax => $h_max,
            cur    => 0,
            rental_id  => 0,
            program_id => 0,
        });
        if ($string{housing_log}) {
            my $hname = $house_name_of{$h_id};
            for my $d (@dates) {
                hlog($c,
                     $hname, $d,
                     "clust_del",
                     $h_id, $h_max, 0, 'U',
                     0, 0,
                     $rname,
                );
            }
        }
    }
    $rental->set_grid_stale();
    $c->response->redirect($c->uri_for("/rental/clusters/$rental_id"));
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
# ???provide a Back button at the bottom but
# exclude it when printing!
#
sub invoice : Local {
    my ($self, $c, $id) = @_;

    Global->init($c);
    system("grab wait");        # make sure the local grid is current
    my $rental = model($c, 'Rental')->find($id);
    my $ndays = $rental->edate_obj() - $rental->sdate_obj();
    my $hc = $rental->housecost();
    my $max = $rental->max();

    my $html = <<"EOH";
<html>
<head>
<style type="text/css">
body {
    margin-top: 1.5in;
    margin-left: .5in;
}
h1 {
    font-size: 18pt;
}
h2 {
    font-size: 14pt;
}
</style>
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
<div style="margin-left: .3in">
EOH

    my $tot_housing_charge = 0;
    my $fgrid = get_grid_file($rental->grid_code());
    if (open my $in, "<", $fgrid) {
        # parse the file and extract total cost
        #
        while (my $line = <$in>) {
            chomp $line;
            my ($cost) = $line =~ m{(\d+)$};
            $tot_housing_charge += $cost;
        }
        close $in;
        my $ctot = commify($tot_housing_charge);
        $html .= <<"EOH";
From web housing grid: \$$ctot
EOH
    }
   
    # how does the total cost compare to the minimum?
    #
    my $dorm_rate = $hc->dormitory();
    my $min_lodging = int(0.75
                          * $max
                          * $ndays
                          * $dorm_rate
                         );
    if ($hc->type() ne 'Total' && $tot_housing_charge < $min_lodging) {
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
    $html .= "</div>\n";

    # get attendance for the first, last days
    my @counts = $rental->daily_counts();

    my $ex_time = "";
    my $extra_hours_charge = 0;
    my $tr_extra = "";

    #
    # repetitious.
    # I can't bother to generalize the two cases at this time.
    #
    my $start = $rental->start_hour_obj();
    my $diff = get_time("1600") - $start;
    if ($diff > 0) {
        my $extra_hours = $diff/60;
        my $np = $rental->expected() || $counts[0];       # first day count
        my $ec = $extra_hours
                 * $np
                 * $string{extra_hours_charge}
                 ;
        my $rounded = "";
        if ($ec != int($ec)) {
            $rounded = " (rounded down)";
        }
        $ec = int($ec);
        my $s = commify($ec);
        $extra_hours_charge += $ec;

        my $pl = ($extra_hours == 1)? "": "s";
        $extra_hours = sprintf("%.2f", $extra_hours);
        $tr_extra = "<tr><th align=right>Extra Time</th><td align=right>$s</td></tr>";
        $ex_time .= "The rental started at "
                 .  $start->ampm()
                 .  " (before 4:00 pm)"
                 .  " so there is an extra time charge of "
                 .  " $extra_hours hour$pl for $np people"
                 .  " at \$$string{extra_hours_charge} per hour"
                 .  " = \$$s$rounded."
                 ;
    }
    my $end = $rental->end_hour_obj();
    $diff = $end - get_time("1300");
    if ($diff > 0) {
        my $extra_hours = $diff/60;
        my $np = $rental->expected()|| $counts[-1];       # last day count
        my $ec = $extra_hours
                 * $np
                 * $string{extra_hours_charge}
                 ;
        my $rounded = "";
        if ($ec != int($ec)) {
            $rounded = " (rounded down)";
        }
        $ec = int($ec);
        my $s = commify($ec);
        $extra_hours_charge += $ec;

        my $pl = ($extra_hours == 1)? "": "s";
        $extra_hours = sprintf("%.2f", $extra_hours);
        $tr_extra .= "<tr><th align=right>Extra Time</th><td align=right>$s</td></tr>";
        $ex_time .= "<p>\n" if $ex_time;
        $ex_time .= "The rental ended at "
                 .  $end->ampm()
                 .  " (after 1:00 pm)"
                 .  " so there is an extra time charge of "
                 .  " $extra_hours hour$pl for $np people"
                 .  " at \$$string{extra_hours_charge} per hour"
                 .  " = \$$s$rounded."
                 ;
    }
    if ($extra_hours_charge) {
        $html .= <<"EOH";
<h2>Extra Time Charge</h2>
<div style="width: 500; margin-left: .3in;">
$ex_time
</div>
EOH
    }

    my @charges = $rental->charges();
    my $tot_other_charges = 0;
    my $tr_other = "";
    if (@charges) {
        $html .= <<"EOH";
<h2>Other Charges</h2>
<div style="margin-left: .3in">
<table cellpadding=3 border=1>
<tr>
<th>Amount</th>
<th align=left>What</th>
</tr>
EOH
        for my $ch (@charges) {
            $tot_other_charges += $ch->amount;
            $html .= "<tr>"
                  .  "<td align=right>" . commify($ch->amount_disp()) . "</td>"
                  .  "<td>" . $ch->what()   . "</td>"
                  .  "</tr>\n"
                  ;
        }
        $html .= "<tr><td align=right>\$"
              .  commify(penny($tot_other_charges))
              .  "</td><td>Total</td></tr>\n";
        $html .= "</table></ul>\n";
        $tr_other = "<tr><th align=right>Other</th><td align=right>"
                  . commify(penny($tot_other_charges))
                  . "</td></tr>";
    }
    my $tot_charges = $tot_housing_charge
                    + $extra_hours_charge
                    + $tot_other_charges
                    ;
    my $st = commify(penny($tot_charges));
    my $sh = commify(penny($tot_housing_charge));
    $html .= <<"EOH";
</table>
</div>
<h2>Total Charges</h2>
<div style="margin-left: .3in">
<table cellpadding=3 border=1>
<tr><th align=right>Housing</th><td align=right>$sh</td></tr>
$tr_extra
$tr_other
<tr><th align=right>Total</th><td>\$$st</td></tr>
</table>
</div>
EOH
    my $tot_payments = 0;
    my @payments = $rental->payments();
    if (@payments) {
        $html .= <<"EOH";
<h2>Total Payments</h2>
<div style="margin-left: .3in">
<table cellpadding=3 border=1>
<tr>
<th>Date</th>
<th>Amount</th>
</tr>
EOH
        for my $p (@payments) {
            $html .= "<tr>"
                  .  "<td>" . $p->the_date_obj() . "</td>"
                  .  "<td align=right>" . commify($p->amount_disp()) . "</td>"
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
</div>
EOH
    }

    my $balance = $tot_charges - $tot_payments;
    my $sb = commify(penny($balance));
    if ($balance == 0) {
        $sb = "Paid in Full";
    }
    else {
        $sb = "\$$sb";
    }
    $html .= <<"EOH";
<h2>Balance</h2>
<div style="margin-left: .3in">
    $sb
</div>
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
        refresh_days => "",

        tentative  => "yes",
        program_id => 0,
        summary_id => 0,

        contract_sent     => "",
        contract_received => "",
        sent_by           => "",
        received_by       => "",
        grid_code         => "",
    });
    stash($c,
        dup_message => " - <span style='color: red'>Duplication</span>",
            # see comment in Program.pm
        rental => $orig_r,
        section => 1,
        housecost_opts =>
            [ model($c, 'HouseCost')->search(
                {
                    id       => $orig_r->housecost_id,
                    inactive => { '!=' => 'yes' },
                },
                { order_by => 'name' },
            ) ],
        h_types            => [ housing_types(1) ],
        string             => \%string,
        check_tentative    => "checked",
        check_linked       => ($orig_r->linked())? "checked": "",
        form_action        => "duplicate_do/$rental_id",
        template           => "rental/create_edit.tt2",
        check_mmc_does_reg => ($orig_r->mmc_does_reg())? "checked": "",
        #check_staff_ok     => ($orig_r->staff_ok())? "checked": "",
        rental_follows     => ($orig_r->rental_follows())? "checked": "",
    );
}

sub duplicate_do : Local {
    my ($self, $c, $old_id) = @_;

    _get_data($c);
    return if @mess;

    my $section = $P{section};
    delete $P{section};

    $P{lunches} = "";
    $P{refresh_days} = "";

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
        gate_code => '',
        needs_verification => "yes",
    });
    my @tprog = model($c, 'Program')->search({
        name => "MMC Template",
    });
    if (@tprog) {
        my $template_sum = model($c, 'Summary')->find($tprog[0]->summary_id());
        $sum->update({
            check_list => $template_sum->check_list(),
        });
    }

    $P{program_id} = 0;     # if a parallel rental is created
                            # this will be overwritten

    # now we can create the new dup'ed rental
    # with the coordinator and contract signer ids from the old.
    #
    my $new_r = model($c, 'Rental')->create({
        %P,         # this comes first so summary_id can override
        summary_id => $sum->id,
        coordinator_id => $old_rental->coordinator_id(),
        cs_person_id   => $old_rental->cs_person_id(),
        grid_code      => rand6($c),
    });
    $new_r->set_grid_stale();
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

sub _house_opts {
    my ($c, $rental_id, $cur_hid) = @_;

    $cur_hid ||= 0;
    my $house_opts = "";
    # ??? should be able to put this in DB/Rental.pm
    # and call $r->rental_bookings
    for my $b (model($c, 'RentalBooking')->search(
                   {
                       rental_id => $rental_id,
                   },
                   {
                       join     => [qw/ house / ],
                       prefetch => [qw/ house / ],
                       order_by => [qw/ house.name /],
                   }
              )
    ) {
        my $h = $b->house();
        my $hid = $h->id();
        $house_opts .= "<option value=$hid"
                    .  ($hid == $cur_hid? " selected": "")
                    .  ">"
                    .  $h->name()
                    .  "\n"
                    ;
    }
    $house_opts .= "<option value=1000"
                .  ($cur_hid == 1000? " selected": "")
                .  ">Own Van\n";
    $house_opts .= "<option value=2000"
                .  ($cur_hid == 2000? " selected": "")
                .  ">Commuting\n";
    return $house_opts;
}

sub del_charge : Local {
    my ($self, $c, $charge_id) = @_;

    my $charge = model($c, 'RentalCharge')->find($charge_id);
    my $rental_id = $charge->rental_id();
    $charge->delete();
    $c->response->redirect($c->uri_for("/rental/view/$rental_id/3"));
}

sub del_payment : Local {
    my ($self, $c, $payment_id) = @_;

    my $payment = model($c, 'RentalPayment')->find($payment_id);
    my $rental_id = $payment->rental_id();
    $payment->delete();
    $c->response->redirect($c->uri_for("/rental/view/$rental_id/3"));
}

sub update_charge : Local {
    my ($self, $c, $charge_id) = @_;

    my $charge = model($c, 'RentalCharge')->find($charge_id);
    stash($c,
        charge => $charge,
        template => 'rental/update_charge.tt2',
    );
}

sub update_charge_do : Local {
    my ($self, $c, $charge_id) = @_;

    my $charge = model($c, 'RentalCharge')->find($charge_id);
    my $rental_id = $charge->rental_id();

    my @mess = ();
    my $amount = trim($c->request->params->{amount});
    my $what   = trim($c->request->params->{what});
    if (empty($amount)) {
        push @mess, "Missing Amount";
    }
    if (invalid_amount($amount)) {
        push @mess, "Illegal Amount: $amount";
    }
    if (empty($what)) {
        push @mess, "Missing What";
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>", @mess;
        $c->stash->{template} = "rental/error.tt2";
        return;
    }
    $charge->update({
        amount => $amount,
        what   => $what,
    });
    $c->response->redirect($c->uri_for("/rental/view/$rental_id/3"));
}

sub update_payment : Local {
    my ($self, $c, $payment_id) = @_;

    my $payment = model($c, 'RentalPayment')->find($payment_id);
    my $type_opts = "";
    for my $t (qw/ D C S O /) {
        $type_opts .= "<option value=$t"
                   .  (($payment->type() eq $t)? " selected": "")
                   .  ">"
                   .  $string{"payment_$t"}
                   .  "\n";
                   ;
    }
    stash($c,
        payment => $payment,
        type_opts => $type_opts,
        template => 'rental/update_payment.tt2',
    );
}

sub update_payment_do : Local {
    my ($self, $c, $payment_id) = @_;

    my $payment = model($c, 'RentalPayment')->find($payment_id);
    my $rental_id = $payment->rental_id();

    my $the_date = trim($c->request->params->{the_date});
    my $dt = date($the_date);
    if (!$dt) {
        error($c,
            "Illegal Date: $the_date",
            "rental/error.tt2",
        );
        return;
    }
    my $amount = trim($c->request->params->{amount});
    if (invalid_amount($amount)) {
        error($c,
            "Illegal Amount: $amount",
            "rental/error.tt2",
        );
        return;
    }
    my $type = $c->request->params->{type};
    $payment->update({
        the_date  => $dt->as_d8(),
        amount    => $amount,
        type      => $type,
    });
    # ??? does not update the time.  okay?
    $c->response->redirect($c->uri_for("/rental/view/$rental_id/3"));
}

#
# sort of wasteful to do this for each rental view...
# put all this looking in a separate cluster assignment dialog?
# yes.  did that.
#
sub _get_cluster_groups {
    my ($c, $rental_id) = @_;

    my @reserved = 
        model($c, 'RentalCluster')->search(
        { rental_id => $rental_id },
        {
            order_by => 'cluster.name',
            join     => 'cluster',
            prefetch => 'cluster',
        },
    );
    my %my_reserved_ids = map { $_->cluster_id() => 1 } @reserved; # easy lookup
    my $reserved = "<tr><th align=left>Reserved</th></tr>\n";
    for my $rc (@reserved) {
        my $cid = $rc->cluster_id();
        $reserved .=
           "<tr><td>"
           . "<a href='/rental/cancel_cluster/$rental_id/$cid'>"
           . $rc->cluster->name()
           . "</a>"
           . "</td></tr>\n"
           ;
    }

    my $available = "<tr><th align=left>Available</th></tr>\n";
    #
    # find ids of overlapping programs AND rentals
    #
    my $rental = model($c, 'Rental')->find($rental_id);
    my $sdate = $rental->sdate();
    my $edate = $rental->edate();
    my $edate1 = (date($edate) - 1)->as_d8();

    my @ol_prog_ids =
        map {
            $_->id()
        }
        model($c, 'Program')->search({
            level => { -not_in => [qw/ D C M /], },
            name  => { -not_like => '%personal%retreat%' },
            sdate => { '<' => $edate },       # and it overlaps
            edate => { '>' => $sdate },       # with this rental
        });
    my @ol_rent_ids =
        map {
            $_->id()
        }
        model($c, 'Rental')->search({
            id    => { '!=' => $rental_id },  # not this rental
            sdate => { '<' => $edate },       # and it overlaps
            edate => { '>' => $sdate },       # with this rental
        });
    #
    # what distinct cluster ids are already taken by
    # these overlapping programs or rentals?
    #
    my %cids;
    # better way to do this???
    if (@ol_prog_ids) {
        for my $pc (model($c, 'ProgramCluster')->search({
                        program_id => { -in => \@ol_prog_ids },
                    })
        ) {
            $cids{$pc->cluster_id()} = 1;
        }
    }
    if (@ol_rent_ids) {
        for my $rc (model($c, 'RentalCluster')->search({
                        rental_id  => { -in => \@ol_rent_ids },
                    })
        ) {
            $cids{$rc->cluster_id()} = 1;
        }
    }
    #
    # and all this leaves what clusters as available?
    #
    CLUSTER:
    for my $cl (@clusters) {
        my $cid = $cl->id();
        next CLUSTER if exists $my_reserved_ids{$cid} || exists $cids{$cid};
        #
        # furthermore, are ALL houses in this cluster truely free?
        #
        for my $h (@{$houses_in_cluster{$cid}}) {
            my @cf = model($c, 'Config')->search({
                         house_id => $h->id,
                         the_date => { 'between', => [ $sdate, $edate1 ] },
                         cur      => { '!=' => 0 },
                     });
            next CLUSTER if @cf;
        }
        $available
            .= "<tr><td>"
            .  "<a href='/rental/reserve_cluster/$rental_id/$cid'>"
            .  $cl->name()
            .  "</a>"
            .  "</td></tr>\n"
            ;
    }
    return "<table>\n$available</table>XX<table>\n$reserved</table>";
}

sub grid : Local {
    my ($self, $c, $rental_id) = @_;

    my $rental = model($c, 'Rental')->find($rental_id);
    my $days = "";
    my $d = $rental->sdate_obj();
    my $ed = $rental->edate_obj() - 1;
    while ($d <= $ed) {
        $days .= "<th align=center width=20>"
              .  $d->format("%s")
              .  "</th>"
              ;
        ++$d;
    }
    # prepare the class hash for fixed cost houses
    # so they can be rendered in green.
    my %class;
    for my $line (split /\|/, $rental->fch_encoded) {
        my @h_ids = split ' ', $line;
        shift @h_ids;     # cost
        for my $h_id (@h_ids) {
            $class{$h_id} = 'fixed';
        }
    }

    # get the most recent edit from the global web
    #
    my $fgrid = get_grid_file($rental->grid_code());

    my %data = ();
    my $total = 0;
    my %max;
    if (open my $in, "<", $fgrid) {
        LINE:
        while (my $line = <$in>) {
            chomp $line;
            my ($id, $bed, $name, @nights) = split m{\|}, $line;
            if ($id >= 1000) {
                $max{$id} = $bed;
            }
            my $cost = pop @nights;
            $data{"p$id\_$bed"} = $name;
            $data{"cl$id\_$bed"}
                = ($name =~ m{\&|\band\b}
                   || $name =~ m{\bchild\b}
                   || $name =~ m{-\s*[12347]\s*$})? "class=special"
                  :                                 ""
                  ;
            for my $n (1 .. @nights) {
                $data{"n$id\_$bed\_$n"} = $nights[$n-1];
            }
            $data{"c$id\_$bed"} = $cost || "";
            $total += $cost || 0;
        }
        close $in;
    }
    my $coord = $rental->coordinator();
    my $coord_name = "";
    if ($coord) {
        $coord_name = $coord->name();
    }
    else {
        $coord_name = "";
    }
    stash($c,
        class    => \%class,
        days     => $days,
        rental   => $rental,
        nnights  => ($rental->edate_obj() - $rental->sdate_obj()),
        data     => \%data,
        max      => \%max,      # for own van, commuting
        coord_name => $coord_name,
        total    => commify($total),
        template => 'rental/grid.tt2',
    );
}

sub color : Local {
    my ($self, $c, $rental_id) = @_;
    my $rental = model($c, 'Rental')->find($rental_id);
    my ($r, $g, $b) = $rental->color() =~ m{\d+}g;
    $r ||= 127;
    $g ||= 127;
    $b ||= 127;
    stash($c,
        Type     => 'Rental',
        type     => 'rental',
        id       => $rental_id,
        name     => $rental->name(),
        red      => $r,
        green    => $g,
        blue     => $b,
        color    => "$r, $g, $b",
        palette  => palette(),
        template => 'color.tt2',
    );
}

sub color_do : Local {
    my ($self, $c, $rental_id) = @_;
    my $rental = model($c, 'Rental')->find($rental_id);
    $rental->update({
        color => $c->request->params->{color},
    });
    $c->response->redirect($c->uri_for("/rental/view/$rental_id/2"));
}

sub update_refresh : Local {
    my ($self, $c, $id) = @_;

    my $r = model($c, 'Rental')->find($id);
    $c->stash->{rental} = $r;
    $c->stash->{refresh_table}
        = refresh_table(0,
              $r->refresh_days(),
              $r->sdate_obj,
              $r->edate_obj,
          );
    $c->stash->{template} = "rental/update_refresh.tt2";
}

sub update_refresh_do : Local {
    my ($self, $c, $id) = @_;

    %P = %{ $c->request->params() };
    my $r = model($c, 'Rental')->find($id);
    my $ndays = $r->edate_obj - $r->sdate_obj;
    my $l = "";
    for my $n (0 .. $ndays) {
        $l .= (exists $P{"d$n"})? "1": "0";
    }
    $r->update({
        refresh_days => $l,
    });
    if (my $p_id = $r->program_id()) {
        my $p = model($c, 'Program')->find($p_id);
        if ($p) {
            $p->update({
                refresh_days => $l,
            });
        }
    }
    $c->response->redirect($c->uri_for("/rental/view/$id/1"));
}

sub cancel : Local {
    my ($self, $c, $id) = @_;

    my $r = model($c, 'Rental')->find($id);
    if ($r->cancelled) {
        $r->update({
            cancelled => '',
        });
    }
    else {
        if (my @bookings = $r->bookings) {
            error($c,
                "Cannot cancel a rental with meeting place bookings.",
                "gen_error.tt2",
            );
            return;
        }
        if (my @rental_bookings = $r->rental_bookings) {
            error($c,
                "Cannot cancel a rental with room bookings.",
                "gen_error.tt2",
            );
            return;
        }
        if (my @blocks = $r->blocks) {
            error($c,
                "Cannot cancel a rental with blocks.",
                "gen_error.tt2",
            );
            return;
        }
        if (my @res_clust = reserved_clusters($c, $id, 'Rental')) {
            error($c,
                "Cannot cancel a rental with reserved clusters.",
                "gen_error.tt2",
            );
            return;
        }
        $r->update({
            cancelled => 'yes',
        });
    }
    $c->response->redirect($c->uri_for("/rental/view/$id/1"));
}

sub grab_new : Local {
    my ($self, $c, $rental_id) = @_;

    system("grab wait");
    $c->response->redirect($c->uri_for("/rental/grid/$rental_id"));
}

sub send_grid : Local {
    my ($self, $c, $rental_id) = @_;
    my $r = model($c, 'Rental')->find($rental_id);
    $r->send_grid_data();
    $r->update({
        grid_stale => '',
    });
    $c->response->redirect($c->uri_for("/rental/view/$rental_id/1"));
}

sub mass_delete : Local {
    my ($self, $c, $rental_id) = @_;
    my $rental = model($c, 'Rental')->find($rental_id);
    stash($c,
        rental   => $rental,
        template => 'rental/mass_delete.tt2',
    );
}

sub mass_delete_do : Local {
    my ($self, $c, $rental_id) = @_;

    my $rental = model($c, 'Rental')->find($rental_id);
    my $sdate = $rental->sdate();
    my $edate1 = date($rental->edate()) - 1;
    $edate1 = $edate1->as_d8();

    %P = %{ $c->request->params() };
    for my $house_id (keys %P) {

        # remove booking
        model($c, 'RentalBooking')->search({
            rental_id => $rental_id,
            house_id  => $house_id,
        })->delete();

        # adjust config
        my $h = model($c, 'House')->find($house_id);
        my $max = $h->max;
        model($c, 'Config')->search({
            house_id => $house_id,
            the_date => { 'between' => [ $sdate, $edate1 ] },
        })->update({
            sex        => 'U',
            curmax     => $max,
            cur        => 0,
            program_id => 0,
            rental_id  => 0,
        });

    }
    $rental->set_grid_stale();
    # housing log?
    $c->response->redirect($c->uri_for("/rental/view/$rental_id/1"));
}

1;
