use strict;
use warnings;
package RetreatCenter::Controller::Ride;
use base 'Catalyst::Controller';

use lib '../..';
use Util qw/
    empty
    model
    trim
    email_letter
    fillin_template
    error
    tt_today
    stash
    invalid_amount
    penny
/;
use Date::Simple qw/
    date
    today
    days_in_month
/;
use Time::Simple qw/
    get_time
/;
use Algorithm::LUHN qw/
    is_valid
/;
use Global qw/
    %string
/;

my @airports = qw/
    SJC
    SFO
    OAK
    MRY
    OTH
/;

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('list');
}

#
# show future rides
# and ones that have not yet been paid for.
#
sub list : Local {
    my ($self, $c) = @_;

    stash($c,
        pg_title => "Rides",
        ride_list => _ride_list($c),
        template => "ride/list.tt2",
    );
}

sub _driver_list {
    my ($c, $cur_dr_id) = @_;
    my $opts = "<option value=0>Driver</option>\n";
    for my $dr (_get_drivers($c)) {
        my $dr_id = $dr->id();
        $opts .= "<option value="
              .  $dr_id
              .  ($cur_dr_id == $dr_id? " selected"
                  :                     ""         )
              .  ">"
              .  $dr->first()
              .  "</option>\n"
              ;
    }
    $opts;
}

