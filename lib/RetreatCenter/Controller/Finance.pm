use strict;
use warnings;
package RetreatCenter::Controller::Finance;
use base 'Catalyst::Controller';

use Util qw/
    model
    commify
    stash
    tt_today
    mmi_glnum
    accpacc
    error
    penny
/;
use Date::Simple qw/
    date
    today
/;
use Time::Simple qw/
    get_time
/;
use Global qw/
    %string
/;

sub reconcile_deposit : Local {
    my ($self, $c, $sponsor, $id, $prelim) = @_;

    my $host = ($sponsor eq 'mmi')? "mmi_": "";
    my ($date_start, $date_end);
    my $dep;
    if ($id) {
        $dep = model($c, 'Deposit')->find($id);
        $date_start = $dep->date_start();
        $date_end   = $dep->date_end();
    }
    else {
        $date_start = (date($string{"last_${host}deposit_date"})+1)->as_d8();
        $date_end   = tt_today($c)->as_d8();
    }
    if ($date_end < $date_start) {
        # we just made a deposit and are asking again
        stash($c, template => "finance/already.tt2");
        return;
    }
    my $cond = {
        the_date => { between => [ $date_start, $date_end ] },
    };
    my @payments;
    my ($cash, $check, $credit, $online, $total) = (0) x 5;
    my @sources = ($sponsor eq 'mmc')? qw/
                      RegPayment
                      RentalPayment
                  /:
                  qw/
                      MMIPayment
                  /;
    push @sources, "XAccountPayment";       # for both
    # Donations are not included in deposits, no???
    #

    for my $src (@sources) {
        PAYMENT1:
        for my $p (model($c, $src)->search($cond)) {
            next PAYMENT1 if $src eq 'XAccountPayment'
                             && $p->xaccount->sponsor() ne $sponsor;
            my $type = $p->type();
            my $amt  = $p->amount_disp();
            next PAYMENT1 if $amt == 0;       # bogus payment
            if ($type eq 'D') {
                $credit += $amt;
            }
            elsif ($type eq 'C') {
                $check += $amt;
            }
            elsif ($type eq 'S') {
                $cash += $amt;
            }
            elsif ($type eq 'O') {
                $online += $amt;
            }
            $total += $amt;
            push @payments, {
                name   => $p->name(),
                link   => $p->link(),
                date   => $p->the_date_obj->format("%D"),
                type   => $type,
                cash   => ($type eq 'S')? $amt: "",
                chk    => ($type eq 'C')? $amt: "",
                credit => ($type eq 'D')? $amt: "",
                online => ($type eq 'O')? $amt: "",
                pname  => $p->pname(),
            };
        }
    }
    if ($sponsor eq 'mmc') {
        # ride payments are handled differently
        # and it is always a credit card payment.
        # not any more!
        #
        RIDE1:
        for my $r (model($c, 'Ride')->search({
                       paid_date => { between => [ $date_start, $date_end ] },
                   })
        ) {
            my $type = $r->type();
            my $amt = $r->cost_disp();
            next RIDE1 if $amt == 0;       # bogus payment
            if ($type eq 'D') {
                $credit += $amt;
            }
            elsif ($type eq 'C') {
                $check += $amt;
            }
            elsif ($type eq 'S') {
                $cash += $amt;
            }
            elsif ($type eq 'O') {
                $online += $amt;
            }
            $total += $amt;
            push @payments, {
                name   => $r->name(),
                link   => $r->link(),
                date   => $r->paid_date_obj->format("%D"),
                type   => $type,
                cash   => ($type eq 'S')? $amt: "",
                chk    => ($type eq 'C')? $amt: "",
                credit => ($type eq 'D')? $amt: "",
                online => ($type eq 'O')? $amt: "",
                pname  => "Ride",
            };
        }
    }
    @payments = sort {
                        lc $a->{name} cmp lc $b->{name}
                    }
                    @payments;

    if (! $id) {
        $string{"$sponsor\_reconciling"} = ($prelim)? ""
                                           :          $c->user->obj->username()
                                           ;
        # on disk???  not needed?
    }

    stash($c,
        sponsor  => $sponsor,
        SPONSOR  => uc $sponsor,
        payments => \@payments,
        again    => (! $id && ! $prelim),
        prelim   => $prelim,
        cash     => $cash,
        check    => $check,
        credit   => $credit,
        online   => $online,
        total    => commify($total),
        template => "finance/deposit.tt2",
    );
}

