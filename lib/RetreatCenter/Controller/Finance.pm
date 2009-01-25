use strict;
use warnings;
package RetreatCenter::Controller::Finance;
use base 'Catalyst::Controller';

use Util qw/
    model
    commify
/;
use Date::Simple qw/date/;

sub index : Local {
    my ($self, $c) = @_;

    $c->stash->{template} = "finance/index.tt2";
}

sub reconcile_deposit : Local {
    my ($self, $c) = @_;

    # ??? replace by actual last deposit date/time
    my $last_date = "20090123";
    my $last_time = "00:00";

    my $cond = {
        -or => [
            the_date => { '>', $last_date },
            -and => [
                the_date => $last_date,
                time     => { '>=', $last_time },
            ],
        ],
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
    $c->stash->{payments} = \@payments;
    $c->stash->{cash}     = $cash;
    $c->stash->{check}    = $check;
    $c->stash->{credit}   = $credit;
    $c->stash->{online}   = $online;
    $c->stash->{total}    = $total;
    $c->stash->{template} = "finance/deposit.tt2";
}

sub file_deposit : Local {
    my ($self, $c) = @_;

    # ??? replace by actual last deposit date/time
    my $last_date = "20090123";
    my $last_time = "00:00";

    my $cond = {
        -or => [
            the_date => { '>', $last_date },
            -and => [
                the_date => $last_date,
                time     => { '>=', $last_time },
            ],
        ],
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

    my $time = localtime();
    my $html = <<"EOH";
$time<span style="font-size: 25pt; font-weight: bold; margin-left: 1.5in;">Bank Deposit</span>
<p>
<table cellpadding=3>
<tr>
<th align=left>Account (GL number)<br>${indent}Name</th>
<th align=center>Date</th>
<th align=right width=70>Cash</th>
<th align=right width=70>Check</th>
<th align=right width=70>Credit</th>
<th align=right width=70>Total</th>
</tr>
<tr><td colspan=6><hr size=2 color=black></td></tr>
EOH
    my $prev_glnum = "";
    my ($cash, $check, $credit) = (0, 0, 0);
    my ($gcash, $gcheck, $gcredit, $gtotal) = (0, 0, 0, 0);
    for my $p (@payments) {
        if ($p->{glnum} ne $prev_glnum) {
            if ($prev_glnum) {
                my $total = $cash+$check+$credit;
                $html .= "<tr><td colspan=2></td><td colspan=3><hr size=2 color=black></td></tr>\n";
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
                  .  "<td colspan=6 align=left>$p->{pname} ($p->{glnum})</td>"
                  .  "</tr>\n"
                  ;
        }
        $prev_glnum = $p->{glnum};
        my $type = $p->{type};
        my $n = ($type eq "Cash" )? 1
               :($type eq "Check")? 2
               :                    3       # includes Online
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
    $html .= "<tr><td colspan=2></td><td colspan=3><hr size=2 color=black></td></tr>\n";
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
    $html .= "<tr><td colspan=2></td><td colspan=4><hr size=4 color=black></td></tr>\n";
    $html .= "<tr>"
          .  "<td colspan=3 align=right>$gcash</td>"
          .  "<td align=right>$gcheck</td>"
          .  "<td align=right>$gcredit</td>"
          .  "<td align=right>"
          .  commify($gtotal)
          .  "</td>"
          .  "</tr>\n"
          ;
    $html .= <<"EOH";
</table>
EOH
    $c->res->output($html);
}

sub deposits : Local {
    my ($self, $c) = @_;

    $c->stash->{deposits} = 0;  # ???
    $c->stash->{template} = "finance/prior_deposits.tt2";
}

1;