sub _ride_list {
    my ($c, $aref_cond) = @_;
    if (! $aref_cond) {
        $aref_cond = [
            -or => [
                pickup_date => { '>=' => today()->as_d8() },
                paid_date   => '',
            ],
        ];
    }
    my @rides = model($c, 'Ride')->search(
        @$aref_cond,
        {
            join       => [qw/ rider /],
            prefetch   => [qw/ rider /],   
            order_by => 'pickup_date, shuttle, flight_time',
        },
    );
    my $rows = "";
    my $errors = "";
    my %to_fro = ();
    my %driver_for = ();
    my $class = "fl_row0";
    my ($prev_date, $prev_shuttle) = (0, 0);
    for my $r (@rides) {
        my $r_id = $r->id();
        my $driver_id = $r->driver_id();
        my $driver_name = ($r->driver_id()? $r->driver->first()
                           :                "Driver"           );
        if ($r->pickup_date() != $prev_date
            ||
            $r->shuttle()  != $prev_shuttle
        ) {
            $class = $class eq "fl_row0"? "fl_row1"
                     :                    "fl_row0"
                     ;
        }
        my $key = $r->shuttle() . "|" . $r->pickup_date();
        if ($r->shuttle() != 0
            && exists $to_fro{$key}
            && $to_fro{$key} ne $r->from_to()
        ) {
            $errors .= "Shuttle #" . $r->shuttle()
                    . " on " . $r->pickup_date_obj()
                    . " cannot be both from AND to MMC.<br>"
                    ;
        }
        else {
            $to_fro{$key} = $r->from_to();
        }
        if ($r->shuttle() != 0
            && $r->driver_id() != 0
            && exists $driver_for{$key}
            && $driver_for{$key} != $r->driver_id()
        ) {
            $errors .= "Shuttle #" . $r->shuttle()
                    . " on " . $r->pickup_date_obj()
                    . " has two different drivers.<br>"
                    ;
        }
        else {
            $driver_for{$key} = $r->driver_id();
        }
        $prev_date    = $r->pickup_date();
        $prev_shuttle = $r->shuttle();
        $rows .= "<tr class=$class>\n";

        $rows .= "<td>";
        if (!$r->complete()) {
            $rows .= "<img src=/static/images/question.jpg height=20>";
        }
        elsif (! $r->sent_date()) {
            $rows .= "<img src=/static/images/envelope.jpg height=20>";
        }
        elsif ($r->paid_date()) {
            $rows .= "<img src=/static/images/checked.gif>";
        }
        $rows .= "</td>\n";

        $rows .= "<td><a href=/ride/view/$r_id>"
              .  $r->rider->last() . ", " . $r->rider->first()
              .  "</a></td>\n"
              ;
        $rows .= "<td>"
              .  $r->from_to()
              .  "</td>\n"
              ;
        my $airport = $r->airport();
        $rows .= "<td align=left style='background: "
              .  sprintf("#%02x%02x%02x",
                         $string{"${airport}_color"} =~ m{(\d+)}g)
              .  "'>&nbsp;&nbsp;&nbsp;"
              .  $airport
              .  "</td>\n"
              ;
        $rows .= "<td>"
              .  $r->pickup_date_obj->format("%a %b %e")
              .  "</td>\n"
              ;
        $rows .= "<td align=right>"
              .  $r->flight_time_obj()
              .  "</td>\n"
              ;
        my $cost1 = penny($r->cost()) || 0;
        my $cost2 = $cost1;
        if ($cost1 == 0 && $r->comment() !~ m{cancel}i) {
            $cost1 = "Cost";
            $cost2 = "";
        }
        $rows .= <<"EOH";
<td align=right>
<div id=c$r_id style="display: block">
<a href='#' onclick="return edit_cost($r_id);">$cost1</a>
</div>
<!------>
<div id=ci$r_id style="display: none">
<input type=text size=3 id=cost$r_id onkeypress="return new_cost($r_id);" value='$cost2'>
</div>
</td>
EOH
        my $putime1 = $r->pickup_time_obj() || "Time";
        my $putime2 = $r->pickup_time_obj() || "";
        $rows .= <<"EOH";
<td align=right>
<div id=pu$r_id style="display: block">
<a href='#' onclick="return edit_pu($r_id);">$putime1</a>
</div>
<!------>
<div id=pui$r_id style="display: none">
<input type=text size=8 id=putime$r_id onkeypress="return new_pickuptime($r_id);" value='$putime2'>
</div>
</td>
EOH
        my $driver_list = _driver_list($c, $driver_id);
        $rows .= <<"EOH";

<td valign=top>
<div id=dr_n$r_id style="display: block">
<a href="#" onclick="return choose_driver($r_id);">$driver_name</a>
</div>
<!------>
<div id=dr_s$r_id style='display: none'>
<select id=dr_sel$r_id onchange="return new_driver($r_id);">
$driver_list
</select>
</div>
</td>

EOH
        my $sh = $r->shuttle();
        my $shuttle_name = ($sh == 0? "Shuttle"
                            :         "#$sh"          );
        my $shuttle_list = "<option value=0>Shuttle</option>\n";
        for my $i (1 .. $string{max_shuttles}) {
            $shuttle_list .= "<option value=$i"
                          .  ($i == $sh? " selected"
                              :          ""         )
                          .  ">#$i</a>"
                          .  "</option>\n"
                          ;
        }
        $rows .= <<"EOH";
<td valign=top align=center>
<div id=sh_n$r_id style="display: block">
<a href="#" onclick="return choose_shuttle($r_id);">$shuttle_name</a>
</div>
<!------>
<div id=sh_s$r_id style='display: none'>
<select id=sh_sel$r_id onchange="return new_shuttle($r_id);">
$shuttle_list
</select>
</div>
</td>
EOH
        $rows .= "</tr>";
    }
    if ($errors) {
        $errors .= "<p class=p2>\n";
    }
    # return a bare string heredoc!
    <<"EOH";
<span style="color: red">$errors</span>
<table cellpadding=5 border=0>
<tr valign=bottom>
<td></td>
<th align=left>Rider</th>
<th align=center>Direction</th>
<th align=left>Airport</th>
<th align=center>Pickup<br>Date</th>
<th align=center>Flight<br>Time</th>
<th align=right width=50>Cost</th>
<th align=center width=100>Pickup<br>Time</th>
<th align=left>Driver</th>
<th align=left>Shuttle</th>
</tr>
$rows
</table>
EOH
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    model($c, 'Ride')->find($id)->delete();
    Global->init($c);
    $c->response->redirect($c->uri_for('/ride/list'));
}