#
# the optional id is passed in if we are viewing a past deposit.
# Without it we are creating a new one.
# dup'ed code from above - DRY???
#
sub file_deposit : Local {
    my ($self, $c, $sponsor, $id) = @_;

    my $host = ($sponsor eq 'mmi')? "mmi_": "";
    my ($date_start, $date_end);
    my $dep;
    if ($id) {
        $dep = model($c, 'Deposit')->find($id);
        $date_start = $dep->date_start();
        $date_end   = $dep->date_end();
    }
    else {
        $date_start = (date($string{"last_${host}deposit_date"})+1)->as_d8();
        $date_end   = tt_today($c)->as_d8();
    }
    if ($date_end < $date_start) {
        # we just made a deposit and are asking again
        stash($c, template => "finance/already.tt2");
        return;
    }

    my $cond = {
        the_date => { between => [ $date_start, $date_end ] },
    };
    my @payments;
    my @sources = ($sponsor eq 'mmc')? qw/
                      RegPayment
                      RentalPayment
                  /:
                  qw/
                      MMIPayment
                  /;
    push @sources, "XAccountPayment";       # for both
    # Donations are not included in deposits, no???
    #
    for my $src (@sources) {
        PAYMENT2:
        for my $p (model($c, $src)->search($cond)) {
            next PAYMENT2 if $src eq 'XAccountPayment'
                             && $p->xaccount->sponsor() ne $sponsor; 
            my $type = $p->type();
            my $amt  = $p->amount_disp();
            next PAYMENT2 if $amt == 0;      # bogus payment
            my $glnum = $p->glnum();
            push @payments, {
                name   => $p->name(),
                date   => $p->the_date_obj->format("%D"),
                type   => $type,
                amt    => $amt,
                glnum  => $glnum,
                pname  => $p->pname(),
            };
        }
    }
    if ($sponsor eq 'mmc') {
        # ride payments are handled differently
        # and it is always a credit card payment.
        # not any more!
        #
        RIDE2:
        for my $r (model($c, 'Ride')->search({
                       paid_date => { between => [ $date_start, $date_end ] },
                   })
        ) {
            my $amt = $r->cost_disp();
            next RIDE2 if $amt == 0;       # bogus payment
            push @payments, {
                name  => $r->name(),
                date  => $r->paid_date_obj->format("%D"),
                type  => $r->type(),
                amt   => $amt,
                glnum => $string{ride_glnum},
                pname => "Ride",
            };
        }
    }

    # Cash
    # Check
    # Credit Card
    # Online

    @payments = sort {
                        (lc $a->{pname} cmp lc $b->{pname}) ||
                        (   $a->{glnum} cmp    $b->{glnum}) ||
                        (   $a->{date}  cmp    $b->{date} ) ||
                        (lc $a->{name}  cmp lc $b->{name} ) ||
                        (   $a->{amt}   <=>    $b->{amt}  )
                    }
                    @payments;

    my $indent = "&nbsp;" x 5;

    my $timestamp;
    if ($id) {
        $timestamp = date($date_end)->format("%D")
                   . " "
                   . $dep->time_obj()->ampm()
                   ;
    }
    else {
        $timestamp = tt_today($c)->format("%D")
                   . " "
                   . get_time()->ampm()
                   ;
    }
    my $html = <<"EOH";
<style type="text/css">
body, td, th {
    font-size: 11pt;
    font-family: Courier;
}
</style>
EOH
my $heading = <<"EOH";
$timestamp<span style="font-size: 15pt; font-weight: bold; margin-left: 1in;">\U$sponsor\E Bank Deposit</span>
<p>
<table cellpadding=1>
<tr valign=bottom>
<th align=left><b>Account</b> (GL number)<br>${indent}Name</th>
<th align=center>Date</th>
<th align=right width=70>Cash</th>
<th align=right width=70>Check</th>
<th align=right width=70>Credit</th>
<th align=right width=70>Total</th>
</tr>
<tr><td colspan=6><hr color=black></td></tr>
EOH
    my $newpage = <<"EOH";
<div style='page-break-after:always'></div>
EOH
    $html .= $heading;
    my $prev_glnum = "";
    my $prev_pname = "";     # needed for MMI programs
    my ($cash, $check, $credit, $online) = (0, 0, 0, 0);
    my ($gcash, $gcheck, $gcredit, $gonline, $gtotal) = (0, 0, 0, 0);
    my $nrows = 0;
    for my $p (@payments) {
        if ($nrows > $string{deposit_lines_per_page}) {
            $html .= "</table>" . $newpage . $heading;
            $nrows = 0;
        }
        if ($p->{glnum} ne $prev_glnum) {
            if ($prev_glnum || $prev_pname) {
                my $total = $cash + $check + $credit + $online;
                $html .= "<tr>"
                      .  "<td colspan=2></td>"
                      .  "<td><hr color=black></td>"
                      .  "<td><hr color=black></td>"
                      .  "<td><hr color=black></td>"
                      .  "</tr>\n";
                $html .= "<tr>"
                      .  "<td colspan=3 align=right>$cash</td>"
                      .  "<td align=right>$check</td>"
                      .  "<td align=right>" . ($credit + $online) . "</td>"
                      .  "<td align=right>"
                      .  commify($total)
                      .  "</td>"
                      .  "</tr>\n"
                      ;
                $html .= "<tr><td>&nbsp;</td></tr>\n";
                $nrows += 3;
                $gcash   += $cash;
                $gcheck  += $check;
                $gonline += $online;
                $gcredit += $credit + $online;
                $gtotal  += $total;
                ($cash, $check, $credit, $online) = (0, 0, 0, 0);
                if ($nrows+10 > $string{deposit_lines_per_page}) {
                    $html .= "</table>" . $newpage . $heading;
                    $nrows = 0;
                }
            }
            $html .= "<tr>"
                  .  "<td colspan=6 align=left><b>$p->{pname}</b> ($p->{glnum})</td>"
                  .  "</tr>\n"
                  ;
            ++$nrows;
        }
        $prev_glnum = $p->{glnum};
        $prev_pname = $p->{pname};
        my $type = $p->{type};
        my $n = ($type eq 'S')? 1
               :($type eq 'C')? 2
               :($type eq 'D')? 3       # Credit
               :                3       # Online
               ;
        my $amt = $p->{amt};
        $html .= "<tr>"
              .  "<td align=left>$indent$p->{name}</td>"
              .  "<td align=center>$p->{date}</td>"
              .  "<td align=right colspan=$n>$amt</td>"
              ;
        if ($type eq 'O') {
            $html .= "<td>*</td>";
        }
        $html .= "</tr>\n";
        ++$nrows;
        if ($type eq 'S') {
            $cash += $amt;
        }
        elsif ($type eq 'C') {
            $check += $amt;
        }
        elsif ($type eq 'D') {
            $credit += $amt;
        }
        else {
            $online += $amt;
        }
    }
    my $total = $cash + $check + $credit + $online;
    $html .= "<tr>"
          .  "<td colspan=2></td>"
          .  "<td><hr color=black></td>"
          .  "<td><hr color=black></td>"
          .  "<td><hr color=black></td>"
          .  "</tr>\n";
    $html .= "<tr>"
          .  "<td colspan=3 align=right>$cash</td>"
          .  "<td align=right>$check</td>"
          .  "<td align=right>" . ($credit + $online) .  "</td>"
          .  "<td align=right>"
          .  commify($total)
          .  "</td>"
          .  "</tr>\n"
          ;
    $html .= "<tr><td>&nbsp;</td></tr>\n";
    $gcash   += $cash;
    $gcheck  += $check;
    $gcredit += $credit + $online;
    $gonline += $online;
    $gtotal  += $total;
    $html .= "<tr><td colspan=2></td>"
          .  "<td><hr color=black></td>"
          .  "<td><hr color=black></td>"
          .  "<td><hr color=black></td>"
          .  "<td><hr color=black></td>"
          .  "</tr>\n";
    $html .= "<tr>"
          .  "<td colspan=3 align=right>$gcash</td>"
          .  "<td align=right>$gcheck</td>"
          .  "<td align=right>$gcredit</td>"
          .  "<td align=right>\$"
          .  commify($gtotal)
          .  "</td>"
          .  "</tr>\n"
          ;
    $html .= <<"EOH";
</table>
EOH
    if (! $id) {
        if ($gtotal != 0) {
            #
            # create a new deposit and update the "last_${host}deposit_date"
            #
            model($c, 'Deposit')->create({
                user_id    => $c->user->obj->id(),
                time       => get_time()->t24(),
                date_start => $date_start,
                date_end   => $date_end,
                cash       => $gcash,
                chk        => $gcheck,
                credit     => $gcredit,
                online     => $gonline,
                sponsor    => $sponsor,
            });

            # in memory
            $string{"last_${host}deposit_date"} = $date_end;         

            # on disk
            model($c, 'String')->find("last_${host}deposit_date")->update({
                value => $date_end,
            });
        }
        $string{"$sponsor\_reconciling"} = "";
        # only in memory???
    }
    $c->res->output($html);
}

