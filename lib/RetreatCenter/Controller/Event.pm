use strict;
use warnings;
package RetreatCenter::Controller::Event;
use base 'Catalyst::Controller';

use Date::Simple qw/date today/;
use Util qw/
    empty
    model
/;

use lib '../../';       # so you can do a perl -c here.

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('list');
}

sub create : Local {
    my ($self, $c) = @_;

    $c->stash->{sponsor_opts} = <<EOH;
<option value="Center">Center
<option value="School">School
<option value="Institute">Institute
<option value="Other">Other
EOH
    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "event/create_edit.tt2";
}

my %hash;
my @mess;
sub _get_data {
    my ($c) = @_;

    %hash = %{ $c->request->params() };
    @mess = ();
    if (empty($hash{name})) {
        push @mess, "Name cannot be blank";
    }
    if (empty($hash{descr})) {
        push @mess, "Description cannot be blank";
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
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "event/error.tt2";
    }
}

sub create_do : Local {
    my ($self, $c) = @_;

    _get_data($c);
    return if @mess;

    my $p = model($c, 'Event')->create(\%hash);
    my $id = $p->id();
    $c->response->redirect($c->uri_for("/event/view/$id"));
}

sub view : Local {
    my ($self, $c, $id) = @_;

    $c->stash->{event} = model($c, 'Event')->find($id);
    $c->stash->{template} = "event/view.tt2";
}

sub list : Local {
    my ($self, $c) = @_;

    my $today = today()->as_d8();
    $c->stash->{events} = [
        model($c, 'Event')->search(
            { sdate => { '>=', $today } },
            { order_by => 'sdate' },
        )
    ];
    $c->stash->{event_pat} = "";
    $c->stash->{template} = "event/list.tt2";
}

sub listpat : Local {
    my ($self, $c) = @_;

    my $event_pat = $c->request->params->{event_pat};
    if (empty($event_pat)) {
        $c->forward('list');
        return;
    }
    my $cond;
    if ($event_pat =~ m{(^[fs])(\d\d)}i) {
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
    elsif ($event_pat =~ m{((\d\d)?\d\d)}) {
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
        my $pat = $event_pat;
        $pat =~ s{\*}{%}g;
        $cond = {
            name => { 'like' => "${pat}%" },
        };
    }
    $c->stash->{events} = [
        model($c, 'Event')->search(
            $cond,
            { order_by => 'sdate desc' },
        )
    ];
    $c->stash->{event_pat} = $event_pat;
    $c->stash->{template} = "event/list.tt2";
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $p = model($c, 'Event')->find($id);
    $c->stash->{event} = $p;
    my $sponsor_opts = "";
    for my $s (qw/Center School Institute Other/) {
        $sponsor_opts .= "<option value='$s'"
                       . (($s eq $p->sponsor)? " selected": "")
                       . ">$s\n";
    }
    $c->stash->{sponsor_opts} = $sponsor_opts;
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "event/create_edit.tt2";
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    _get_data($c);
    return if @mess;

    my $p = model($c, 'Event')->find($id);
    $p->update(\%hash);
    $c->response->redirect($c->uri_for("/event/view/" . $p->id));
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    model($c, 'Event')->search(
        { id => $id }
    )->delete();
    $c->response->redirect($c->uri_for('/event/list'));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

sub calendar : Local {
    my ($self, $c) = @_;

    my $sdate = $c->request->params->{sdate};
    my $edate = $c->request->params->{edate};
    if (! defined $sdate || empty($sdate)) {
        # the default: the current month
        # or should it be from today + 30 days???
        my $today = today();
        my $year = $today->year;
        my $month = $today->month;
        $sdate = date($year, $month, 1);
        $edate = date($year, $month, $sdate->days_in_month);
        # is there a better way to do the above???
    }
    else {
        $sdate = date($sdate);
        $edate = date($edate);
        # errors???
    }
    my $sdate8 = $sdate->as_d8();
    my $edate8 = $edate->as_d8();
    my $cond = {
       -or => [
           sdate => { 'between' => [ $sdate8, $edate8 ] },
           -and => [
               sdate => { '<=', $sdate8 },
               edate => { '>=', $sdate8 },
           ],
       ],
    };
    my @programs = model($c, 'Program')->search($cond);
    my @rentals  = model($c, 'Rental' )->search($cond);
    my @events   = model($c, 'Event'  )->search($cond);
    my $content = "";
    my $d = $sdate;
    my $prev_month = 0;
    while ($d <= $edate) {
        if ($d->month != $prev_month) {
            $content .= "<h2>" . $d->format("%B %e") . "</h2>";
            $prev_month = $d->month;
        }
        else {
            $content .= "<h2>" . $d->format("%e") . "</h2>";
        }
        $content .= "<ul>\n";
        for my $th (@programs, @rentals, @events) {     # thingy
            if ($th->sdate <= $d && $d <= $th->edate) {
                my $s = lc(ref($th));
                $s =~ s{.*::}{};
                $content .= "<a href='/$s/view/"
                          . $th->id
                          . "'>"
                          . $th->name
                          . "</a><br>\n";
            }
        }
        $content .= "</ul>\n";
        ++$d;
    }
    $c->stash->{content} = $content;
    $c->stash->{template} = "event/calendar.tt2";
}

1;
