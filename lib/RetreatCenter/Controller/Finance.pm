use strict;
use warnings;
package RetreatCenter::Controller::Finance;
use base 'Catalyst::Controller';

use Util qw/
    model
    commify
    stash
    tt_today
/;
use Date::Simple qw/
    date
/;
use Global qw/
    %string
/;

sub index : Local {
    my ($self, $c) = @_;

    $c->stash->{template} = "finance/index.tt2";
}

sub reconcile_deposit : Local {
    my ($self, $c, $id) = @_;

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
    for my $src (qw/ Reg XAccount Rental /) {
        for my $p (model($c, "${src}Payment")->search($cond)) {
            my $type = $p->type;
            my $amt  = $p->amount;
            if ($type eq 'Cash') {
                $cash += $amt;
            }
            elsif ($type eq 'Check') {
                $check += $amt;
            }
            elsif ($type eq 'Credit Card') {
                $credit += $amt;
            }
            elsif ($type eq 'Online') {
                $online += $amt;
            }
            $total += $amt;
            push @payments, {
                name   => $p->name,
                link   => $p->link,
                date   => $p->the_date_obj->format("%D"),
                cash   => ($type eq 'Cash'  )? $amt: "",
                chk    => ($type eq 'Check' )? $amt: "",
                credit => ($type eq 'Credit Card')? $amt: "",
                online => ($type eq 'Online')? $amt: "",
                pname  => $p->pname,
            };
        }
    }
    @payments = sort {
                        $a->{name} cmp $b->{name}
                    }
                    @payments;

    $string{reconciling} = $c->user->obj->username();
        # on disk??  not needed?

    stash($c,
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
# the id  is passed in if we are viewing a past deposit.
# Without it we are creating a new one.
#
sub file_deposit : Local {
    my ($self, $c, $id) = @_;

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
    for my $src (qw/ Reg XAccount Rental /) {
        for my $p (model($c, "${src}Payment")->search($cond)) {
            my $type = $p->type();
            my $amt  = $p->amount();
            push @payments, {
                name   => $p->name(),
                date   => $p->the_date_obj->format("%D"),
                type   => $type,
                amt    => $amt,
                glnum  => $p->glnum(),
                pname  => $p->pname(),
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
    my $time;
    if ($id) {
        $timestamp = date($date_end)->format("%D") . " " . $dep->time();
    }
    else {
        $time = sprintf("%02d:%02d", (localtime())[2, 1]),
        $timestamp = tt_today($c) . " " . $time;
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
    my ($cash, $check, $credit) = (0, 0, 0);
    my ($gcash, $gcheck, $gcredit, $gtotal) = (0, 0, 0, 0);
    for my $p (@payments) {
        if ($p->{glnum} ne $prev_glnum) {
            if ($prev_glnum) {
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
        my $type = $p->{type};
        my $n = ($type eq "Cash" )? 1
               :($type eq "Check")? 2
               :                    3       # Credit - includes Online
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
    if (! $id && $gtotal != 0) {
        #
        # create a new deposit and update the last_deposit_date
        #
        model($c, 'Deposit')->create({
            user_id    => $c->user->obj->id(),
            time       => $time,
            date_start => $date_start,
            date_end   => $date_end,
            cash       => $gcash,
            chk        => $gcheck,
            credit     => $gcredit,
            total      => $gtotal,
        });
        $string{last_deposit_date} = $date_end;                   # in memory
        model($c, 'String')->find('last_deposit_date')->update({  # on disk
            value => $date_end,
        });
        $string{reconciling} = 0;   # only in memory???
    }
    $c->res->output($html);
}

sub deposits : Local {
    my ($self, $c) = @_;

    stash($c,
        deposits => [ 
            model($c, 'Deposit')->search(
                { },
                { order_by => 'date_start desc' },
            )
        ],
        template => "finance/prior_deposits.tt2",
    );
}

1;