sub deposits : Local {
    my ($self, $c, $sponsor) = @_;

    my $dt;
    if ($dt = $c->request->params->{date_end}) {
        $dt = date($dt);
        if (! $dt) {
            $dt = tt_today($c);
        }
    }
    else {
        $dt = tt_today($c);
    }
    stash($c,
        deposits => [ 
            model($c, 'Deposit')->search(
                {
                    sponsor   => $sponsor,
                    date_end => { '<=', $dt->as_d8() },
                },
                {
                    rows => 10,
                    order_by => 'date_start desc'
                },
            )
        ],
        sponsor   => $sponsor,
        SPONSOR   => uc $sponsor,
        template => "finance/prior_deposits.tt2",
    );
}

sub period_end : Local {
    my ($self, $c, $sponsor) = @_;

    my $sdate = $c->request->params->{sdate};
    my $edate = $c->request->params->{edate};

    # validation
    my $start = $sdate? date($sdate): "";
    if (! $start) {
        $c->stash->{mess} = "Illegal start date: $sdate";
        $c->stash->{template} = "gen_error.tt2";
        return;
    }

    Date::Simple->relative_date($start);
    my $end = $edate? date($edate): "";
    Date::Simple->relative_date();

    if (! $end) {
        $c->stash->{mess} = "Illegal end date: $edate";
        $c->stash->{template} = "gen_error.tt2";
        return;
    }
    if ($end < $start) {
        $c->stash->{mess} = "End date must be after Start date.";
        $c->stash->{template} = "gen_error.tt2";
        return;
    }

    my $start_d8 = $start->as_d8();
    my $end_d8   = $end->as_d8();

    #
    # key is general ledger number.
    # value is {
    #    name   => ,
    #    link   => ,
    #    amount => ,
    #    cash   => ,
    #    check. => ,
    #    credit => ,            (includes online)
    # }.
    # then sort by name for display.
    #
    my %totals = ();

    my $cond = {
        the_date => { between => [ $start_d8, $end_d8 ] },
    };

    # copied from above :( DRY??? YES revisit.
    my @sources = ($sponsor eq 'mmc')? qw/
                      RegPayment
                      RentalPayment
                  /:
                  qw/
                      MMIPayment
                  /;
    push @sources, 'XAccountPayment';       # for both
    # Donations are not included in deposits, no???
    #
    for my $src (@sources) {
        PAYMENT3:
        for my $p (model($c, $src)->search($cond)) {
            next PAYMENT3 if $src eq 'XAccountPayment'
                             && ($p->xaccount->sponsor() ne $sponsor);
            my $type = $p->type();
            my $amt  = $p->amount_disp();
            my $glnum = $p->glnum();
            if (! exists $totals{$glnum}) {
                # initialize this entry
                #
                my ($name, $link);
                if ($src eq 'MMIPayment') {
                    ($name, $link) = mmi_glnum($c, $glnum);
                }
                else {
                    $name = $p->pname();
                    $link = $p->plink();
                }
                $totals{$glnum} = {
                    name   => $name,
                    type   => ($src eq "RegPayment"     ? ' '
                              :$src eq "RentalPayment"  ? '*'
                              :$src eq "XAccountPayment"? 'x'
                              :$src eq "MMIPayment"     ? ' '
                              :                           ' '),
                    link   => $link,
                    glnum  => $glnum,
                    amount => 0,
                    cash   => 0,
                    check  => 0,
                    credit => 0,
                };
                if ($src eq 'MMIPayment') {
                    $totals{$glnum}{accpacc_num} = accpacc($glnum);
                }
            }
            my $href = $totals{$glnum};
            $href->{amount} += $amt;
            $href->{
                $type eq 'S'? 'cash'
               :$type eq 'C'? 'check'
               :              'credit'      # includes online
            } += $amt;
        }
    }
    if ($sponsor eq 'mmc') {
        # ride payments are handled differently
        # and it is always a credit card payment. - not any more.
        #
        my $rgl = $string{ride_glnum};
        RIDE3:
        for my $r (model($c, 'Ride')->search({
                       paid_date => { between => [ $start_d8, $end_d8 ] },
                   })
        ) {
            my $href = $totals{$rgl};
            my $amt = $r->cost_disp();
            next RIDE3 if $amt == 0;        # bogus payment
            if (! exists $totals{$rgl}) {
                $totals{$rgl} = {
                    name  => 'Rides',
                    type  => 'r',
                    link  => "/ride/list",
                    glnum => $rgl,
                };
            }
            $href->{amount} += $amt;
            my $type = $r->type();
            $href->{
                $type eq 'S'? 'cash'
               :$type eq 'C'? 'check'
               :              'credit'      # includes online
            } += $amt;
        }
    }
    my %grand_total;
    for my $t (keys %totals) {
        my $href = $totals{$t};
        for my $n (qw/ amount cash check credit online /) {
            $grand_total{$n} += ($href->{$n} || 0);
            $href->{$n} = commify($href->{$n});
        }
    }
    for my $n (keys %grand_total) {
        $grand_total{$n} = commify($grand_total{$n});
    }
    stash($c,
        SPONSOR     => uc $sponsor,
        start       => $start,
        end         => $end,
        totals      => [ sort { $a->{name} cmp $b->{name} } values %totals ],
        grand_total => \%grand_total,
        timestamp   => scalar(localtime),
        template    => "finance/period_end.tt2",
    );
}