my %P;
my @mess;
sub _get_data {
    my ($c) = @_;

    %P = %{ $c->request->params() };
    @mess = ();
    if (! empty($P{pickup_date})) {
        my $dt = date($P{pickup_date});
        if ($dt) {
            $P{pickup_date} = $dt->as_d8();
        }
        else {
            push @mess, "Invalid pick up date: $P{pickup_date}";
        }
    }
    if (! empty($P{flight_time})) {
        my $t = get_time($P{flight_time});
        if (! $t) {
            push @mess, Time::Simple->error();
        }
        else {
            $P{flight_time} = $t->t24();
        }
    }
    if (! empty($P{pickup_time})) {
        my $t = get_time($P{pickup_time});
        if (! $t) {
            push @mess, Time::Simple->error();
        }
        else {
            $P{pickup_time} = $t->t24();
        }
    }
    if (! (   empty($P{cc_number1})
           && empty($P{cc_number2})
           && empty($P{cc_number3})
           && empty($P{cc_number4})
          )
    ) {
        if (   $P{cc_number1} !~ m{\d{4}}
            || $P{cc_number2} !~ m{\d{4}}
            || $P{cc_number3} !~ m{\d{4}}
            || $P{cc_number4} !~ m{\d{4}}
        ) {
            push @mess, "Invalid credit card number";
        }
    }
    if (! empty($P{cc_expire})) {
        if ($P{cc_expire} !~ m{(\d\d)(\d\d)}) {
            push @mess, "Invalid expiration date";
        }
        else {
            my $month = $1;
            my $year = $2;
            if (! (1 <= $month && $month <= 12)) {
                push @mess, "Invalid month in expiration date";
            }
            else {
                my $today = today();
                my $cur_century = (int($today->year() / 100)) * 100;
                    # another way to just get the century?

                my $exp_date = date($year + $cur_century,
                                    $month,
                                    days_in_month($year, $month)
                               );
                if ($today > $exp_date) {
                    push @mess, "Credit card has expired";
                }
            }
        }
    }
    if (! empty($P{cc_code}) && $P{cc_code} !~ m{\d{3}}) {
        push @mess, "Invalid security code";
    }
    $P{cc_number} = ($P{cc_number1} || "")
                  . ($P{cc_number2} || "")
                  . ($P{cc_number3} || "")
                  . ($P{cc_number4} || "")
                  ;
    for my $i (1 .. 4) {
        delete $P{"cc_number$i"};
    }
    if ((! empty($P{cost})) && invalid_amount($P{cost})) {
        push @mess, "Invalid cost";
    }
    if (empty($P{paid_date})) {
        $P{paid_date} = '';      # to be sure???
    }
    else {
        my $dt = date($P{paid_date});
        if ($dt) {
            $P{paid_date} = $dt->as_d8();
        }
        else {
            push @mess, "Invalid paid date: $P{paid_date}";
        }
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "ride/error.tt2";
    }
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $ride = model($c, 'Ride')->find($id);
    my $driver_opts = "<option value=0>Driver\n";
    for my $d (_get_drivers($c)) {
        my $id = $d->id();
        $driver_opts .= "<option value=$id"
                     . (($ride->driver_id() == $id)? " selected": "")
                     . "> "
                     . $d->first() . " " . $d->last()
                     . "\n"
                     ;
    }
    my $shuttle_opts = "<option value=0>Shuttle\n";
    for my $sh (1 .. $string{max_shuttles}) {
        $shuttle_opts .= "<option value=$sh"
                      .  ($ride->shuttle() == $sh? " selected"
                          :                        "")
                      .  ">#$sh\n";
    }

    my $opts = "";
    my $airport = $ride->airport();
    for my $a (@airports) {
        $opts .= "<option value=$a"
              .  (($a eq $airport)? " selected": "")
              .  "> $a - $string{$a}\n"
              ;
    }

    my $type = $ride->type();
    my $type_opts = "";
    for my $t (qw/ D C S O /) {
        $type_opts .= "<option value=$t"
                   .  ($type eq $t? " selected": "")
                   .  ">"
                   .  $string{"payment_$t"}
                   .  "\n";
                   ;
    }

    stash($c,
        ride         => $ride,
        driver_opts  => $driver_opts,
        shuttle_opts => $shuttle_opts,
        dir_from     => (($ride->from_to() eq "From MMC")? "checked": ""),
        dir_to       => (($ride->from_to() eq "To MMC"  )? "checked": ""),
        airport_opts => $opts,
        carrier      => $ride->carrier(),
        type_opts    => $type_opts,
        person       => $ride->rider(),
        form_action  => "update_do/$id",
        template     => "ride/create_edit.tt2",
    );
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    _get_data($c);
    return if @mess;
    my $ride = model($c, 'Ride')->find($id);
    my $rider = $ride->rider();
    $rider->update({
        cc_number => $P{cc_number},
        cc_expire => $P{cc_expire},
        cc_code   => $P{cc_code},
    });
    delete @P{qw/cc_number cc_expire cc_code/};
    my $changed = ($ride->pickup_time() ne $P{pickup_time});
    $ride->update(\%P);
    if ($changed) {
        #
        # pickup time has changed.
        # change other rides as well
        #
        my @cond = ();
        if ($ride->from_to() eq 'To MMC') {
            @cond = (airport => $ride->airport());
        }
        model($c, 'Ride')->search({
            pickup_date => $ride->pickup_date(),
            shuttle     => $ride->shuttle(),
            id          => { '!=' => $id },
            @cond,
        })->update({
            pickup_time => $P{pickup_time},
        });
    }
    Global->init($c);
    $c->response->redirect($c->uri_for("/ride/view/$id"));
}

