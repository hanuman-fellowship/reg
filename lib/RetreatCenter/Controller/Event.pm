use strict;
use warnings;
package RetreatCenter::Controller::Event;
use base 'Catalyst::Controller';

use Date::Simple qw/date today/;
use Util qw/
    empty
    model
    meetingplace_table
/;
use GD;
use ActiveCal;
use DateRange;      # imports overlap

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

    my $e = model($c, 'Event')->find($id);
    if ($e->sdate ne $hash{sdate} || $e->edate ne $hash{edate}) {
        # invalidate the bookings as the dates have changed
        model($c, 'Booking')->search({
            event_id => $id,
        })->delete();
    }
    $e->update(\%hash);
    $c->response->redirect($c->uri_for("/event/view/" . $e->id));
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

    my ($no_where) = model($c, 'MeetingPlace')->search({
        name => 'No Where',
    });
    my $today = today();
    my $year = $today->year;
    my $month = $today->month;
    my $sdate = sprintf("%4d%02d%02d", $year, $month, 1);
    my @events;
    for my $ev_kind (qw/Event Program Rental/) {
        push @events, model($c, $ev_kind)->search({
                          edate => { '>=', $sdate },
                      });
    }
    my $maxdate = $sdate;
    for my $e (@events) {
        if ($e->edate > $maxdate) {
            $maxdate = $e->edate;
        }
    }
    $maxdate = date($maxdate);
    my $end_year  = $maxdate->year;
    my $end_month = $maxdate->month;

    my %cals;       # a hash of ActiveCal objects indexed by yearmonth
    my %imgmaps;    # the image maps for each calendar image
    #
    # initialize the cals and imgmaps
    #
    while ($year < $end_year || ($year == $end_year && $month <= $end_month)) {
        my $key = sprintf("%04d%02d", $year, $month);
        $cals{$key} = ActiveCal->new($year, $month);
        $imgmaps{$key} = "";
        ++$month;
        if ($month > 12) {
            $month = 1;
            ++$year;
        }

    }
    #
    # sort the events by start date so that
    # a later event will overwrite one to its left
    #
    my $day_width = ActiveCal->day_width;
    for my $ev (sort { $a->sdate <=> $b->sdate } @events) {
        # draw on the right image(s)
        #
        my $ev_sdate = $ev->sdate_obj;
        my $ev_edate = $ev->edate_obj;

        for my $key (ActiveCal->keys($ev_sdate, $ev_edate)) {
            my $cal = $cals{$key};
            if (! $cal) {
                # this event apparently begins in a prior month
                # and overlaps into the first shown month???
                # like today is April 10th and the event is from
                # March 29th to April 4th.
                $cal = $cals{$today->format("%Y%m")};
            }
            my $dr = overlap($ev->date_range, $cal);
            my $d1 = $dr->sdate->day;
            my $d2 = $dr->edate->day;
            my @places = map { $_->meeting_place } $ev->bookings;
            #
            # if no meeting place assigned hopefully put it SOMEwhere.
            # to alert the user that it is dangling homeless.
            #
            if (! @places && $no_where) {
                push @places, $no_where;
            }
            my $im = $cal->image;
            for my $pl (@places) {
                my ($r, $g, $b) = $pl->color =~ m{(\d+)}g;
                my $color = $im->colorAllocate($r, $g, $b);
                my $black = $im->colorAllocate(0, 0, 0);
                    # ??? do the above once for all meeting places
                    # then index into a hash for the color.
                my $x1 = ($d1-1) * $day_width;
                # if overlapping from prior month don't indent it
                if ($d1 == $ev_sdate->day) {
                    $x1 += $day_width/2;
                }
                my $x2 = $d2 * $day_width;
                # if overflowing to the next month don't exdent it
                if ($d2 == $ev_edate->day) {
                    $x2 -= $day_width/2;
                }
                my $y1 = $pl->disp_ord * 40;
                my $y2 = $y1 + 20;
                my $place_name = $pl->abbr;
                if ($place_name eq '-') {
                    $place_name = "";
                }
                else {
                    $place_name = " ($place_name)";
                }
                my $event_name = $ev->name;
                my $width = length($event_name . $place_name) * 20;

                $im->rectangle($x1, $y1, $x2, $y2, $black);
                $im->filledRectangle($x1+1, $y1+1, $x2-1, $y2-1, $color);

                # print the event and place names in the rectangle, if you can
                $im->string(gdLargeFont, $x1 + 2, $y1 + 2,
                            $event_name . $place_name, $black);

                # add to the image map
                $imgmaps{$key} .= "<area shape='rect' coords='$x1,$y1,$x2,$y2'\n"
                               .  "    target=_blank\n"
                               .  "    href='" . $ev->link . "'\n"
    . qq!    onmouseover="return overlib('!
    . $event_name . $place_name
    . qq!', FGCOLOR, '#FFFFFF', BGCOLOR, '#333333', BORDER, 2,!
    . qq! TEXTFONT, 'Verdana', TEXTSIZE, 5, WIDTH, $width)"\n !
    . qq!    onmouseout="return nd();">\n!;
            }       # places the event meets in 
        }       # keys of the calendar month images/maps the event spans
    }       # events
    #
    # generate the HTML output
    #
    my $content = <<EOH;
<script type="text/javascript" src="/static/js/overlib.js"><!-- overLIB (c) Erik Bosrup --></script>
<div style='margin-left: .5in'>
EOH
    for my $ym (sort keys %cals) {
        my $ac = $cals{$ym};
        $content .= "\n<h2>" . $ac->sdate->format("%B %Y") . "</h2>\n";

        my $image = $c->uri_for("/static/images/$ym.png");
        $content .= <<EOH;
<img src='$image' usemap='#$ym'>
<map name=$ym>
$imgmaps{$ym}</map>
EOH
  
        open my $imf, ">", "root/static/images/$ym.png"; 
        print {$imf} $ac->image->png;
        close $imf;
    }
    $content .= "</div>\n";
    $c->res->output($content);
    $c->stash->{template} = "event/calendar.tt2";
}

sub meetingplace_update : Local {
    my ($self, $c, $id) = @_;

    my $e = $c->stash->{event} = model($c, 'Event')->find($id);
    $c->stash->{meetingplace_table}
        = meetingplace_table($c, $e->sdate, $e->edate, $e->bookings());
    $c->stash->{template} = "event/meetingplace_update.tt2";
}

sub meetingplace_update_do : Local {
    my ($self, $c, $id) = @_;

    my $e = model($c, 'Event')->find($id);
    my @cur_mps = grep {  s{^mp(\d+)}{$1}  }
                     keys %{$c->request->params};
    # delete all old bookings and create the new ones.
    model($c, 'Booking')->search(
        { event_id => $id },
    )->delete();
    for my $mp (@cur_mps) {
        model($c, 'Booking')->create({
            meet_id    => $mp,
            program_id => 0,
            rental_id  => 0,
            event_id   => $id,
            sdate      => $e->sdate,
            edate      => $e->edate,
        });
    }
    # show the event again - with the updated meeting places
    view($self, $c, $id);
    $c->forward('view');
}

1;