sub outstanding : Local {
    my ($self, $c) = @_;

    my $since_str = $c->request->params->{since};
    my $since = date($since_str);
    if (! $since) {
        error($c,
              "Illegal date: $since_str",
              'gen_error.tt2',
        );
        return;
    }
    my $yesterday = today()-1;
    my @outbals = ();
    my @regs = model($c, 'Registration')->search(
        {
            date_start       => { 'between' => [ $since->as_d8(),
                                           $yesterday->as_d8() ] },
            balance          => { '!=' => 0 },
            cancelled        => { '!=' => 'yes' }, 
            'program.school' => 0,      # no MMI
        },
        {
            prefetch => ['program'],
            join     => ['program'],
        }
    );
    for my $r (@regs) {
        push @outbals, {
            date => $r->date_start_obj(),
            name => $r->person->first() . " " . $r->person->last(),
            program => $r->program->name(),
            link => $c->uri_for("/registration/view/" . $r->id()),
            balance => penny($r->balance()),
        };
    }
    my @rentals = model($c, 'Rental')->search({
        sdate   => { 'between' => [ $since->as_d8(), $yesterday->as_d8() ] },
        balance => { '!=' => 0 },
    });
    for my $r (@rentals) {
        push @outbals, {
            date => $r->sdate_obj(),
            name => $r->name(),
            program => '',
            link => $c->uri_for("/rental/view/" . $r->id() . "/3"),
            balance => penny($r->balance()),
        };
    }
    @outbals = sort {
                   $b->{date} <=> $a->{date}
               }
               @outbals;
    stash($c,
        since    => $since,
        outbals  => \@outbals,
        template => 'finance/outstanding.tt2',
    );
}

