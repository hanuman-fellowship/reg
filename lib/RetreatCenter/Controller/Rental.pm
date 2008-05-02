use strict;
use warnings;
package RetreatCenter::Controller::Rental;
use base 'Catalyst::Controller';

use Date::Simple qw/date today/;
use Util qw/
    trim
    empty
    compute_glnum
    valid_email
    model
    meetingplace_table
/;

use lib '../../';       # so you can do a perl -c here.

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('list');
}

sub create : Local {
    my ($self, $c) = @_;

    $c->stash->{check_webready} = "checked";
    $c->stash->{check_linked}   = "checked";
    $c->stash->{housecost_opts} =
        [ model($c, 'HouseCost')->search(
            undef,
            { order_by => 'name' },
        ) ];
    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "rental/create_edit.tt2";
}

my %hash;
my @mess;
sub _get_data {
    my ($c) = @_;

    %hash = %{ $c->request->params() };
    @mess = ();
    $hash{url} =~ s{^\s*http://}{};
    $hash{email} = trim($hash{email});
    if (empty($hash{name})) {
        push @mess, "Name cannot be blank";
    }
    if (empty($hash{title})) {
        push @mess, "Title cannot be blank";
    }
    # dates are either blank or converted to d8 format
    for my $d (qw/ sdate edate /) {
        my $fld = $hash{$d};
        if (! $fld =~ /\S/) {
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
    if (!@mess && $hash{sdate} > $hash{edate}) {
        push @mess, "End date must be after the Start date";
    }
    my $ndays = 0;
    if (!@mess) {
        $ndays = date($hash{edate}) - date($hash{sdate});
    }
    my $hc = model($c, 'HouseCost')->find($hash{housecost_id});
    my $total = 0;
    for my $f (qw/
        n_single_bath
        n_single
        n_double_bath
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
        if (! ($hash{$f} =~ m{^\s*\d*\d*$})) {
            $s =~ s{_}{ };
            $s =~ s{\b(\w)}{\u$1}g;
            $s =~ s{Dble}{Double};
            push @mess, "Illegal quantity for $s: $hash{$f}";
        }
        else {
            if ($hc->type eq 'Perday') {
                $total += $hc->$s * $hash{$f} * $ndays;
            }
            else {
                # Total
                $total += $hc->$s * $hash{$f};
            }
        }
    }
    $hash{total_charge} = $total;

    if ($hash{email} && ! valid_email($hash{email})) {
        push @mess, "Invalid email: $hash{email}";
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "rental/error.tt2";
    }
}

sub create_do : Local {
    my ($self, $c) = @_;

    _get_data($c);
    return if @mess;

    $hash{glnum} = compute_glnum($c, $hash{sdate});
    my $p = model($c, 'Rental')->create(\%hash);
    my $id = $p->id();
    $c->response->redirect($c->uri_for("/rental/view/$id"));
}

sub view : Local {
    my ($self, $c, $id) = @_;

    my $r = model($c, 'Rental')->find($id);
    $c->stash->{rental} = $r;

    my @payments = $r->payments;
    my $tot = 0;
    for my $p (@payments) {
        $tot += $p->amount;
    }
    $c->stash->{tot_payment}  = $tot;
    $c->stash->{balance}  = $r->total_charge - $tot;
    $c->stash->{payments} = \@payments;
    $c->stash->{template} = "rental/view.tt2";
}

sub list : Local {
    my ($self, $c) = @_;

    my $today = today()->as_d8();
    $c->stash->{rentals} = [
        model($c, 'Rental')->search(
            { sdate => { '>=', $today } },
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
    my ($self, $c, $id) = @_;

    my $p = model($c, 'Rental')->find($id);
    $c->stash->{rental} = $p;
    $c->stash->{"check_linked"}    = ($p->linked()   )? "checked": "";
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
    $c->stash->{template}    = "rental/create_edit.tt2";
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    _get_data($c);
    return if @mess;

    my $p = model($c, 'Rental')->find($id);
    if ($p->sdate ne $hash{sdate} || $p->edate ne $hash{edate}) {
        # we have changed the dates of the rental
        # and need to invalidate/remove any bookings for meeting spaces.
        model($c, 'Booking')->search({
            rental_id => $id,
        })->delete();
    }
    $p->update(\%hash);
    $c->response->redirect($c->uri_for("/rental/view/" . $p->id));
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    model($c, 'Rental')->search(
        { id => $id }
    )->delete();
    $c->response->redirect($c->uri_for('/rental/list'));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

sub pay_balance : Local {
    my ($self, $c, $id, $amt) = @_;

    my $r = model($c, 'Rental')->find($id);
    $c->stash->{rental} = $r;
    $c->stash->{amount} = $amt;
    $c->stash->{template} = "rental/pay_balance.tt2";
}

sub pay_balance_do : Local {
    my ($self, $c, $id) = @_;

    my $amt = $c->request->params->{amount};
    my $type = $c->request->params->{type};

    # can't do $c->user->id for some unknown reason??? so...
    my $username = $c->user->username();
    my ($u) = model($c, 'User')->search({
        username => $username,
    });
    my $user_id = $u->id;

    my $today = today();
    my $now_date = $today->as_d8();
    my ($hour, $min) = (localtime())[2, 1];
    my $now_time = sprintf "%02d:%02d", $hour, $min;

    model($c, 'RentalPayment')->create({

        rental_id => $id,
        amount    => $amt,
        type      => $type,

        user_id  => $user_id,
        the_date => $now_date,
        time     => $now_time,
    });
    $c->response->redirect($c->uri_for("/rental/view/$id"));
}

sub meetingplace_update : Local {
    my ($self, $c, $id) = @_;

    my $r = $c->stash->{rental} = model($c, 'Rental')->find($id);
    $c->stash->{meetingplace_table}
        = meetingplace_table($c, $r->sdate, $r->edate, $r->bookings());
    $c->stash->{template} = "rental/meetingplace_update.tt2";
}

sub meetingplace_update_do : Local {
    my ($self, $c, $id) = @_;

    my $r = model($c, 'Rental')->find($id);
    my @cur_mps = grep {  s{^mp(\d+)}{$1}  }
                     keys %{$c->request->params};
    # delete all old bookings and create the new ones.
    model($c, 'Booking')->search(
        { rental_id => $id },
    )->delete();
    for my $mp (@cur_mps) {
        model($c, 'Booking')->create({
            meet_id    => $mp,
            program_id => 0,
            rental_id  => $id,
            event_id   => 0,
            sdate      => $r->sdate,
            edate      => $r->edate,
        });
    }
    # show the rental again - with the updated meeting places
    view($self, $c, $id);
    $c->forward('view');
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
        $c->response->redirect($c->uri_for("/rental/view/$id"));
    }
    else {
        $c->stash->{template} = "rental/no_coord.tt2";
    }
}

1;
