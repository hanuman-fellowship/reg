use strict;
use warnings;
package RetreatCenter::Controller::DailyPic;
use base 'Catalyst::Controller';

use GD;
use Date::Simple qw/
    date
    today
/;
use Lookup;
use Util qw/
    model
/;

sub index : Local {
    # ???
}

sub show : Local {
    my ($self, $c, $date) = @_;

    Lookup->init($c);
    my $today = today();
    my $last_date = date($lookup{sys_last_config_date});
    my ($dt, $clusters);
    if ($date) {
        $dt = date($date);
    }
    elsif (my $fdate = $c->request->params->{date}) {
        $dt = date($fdate);
        if ((! $dt)
            || ($dt < $today)
            || ($dt->as_d8() gt $last_date)
        ) {
            $c->stash->{mess} = "Illegal date: $fdate";
            $c->stash->{template} = "gen_error.tt2";
            return;
        }
    }
    else {
        $dt = $today;
    }

    my @clusters = ();

    my @where = ();
    if ($clusters = $c->request->params->{clusters}) {
        if (my @clust_params = split m{\s+}, $clusters) {
            my @cluster_ids = ();
            my @bad_names = ();
            for my $name (@clust_params) {
                if (my (@cl) = model($c, 'Cluster')->search({
                                   name => { -like => "%$name%" },
                               })
                ) {
                    push @clusters, @cl;
                    push @cluster_ids, map { $_->id } @cl;
                }
                else {
                    push @bad_names, $name;
                }
            }
            if (@bad_names) {
                $c->stash->{mess} = "Unknown clusters: @bad_names";
                $c->stash->{template} = "gen_error.tt2";
                return;
            }
            @where = (
                cluster_id => { -in => \@cluster_ids },
            );
        }
    }
    else {
        @clusters = model($c, 'Cluster')->all();
    }
    my $d8 = $dt->as_d8();

    my ($width, $height) = (0, 0);
    my @houses = model($c, 'House')->search({
        inactive => '',    
        @where,
    });
    for my $h (@houses) {
        my $wd = $h->x + $h->max * $lookup{house_width};
        my $code = $h->disp_code;
        if (substr($code, 0, 1) eq 'R') {
            my $name = $h->name;
            if ($code =~ m{t}) {
                $name =~ s{^\S*\s*}{};
            }
            $wd += length($name)*$lookup{house_let};
        }
        my $ht = $h->y + $lookup{house_height};
        if (substr($code, 0, 1) eq 'B') {
            $ht += $lookup{house_height};
        }
        if ($wd > $width) {
            $width = $wd;
        }
        if ($ht > $height) {
            $height = $ht;
        }
    }
    # margin???
    $width += $lookup{house_height};
    $height += $lookup{house_height};

    # I can't imagine cluster labels extending beyond
    # the houses in the cluster.  right?

    my $dp = GD::Image->new($width+1, $height+1);
    my $white = $dp->colorAllocate(255,255,255);    # 1st color = background
    my $black = $dp->colorAllocate(0, 0, 0);
    $dp->rectangle(0, 0, $width, $height, $black);

    # cluster labels
    for my $cl (@clusters) {
        my $x = $cl->x;
        my $y = $cl->y;
        if ($x && $y) {
            $dp->string(gdGiantFont, $x, $y, $cl->name, $black);
        }
    }

    my $dp_map = "";    
    my %clust_color;
    for my $cl (@clusters) {
        $clust_color{$cl->id} = $dp->colorAllocate($cl->color =~ m{\d+}g);
    }
    for my $h (@houses) {
        my $x1 = $h->x;
        my $y1 = $h->y;
        my $hid = $h->id;
        my $name = $h->name;
        my $tname = $name;
        my $disp_code = $h->disp_code;
        if (substr($disp_code, 1, 1) eq 't') {
            $tname =~ s{^\S+\s*}{};        
        }
        $disp_code = substr($disp_code, 0, 1);
        my $x2 = $x1 + $h->max * $lookup{house_width} + 3;
        my $y2 = $y1 + $lookup{house_height};
        $dp->rectangle($x1, $y1, $x2, $y2, $black);
        $dp->filledRectangle($x1+1, $y1+1, $x2-1, $y2-1,
                             $clust_color{$h->cluster_id});
        # below we have a cool use of the ?: operator!  (what is its name?)
        $dp->string(gdGiantFont,
            ($disp_code eq 'L')? ($x1-length($tname)*$lookup{house_let}-2,$y1+3)
           :($disp_code eq 'R')? ($x2+3, $y1+3)
           :($disp_code eq 'A')? ($x1, $y1-$lookup{house_height}+3)
           :($disp_code eq 'B')? ($x1, $y1+$lookup{house_height}+3)
           :                     (0, 0),    # shouldn't happen
                    $tname, $black);
        # check the config table for this house, this date
        # we _will_ find a record.  right?
        my ($cf) = model($c, 'Config')->search({
            house_id => $hid,
            the_date => $d8,
        });
        # encode the config record in a string
        my $code = ($cf->sex x $cf->cur)
                 . ('.' x ($cf->curmax - $cf->cur))
                 . ('|' x ($h->max - $cf->curmax))
                 ;
        $dp->string(gdGiantFont,
                    $x1+3, $y1+3,
                    $code, $black);
        if ($cf->cur == 0) {
            next;       # assume that the config and the
                    # Registrations/RentalBookings are in synch.
                    # if not, we're screwed.
                    # this is why I made hcck!
        }
        # prepare the overlib popups
        #
        # registrations?
        # the end date is strictly less because
        # we reserve housing up to the night before their end date.
        #
        # so:
        #      date_start <= $d8 < date_end
        #
        my @regs = model($c, 'Registration')->search({
            house_id => $hid,
            date_start => { '<=', $d8 },
            date_end   => { '>',  $d8 },
        });
        my $reg_names = "";
        for my $r (@regs) {
            $reg_names .= "<tr>"
                       . "<td>"
                       . "<a target=happening class=pr_links href="
                       . $c->uri_for("/registration/view/" . $r->id)
                       . ">"
                       . $r->person->last . ", " . $r->person->first
                       . "</a>"
                       . "<td>" . $r->program->name . "</td>"
                       . "</td>"
                       . "</tr>";
        }
        $reg_names =~ s{'}{\\'}g;       # for O'Dwyer etc.
                                    # can't use &apos; :( why?
        if ($reg_names) {
            $dp_map .= "<area shape=rect coords='$x1, $y1, $x2, $y2'"
. qq! onclick="return overlib('<center>$name</center><p><table cellpadding=2>$reg_names</table>',!
. qq! STICKY, MOUSEOFF, TEXTFONT, 'Verdana', TEXTSIZE, 5, WRAP,!
. qq! CELLPAD, 7, FGCOLOR, '#FFFFFF', BORDER, 2)"!
. qq! onmouseout="return nd();">\n!;
        }
        else {
            # no registrations - it may/must have been booked
            # for a rental.
            my @rentbook = model($c, 'RentalBooking')->search({
                house_id => $hid,
                date_start => { '<=', $d8 },
                date_end   => { '>=', $d8 },
            });
            for my $rb (@rentbook) {      # max of one...
                $dp_map .= "<area shape=rect coords='$x1, $y1, $x2, $y2'"
. qq! onclick="return overlib('<center>$name</center><p><table cellpadding=2>!
. "<tr><td><a target=happening class=pr_links href="
. $c->uri_for("/rental/view/" . $rb->rental_id . "/3")
. ">"
. $rb->rental->name . " - " . $rb->h_type
. "</a></td></tr>"
. qq! </table>',!
. qq! STICKY, MOUSEOFF, TEXTFONT, 'Verdana', TEXTSIZE, 5, WRAP,!
. qq! CELLPAD, 7, FGCOLOR, '#FFFFFF', BORDER, 2)"!
. qq! onmouseout="return nd();">\n!;
            }
        }
    }
    # write the image to be used shortly
    open my $imf, ">", "root/static/images/dailypic.png"
        or die "no dailypic.png: $!\n"; 
    print {$imf} $dp->png;
    close $imf;
    my $image = $c->uri_for("/static/images/dailypic.png");
    my $back = $dt - 1;
    if ($back < $today) {
        $back = $today;
    }
    my $next = $dt + 1;
    if ($next > $last_date) {
        $next = $last_date;
    }
    $back = $back->as_d8();
    $next = $next->as_d8();
    my $dt_fmt = $dt->format("%A %B %e, %Y");
    #
    # find everything that is happening on this day
    #
    my $event_table = "";
    my @events = ();
    for my $type (qw/Event Rental Program/) {
        for my $ev (model($c, $type)->search({
                        sdate => { '<=', $d8 },
                        edate => { '>=', $d8 },
                    })
        ) {
            my $ev_type = ref($ev);
            $ev_type =~ s{.*::}{};
            $ev_type = lc $ev_type;
            push @events, {
                sdate => date($ev->sdate, "%m/%d"),
                edate => date($ev->edate, "%m/%d"),
                name  => $ev->name,
                type  => $ev_type,
                id    => $ev->id,
            };
        }
    }
    for my $ev (sort { $a->{sdate} <=> $b->{sdate} } @events) {
        $event_table .=
            "<tr><td>$ev->{sdate}</td><td>$ev->{edate}</td>"
          . "<td><a target=happening href=/$ev->{type}/view/$ev->{id}>$ev->{name}</td>"
          . "</tr>\n";
    }
    if ($event_table) {
        $event_table = <<EOT;
<p>
<table cellpadding=3>
<tr><th>Start</th><th>End</td><th align=left>Name</th></tr>
$event_table
</table>
EOT
    }
    my $html = <<EOH;
<head>
<link rel="stylesheet" type="text/css" href="/static/cal.css" />
<script type="text/javascript" src="/static/js/overlib.js"><!-- overLIB (c) Erik Bosrup --></script>
</head>
<body>
<span class=hdr>$dt_fmt</span>
<p>
<form method=POST action="/dailypic/show">
<a class=details href="/dailypic/show/$back?clusters=$clusters">Back</a>
<a class=details href="/dailypic/show/$next?clusters=$clusters">Next</a>
<span class=details> Date <input type=text name=date size=10 value='$dt'></span>
<span class=details>Clusters <input type=text name=clusters size=15 value='$clusters'></span>
<input class=go type=submit value="Go">
</form>
<p>
<img style="margin-left: .5in;" src=$image usemap=#dailypic>
$event_table
<map name=dailypic>
$dp_map
</map>
</body>
EOH
    $c->res->output($html);
}

1;