#
# gather Extra Accounts and Programs (since $since) sponsored by MMC
#
sub glnum_list : Local {
    my ($self, $c, $since_param, $psort, $xsort) = @_;

    if (! defined $psort) {
        $psort = 0;
    }
    if (! defined $xsort) {
        $xsort = 0;
    }
    my $since_str = $since_param || $c->request->params->{since};
    if (! $since_str) {
        my $today = today();
        my $y = $today->year();
        my $m = $today->month();
        $since_str = date($y-1, $m, 1)->as_d8();
    }
    my $since = date($since_str);
    if (! $since) {
        error($c,
              "Illegal date: $since_str",
              'gen_error.tt2',
        );
        return;
    }
    my $porder = $psort == 0? 'glnum'
                :$psort == 1? 'name'
                :             'sdate'
                ;
    my @progs = model($c, 'Program')->search(
                    {
                        sdate     => { '>=' => $since->as_d8() },
                        school    => 0,
                        rental_id => 0,     # no hybrid programs
                                            # the finances are on the Rental
                    },
                    {
                        order_by => [ $porder ],
                    }
                );
    my @rents = model($c, 'Rental')->search(
                    {
                        sdate  => { '>=' => $since->as_d8() },
                    },
                    {
                        order_by => [ $porder ],
                    }
                );
    my @events = sort {
                     $a->$porder cmp $b->$porder        # cool!
                 }
                 @progs, @rents;
    my @projs = model($c, 'Project')->search(
                    {
                    },
                    {
                        order_by => [ 'glnum' ],
                    }
                );
    my $xorder = $xsort == 0? 'glnum'
                :             'descr'
                ;
    my @xaccts = model($c, 'XAccount')->search(
                     {
                        sponsor => 'mmc',
                     },
                     {
                        order_by => [$xorder],
                     },
                 );
    my %glnum_count = ();
    my $ndups = 0;
    ITEM:
    for my $item (@events, @projs, @xaccts) {
        my $n = $item->glnum();
        if (exists $glnum_count{$n}
            && (!$item->can('name') || $item->name() !~ m{personal\s+retreat}i)
        ) {
            $item->{dup} = $glnum_count{$n}->{dup} = 1;
            ++$ndups;
            next ITEM;
        }
        $glnum_count{$n} = $item;
    }
    stash($c,
        ndups    => $ndups,
        since    => $since,
        psort    => $psort,
        xsort    => $xsort,
        events   => \@events,
        projs    => \@projs,
        xaccts   => \@xaccts,
        ride_glnum  => $string{ride_glnum},
        template => 'finance/glnum.tt2',
    );
}

