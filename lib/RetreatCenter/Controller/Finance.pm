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

sub index : Local {
    my ($self, $c) = @_;

    $c->stash->{template} = "finance/index.tt2";
}

sub reconcile_deposit : Local {
    my ($self, $c, $source, $id) = @_;

    my ($date_start, $date_end);
    my $dep;
    if ($id) {
        $dep = model($c, 'Deposit')->find($id);
        $date_start = $dep->date_start();
        $date_end   = $dep->date_end();
    }
    else {
        $date_start = (date($string{last_deposit_date})+1)->as_d8();
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
    my @sources = ($source eq 'mmc')? qw/
                      RegPayment
                      XAccountPayment
                      RentalPayment
                  /:
                  qw/
                      MMIPayment
                  /;
    # Donations are not included in deposits, no???
    #
    for my $src (@sources) {
        for my $p (model($c, $src)->search($cond)) {
            my $type = $p->type;
            my $amt  = $p->amount;
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
                name   => $p->name,
                link   => $p->link,
                date   => $p->the_date_obj->format("%D"),
                type   => $type,
                cash   => ($type eq 'S')? $amt: "",
                chk    => ($type eq 'C')? $amt: "",
                credit => ($type eq 'D')? $amt: "",
                online => ($type eq 'O')? $amt: "",
                pname  => $p->pname,
            };
        }
    }
    if ($source eq 'mmc') {
        # ride payments are handled differently
        # and it is always a credit card payment.
        #
        for my $r (model($c, 'Ride')->search({
                       paid_date => { between => [ $date_start, $date_end ] },
                   })
        ) {
            my $amt = $r->cost();
            push @payments, {
                name => $r->name(),
                link => $r->link(),
                date => $r->paid_date_obj->format("%D"),
                type => 'C',
                cash => 0,
                chk  => 0,
                credit => $amt,
                online => 0,
                pname => "Ride",
            };
            $credit += $amt;
            $total += $amt;
        }
    }
    @payments = sort {
                        $a->{name} cmp $b->{name}
                    }
                    @payments;

    if (! $id) {
        $string{reconciling} = $c->user->obj->username();
        # on disk??  not needed?
    }

    stash($c,
        source   => $source,
        payments => \@payments,
        again    => ! $id,
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
    my ($self, $c, $source, $id) = @_;

    my ($date_start, $date_end);
    my $dep;
    if ($id) {
        $dep = model($c, 'Deposit')->find($id);
        $date_start = $dep->date_start();
        $date_end   = $dep->date_end();
    }
    else {
        $date_start = (date($string{last_deposit_date})+1)->as_d8();
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
    my @sources = ($source eq 'mmc')? qw/
                      RegPayment
                      XAccountPayment
                      RentalPayment
                  /:
                  qw/
                      MMIPayment
                  /;
    # Donations are not included in deposits, no???
    #
    for my $src (@sources) {
        for my $p (model($c, $src)->search($cond)) {
            my $type = $p->type();
            my $amt  = $p->amount();
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
    if ($source eq 'mmc') {
        # ride payments are handled differently
        # and it is always a credit card payment.
        #
        for my $r (model($c, 'Ride')->search({
                       paid_date => { between => [ $date_start, $date_end ] },
                   })
        ) {
            push @payments, {
                name => $r->name(),
                date => $r->paid_date_obj->format("%D"),
                type => 'C',
                amt   => $r->cost(),
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
                        ($a->{pname} cmp $b->{pname}) ||
                        ($a->{glnum} cmp $b->{glnum}) ||
                        ($a->{name}  cmp $b->{name} ) ||
                        ($a->{date}  cmp $b->{date} ) ||
                        ($a->{amt}   cmp $b->{amt}  )
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
body {
    font-size: 13pt;
    font-family: Helvetica;
}
td, th {
    font-size: 15pt;
}
</style>
$timestamp<span style="font-size: 25pt; font-weight: bold; margin-left: 1in;">Bank Deposit</span>
<p>
<table cellpadding=3>
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
    my $prev_glnum = "";
    my $prev_pname = "";     # needed for MMI programs
    my ($cash, $check, $credit) = (0, 0, 0);
    my ($gcash, $gcheck, $gcredit, $gtotal) = (0, 0, 0, 0);
    for my $p (@payments) {
        if ($p->{glnum} ne $prev_glnum) {
            if ($prev_glnum || $prev_pname) {
                my $total = $cash+$check+$credit;
                $html .= "<tr>"
                      .  "<td colspan=2></td>"
                      .  "<td><hr color=black></td>"
                      .  "<td><hr color=black></td>"
                      .  "<td><hr color=black></td>"
                      .  "</tr>\n";
                $html .= "<tr>"
                      .  "<td colspan=3 align=right>$cash</td>"
                      .  "<td align=right>$check</td>"
                      .  "<td align=right>$credit</td>"
                      .  "<td align=right>"
                      .  commify($total)
                      .  "</td>"
                      .  "</tr>\n"
                      ;
                $html .= "<tr><td>&nbsp;</td></tr>\n";
                $gcash   += $cash;
                $gcheck  += $check;
                $gcredit += $credit;
                $gtotal  += $total;
                ($cash, $check, $credit) = (0, 0, 0);
            }
            $html .= "<tr>"
                  .  "<td colspan=6 align=left><b>$p->{pname}</b> ($p->{glnum})</td>"
                  .  "</tr>\n"
                  ;
        }
        $prev_glnum = $p->{glnum};
        $prev_pname = $p->{pname};
        my $type = $p->{type};
        my $n = ($type eq "S")? 1
               :($type eq "C")? 2
               :                3       # Credit - includes Online
               ;
        my $amt = $p->{amt};
        $html .= "<tr>"
              .  "<td align=left>$indent$p->{name}</td>"
              .  "<td align=center>$p->{date}</td>"
              .  "<td align=right colspan=$n>$amt</td>"
              .  "</tr>\n"
              ;
        if ($n == 1) {
            $cash += $amt;
        }
        elsif ($n == 2) {
            $check += $amt;
        }
        else {
            $credit += $amt;
        }
    }
    my $total = $cash+$check+$credit;
    $html .= "<tr>"
          .  "<td colspan=2></td>"
          .  "<td><hr color=black></td>"
          .  "<td><hr color=black></td>"
          .  "<td><hr color=black></td>"
          .  "</tr>\n";
    $html .= "<tr>"
          .  "<td colspan=3 align=right>$cash</td>"
          .  "<td align=right>$check</td>"
          .  "<td align=right>$credit</td>"
          .  "<td align=right>"
          .  commify($total)
          .  "</td>"
          .  "</tr>\n"
          ;
    $html .= "<tr><td>&nbsp;</td></tr>\n";
    $gcash   += $cash;
    $gcheck  += $check;
    $gcredit += $credit;
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
            # create a new deposit and update the last_deposit_date
            #
            model($c, 'Deposit')->create({
                user_id    => $c->user->obj->id(),
                time       => get_time()->t24(),
                date_start => $date_start,
                date_end   => $date_end,
                cash       => $gcash,
                chk        => $gcheck,
                credit     => $gcredit,
                source     => $source,
            });
            $string{last_deposit_date} = $date_end;         # in memory
            model($c, 'String')->find('last_deposit_date')->update({  # on disk
                value => $date_end,
            });
        }
        $string{reconciling} = 0;   # only in memory???
    }
    $c->res->output($html);
}

sub deposits : Local {
    my ($self, $c, $source) = @_;

    my $dt;
    if ($dt = $c->request->params->{date_end}) {
        $dt = date($dt);
        if (! $dt) {
            $dt = today();
        }
    }
    else {
        $dt = today();
    }
    stash($c,
        deposits => [ 
            model($c, 'Deposit')->search(
                {
                    source   => $source,
                    date_end => { '<=', $dt->as_d8() },
                },
                {
                    rows => 10,
                    order_by => 'date_start desc'
                },
            )
        ],
        source   => $source,
        template => "finance/prior_deposits.tt2",
    );
}

sub period_end : Local {
    my ($self, $c, $source) = @_;

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
    #    credit => ,
    # }.
    # then sort by name for display.
    #
    my %totals = ();

    my $cond = {
        the_date => { between => [ $start_d8, $end_d8 ] },
    };

    # copied from above :( DRY??? YES revisit.
    my @sources = ($source eq 'mmc')? qw/
                      RegPayment
                      XAccountPayment
                      RentalPayment
                  /:
                  qw/
                      MMIPayment
                  /;
    # Donations are not included in deposits, no???
    #
    for my $src (@sources) {
        for my $p (model($c, $src)->search($cond)) {
            my $type = $p->type();
            my $amt  = $p->amount();
            my $glnum = $p->glnum();
            if (! exists $totals{$glnum}) {
                my ($name, $link);
                if ($src eq 'MMIPayment') {
                    ($name, $link) = mmi_glnum($c, $glnum);
                }
                else {
                    $name = $p->pname();
                    $link = $p->plink();
                }
                $totals{$p->glnum()} = {
                    name   => $name,
                    type  => ($src eq "RegPayment"     ? ' '
                             :$src eq "RentalPayment"  ? '*'
                             :$src eq "XAccountPayment"? 'x'
                             :$src eq "MMIPayment"     ? ' '
                             :                           ' '),
                    link  => $link,
                    glnum => $p->glnum(),
                };
            }
            my $href = $totals{$glnum};
            $href->{amount} += $amt;
            $href->{
                $type eq 'S'? 'cash'
               :$type eq 'C'? 'check'
               :              'credit'
            } += $amt;
        }
    }
    if ($source eq 'mmc') {
        # ride payments are handled differently
        # and it is always a credit card payment.
        #
        my $rgl = $string{ride_glnum};
        for my $r (model($c, 'Ride')->search({
                       paid_date => { between => [ $start_d8, $end_d8 ] },
                   })
        ) {
            if (! exists $totals{$rgl}) {
                $totals{$rgl} = {
                    name  => 'Rides',
                    type  => 'r',
                    link  => "/ride/list",
                    glnum => $rgl,
                };
            }
            my $href = $totals{$rgl};
            my $amt = $r->cost();
            $href->{amount} += $amt;
            $href->{credit} += $amt;
        }
    }
    my %grand_total;
    for my $t (keys %totals) {
        for my $n (qw/ amount cash check credit /) {
            $grand_total{$n} += $totals{$t}->{$n};
            $totals{$t}->{$n} = commify($totals{$t}->{$n});
        }
    }
    for my $n (keys %grand_total) {
        $grand_total{$n} = commify($grand_total{$n});
    }
    stash($c,
        which       => $source eq 'mmi'? "MMI": "",
        start       => $start,
        end         => $end,
        totals      => [ sort { $a->{name} cmp $b->{name} } values %totals ],
        grand_total => \%grand_total,
        template    => "finance/period_end.tt2",
    );
}

1;