sub create : Local {
    my ($self, $c, $person_id, $ride_id) = @_;

    my $airport = "SJC";        # default airport
    if ($ride_id) {
        # a return ride FROM the center
        #
        my $ride = model($c, 'Ride')->find($ride_id);
        $c->stash->{carrier} = $ride->carrier();
        $c->stash->{dir_from} = "checked";
        $airport = $ride->airport();        # for use below
    }
    else {
        # a ride TO the center
        #
        $c->stash->{dir_to} = "checked";
    }
    my $driver_opts = "<option value=0>Driver\n";
    for my $d (_get_drivers($c)) {
        $driver_opts .= "<option value="
                     . $d->id()
                     . "> "
                     . $d->first() . " " . $d->last()
                     . "\n"
                     ;
    }
    my $opts = "";
    for my $a (@airports) {
        $opts .= "<option value=$a"
              .  (($a eq $airport)? " selected": "")
              .  "> $a - $string{$a}\n";
    }

    my $type_opts = "";
    for my $t (qw/ D C S O /) {
        $type_opts .= "<option value=$t>"
                   .  $string{"payment_$t"}
                   .  "\n"
                   ;
    }

    my $shuttle_opts = "<option value=0>Shuttle</option>\n";
    for my $sh (1 .. $string{max_shuttles}) {
        $shuttle_opts .= "<option value=$sh>#$sh</option>\n";
    }
    stash($c,
        airport_opts => $opts,
        shuttle_opts => $shuttle_opts,
        type_opts    => $type_opts,
        driver_opts  => $driver_opts,
        person       => model($c, 'Person')->find($person_id),
        form_action  => "create_do/$person_id",
        template     => "ride/create_edit.tt2",
    );
}

sub create_do : Local {
    my ($self, $c, $person_id) = @_;

    _get_data($c);
    return if @mess;
    $P{rider_id} = $person_id;
    my $p = model($c, 'Person')->find($person_id);
    $p->update({
        cc_number => $P{cc_number},
        cc_expire => $P{cc_expire},
        cc_code   => $P{cc_code},
    });
    delete $P{cc_number};
    delete $P{cc_expire};
    delete $P{cc_code};
    my $ride = model($c, 'Ride')->create(\%P);
    $c->response->redirect($c->uri_for("/ride/view/" . $ride->id()));
}

# send email to driver and rider with the appropriate details.
#
sub send : Local {
    my ($self, $c, $id) = @_;

    my $ride = model($c, 'Ride')->find($id);
    my $driver = $ride->driver();
    my $rider = $ride->rider();
    my $snail = empty($rider->email());
    my @opt_addr;
    if ($snail) {
        push @opt_addr, 'snail_address', 
                          <<"EOS"
<style type='text/css'>
body {
    margin-top: 1.5in;
    margin-left: 1in;
}
</style>
EOS
                        . $rider->first() . " " . $rider->last() . "<br>"
                        . $rider->addr1() . "<br>"
                        . ((! empty($rider->addr2()))? $rider->addr2(): "")
                        . $rider->city() . ", "
                        . $rider->st_prov() . " " . $rider->zip_post()
                        . ((! empty($rider->country()))? $rider->country(): "")
                        . "<p>"
                        ;
    }
    my $html = fillin_template("letter/ride_confirm.tt2", {
        @opt_addr,
        ride      => $ride,
        user      => $c->user(),
        penalty   => $string{ride_cancel_penalty},
        airport   => $string{$ride->airport()},
        has_email => ! empty($rider->email()),
        pictures  => _driver_pics($ride),
    });
    if ($snail) {
        $ride->update({
            sent_date => today()->as_d8(),
        });
        $c->res->output($html);
        return;
    }
    else {
        email_letter($c,
            to      => $rider->name_email(),
            cc      => $driver->name_email(),
            from    => "MMC Transportation <$string{ride_email}>",
            subject => "Ride Scheduled",
            html    => $html,
        );
        # ??? did it send correctly?
        $ride->update({
            sent_date => today()->as_d8(),
        });
        $c->response->redirect($c->uri_for("/ride/view/$id/1"));
    }
}