#
# gather Extra Accounts and Programs (since $since) sponsored by MMI
#
sub mmi_glnum_list : Local {
    my ($self, $c, $since_param, $psort, $xsort) = @_;

    if (! defined $psort) {
        $psort = 0;
    }
    if (! defined $xsort) {
        $xsort = 0;
    }
    my $since_str = $since_param || $c->request->params->{since};
    if (! $since_str) {
        my $today = today();
        my $y = $today->year();
        my $m = $today->month();
        $since_str = date($y-1, $m, 1)->as_d8();
    }
    my $since = date($since_str);
    if (! $since) {
        error($c,
              "Illegal date: $since_str",
              'gen_error.tt2',
        );
        return;
    }
    my $porder = $psort == 0? 'glnum'
                :$psort == 1? 'name'
                :             'sdate'
                ;
    my @progs = model($c, 'Program')->search(
                    {
                        sdate  => { '>=' => $since->as_d8() },
                        school => { '!=' => 0 },
                    },
                    {
                        order_by => [ $porder ],
                    }
                );
    my $xorder = $xsort == 0? 'glnum'
                :             'descr'
                ;
    my @xaccts = model($c, 'XAccount')->search(
                     {
                        sponsor => 'mmi',
                     },
                     {
                        order_by => [$xorder],
                     },
                 );
    stash($c,
        since    => $since,
        psort    => $psort,
        xsort    => $xsort,
        programs => \@progs,
        xaccts   => \@xaccts,
        template => 'finance/mmi_glnum.tt2',
    );
}

sub ride : Local {
    my ($self, $c) = @_;

    my $since_str = $c->request->params->{since_2months};
    my $since = date($since_str);
    if (! $since) {
        error($c,
              "Illegal date: $since_str",
              'gen_error.tt2',
        );
        return;
    }
    my @rides = model($c, 'Ride')->search(
                    {
                        paid_date => { '>=' => $since->as_d8() },
                    },
                );
    my %nrides = ();
    my %total = ();
    my $gtot = 0;
    for my $r (@rides) {
        my $d_id = $r->driver_id();
        ++$nrides{$d_id};
        my $c = $r->cost();
        $total{$d_id} += $c;
        $gtot += $c;
    }
    my @drivers = model($c, 'User')->search(
        {
            id => { in => [keys %nrides] },
        },
        {
            order_by => ['first'],
        }
    );
    # to make it easier in the template:
    for my $d (@drivers) {
        my $d_id = $d->id();
        $d->{nrides} = $nrides{$d_id};
        $d->{total} = $total{$d_id};
    }
    stash($c,
        since    => $since,
        drivers  => \@drivers,
        gtot     => $gtot,
        template => "finance/rides.tt2",
    );
}

1;