sub view : Local {
    my ($self, $c, $id, $sent) = @_;

    my $ride = model($c, 'Ride')->find($id);
    $c->stash->{ride} = $ride;
    if ($sent) {
        $c->stash->{message} = "Email was sent.";
    }
    $c->stash->{template} = "ride/view.tt2";
}

sub pay : Local {
    my ($self, $c) = @_;

    if (tt_today($c)->as_d8() eq $string{last_deposit_date}) {
        error($c,
              'Since a deposit was just done'
                  . ' please make these payments tomorrow instead.',
              'gen_error.tt2');
        return;
    }
    my @rides = model($c, 'Ride')->search({
        pickup_date => { '<=', today()->as_d8() },
        paid_date   => '',
    });
    $c->stash->{rides} = \@rides;
    $c->stash->{template} = "ride/pay.tt2";
}

sub pay_do : Local {
    my ($self, $c) = @_;

    my @paid_ids;
    for my $p ($c->request->param()) {
        if ($p =~ m{r(\d+)}) {
            push @paid_ids, $1;
        }
    }
    my $now_date = tt_today($c)->as_d8();
    if (tt_today($c)->as_d8() eq $string{last_deposit_date}) {
        $now_date = (tt_today($c)+1)->as_d8();
    }
    if (@paid_ids) {
        my $today = today()->as_d8();
        model($c, 'Ride')->search({
            id => { -in => \@paid_ids },
        })->update({
            paid_date => $now_date,          
        });
    }
    $c->forward('list');
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

sub _get_cond {
    my ($c) = @_;
    my @cond = ();
    my $start = $c->request->params->{start};
    $start = date($start);
    if ($start) {
        push @cond, pickup_date => { '>=' => $start->as_d8() };
    }
    my $end = $c->request->params->{end};
    $end = date($end);
    if ($end) {
        if (@cond) {
            @cond = ();     # start fresh
            push @cond, -and => [
                            pickup_date => { '>=' => $start->as_d8() },
                            pickup_date => { '<=' => $end->as_d8() },
                        ];
        }
        else {
            push @cond, pickup_date => { '<=' => $end->as_d8() };
        }
    }
    my $name = $c->request->params->{name};
    if (! empty($name)) {
        $name =~ s{\*}{%}g;
        push @cond, 'rider.last' => { 'like' => "%$name%" };
    }
    if (! @cond) {
        # same as list
        #
        push @cond, -or => [
                        pickup_date => { '>=' => today()->as_d8() },
                        paid_date   => '',
                    ];
    }
    return \@cond;
}

sub search : Local {
    my ($self, $c) = @_;
    
    my $start = $c->request->params->{start};
    $start = date($start);
    my $end = $c->request->params->{end};
    $end = date($end);
    my $name = $c->request->params->{name};

    stash($c,
        pg_title  => "Rides",
        start     => ($start? $start->format("%D"): ""),
        end       => (  $end? $end->format("%D")  : ""),
        name      => $name,
        ride_list => _ride_list($c, _get_cond($c)),
        template  => "ride/list.tt2",
    );
}

sub mine : Local {
    my ($self, $c) = @_;

    my $driver_id = $c->user->obj->id();
    $c->stash->{ride_list} = _ride_list($c,
        [ driver_id => $driver_id ],
    );
    $c->stash->{template} = "ride/list.tt2";
}

#
# assign the driver_id to the ride.
# other rides on that day with the same shuttle #
# should get the new driver as well.
#
# return a whole new table for the list of rides.
# called via AJAX from list.tt2 when choosing a new driver
# directly from the list.
#
sub new_driver : Local {
    my ($self, $c, $ride_id, $driver_id) = @_;
    my $ride = model($c, 'Ride')->find($ride_id);
    $ride->update({
        driver_id => $driver_id,
    });
    model($c, 'Ride')->search({
        pickup_date => $ride->pickup_date(),
        shuttle     => $ride->shuttle(),
        id          => { '!=' => $ride_id },
    })->update({
        driver_id => $driver_id,
    });
    $c->res->output(_ride_list($c, _get_cond($c)));
}
#
# similarily for a new shuttle number
# but don't change other rides.
# if there is another ride with this shuttle
# on the same day with a driver, then take its
# driver for this ride.
#
sub new_shuttle : Local {
    my ($self, $c, $ride_id, $shuttle_num) = @_;
    my $ride = model($c, 'Ride')->find($ride_id);
    my @others = model($c, 'Ride')->search({
        pickup_date => $ride->pickup_date(),
        shuttle     => $shuttle_num,
        driver_id   => { '>' => 0 },
    });
    my @opt;
    if (@others) {
        @opt = (driver_id => $others[0]->driver_id());
    }
    $ride->update({
        shuttle => $shuttle_num,
        @opt,
    });
    $c->res->output(_ride_list($c, _get_cond($c)));
}

sub new_cost : Local {
    my ($self, $c, $ride_id, $cost) = @_;
    my $ride = model($c, 'Ride')->find($ride_id);
    $ride->update({
        cost => $cost,
    });
    $c->res->output(_ride_list($c, _get_cond($c)));
}

sub new_pickup_time : Local {
    my ($self, $c, $ride_id, $putime) = @_;
    my $ride = model($c, 'Ride')->find($ride_id);
    $ride->update({
        pickup_time => $putime,
    });
    $c->res->output(_ride_list($c, _get_cond($c)));
}

sub _get_drivers {
    my ($c) = @_;

    my (@roles) = model($c, "Role")->search({
        role => 'driver',
    });
    # should just be one role
    return $roles[0]->users();
}

sub drivers : Local {
    my ($self, $c) = @_;
    my $html = <<"EOH";
<table cellpadding=5>
<tr align=left>
<th>Name</th>
<th>Email</th>
<th>Cell</th>
</tr>
EOH
    for my $d (_get_drivers($c)) {
        $html .= "<tr>"
              . "<td>" . $d->first() . " " . $d->last() . "</td>"
              . "<td><a href='mailto:" . $d->email()
                   . "'>" . $d->email() . "</a></td>"
              . "<td>" . $d->cell() . "</td>"
              . "</tr>\n"
              ;
    }
    $html .= "</table>\n";
    $c->res->output($html);
}

sub _driver_pics {
    my ($ride) = @_;
    my $driver = $ride->driver();
    my $id = $driver->id();
    my @pics = <root/static/images/ub-$id*>;
    if (!@pics) {
        return "";
    }
    my $pics = "";
    for my $p (@pics) {
        my $mp = $p;
        $mp =~ s{root/static/images/}{};
        $pics .= "<p><img src=http://www.mountmadonna.org/userpics/$mp>";
    }
    my $pl = @pics > 1? "s": "";
    my $first = $ride->driver->first();
    return <<"EOH";
<p>
<hr style="width: 400px; margin-left: 0px; height: 1px">
<p>
Picture$pl of your driver, $first:
$pics
EOH
}

1;

=comment
simple test plan

create 7 rides with 2 or 3 on a day
    with varying times
don't assign shuttle or driver on the create screen

view the list
note the order of rides
    date, time
note the spacing between days

DOUBLE click on "Driver" and you can assign a new driver.
similarily for "Shuttle"
you can also change an existing driver or shuttle in the same way.

if you change the driver of a ride then
    other rides on that same day with the same
    shuttle number will get that same newly assigned driver.
if you change the shuttle number of a ride
    and there are other rides with that shuttle number on that same day
    which have a driver, that driver (the first one) will be used
    for the ride you just changed.

note that all rides in a shuttle have the same background color
and the next shuttle in a day will have a different background
note the order of the rides
    date, shuttle, time

- can't have a shuttle both from AND to MMC.
- if you edit a ride individually and change
    the driver or shuttle you can end up with
    one shuttle having two different drivers.
in both these cases you will see a red error message
    below the table of rides.
=cut
