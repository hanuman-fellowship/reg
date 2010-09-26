use strict;
use warnings;
package RetreatCenter::Controller::Cluster;
use base 'Catalyst::Controller';

use lib '../..';
use Util qw/
    empty
    model
    trim
    tt_today
    reserved_clusters
/;
use Date::Simple qw/
    date
/;
use Global qw/
    %string
    %cluster
    %houses_in_cluster
    @clusters
/;
use GD;

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c) = @_;

    $c->stash->{clusters} = [ model($c, 'Cluster')->search(
        undef,
        { order_by => 'name' }
    ) ];
    $c->stash->{template} = "cluster/list.tt2";
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    # cascade???
    model($c, 'Cluster')->find($id)->delete();
    $c->response->redirect($c->uri_for('/cluster/list'));
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $cl = $c->stash->{cluster} = model($c, 'Cluster')->find($id);
    my $opts = "";
    for my $t (1 .. 5) {
        my $s = $string{"dp_type$t"};
        next if $s eq 'future use';
        $opts .= "<option value='$s'"
              .  (($cl->type() eq $s)? " selected": "")
              .  ">\u$s\n"
              ;
    }
    $c->stash->{type_opts} = $opts;
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "cluster/create_edit.tt2";
}

#
# currently there's no way to know which fields changed
# so assume they all did.
#
# check for dups???
#
sub update_do : Local {
    my ($self, $c, $id) = @_;

    my $name  = $c->request->params->{name};
    my $type  = $c->request->params->{type};
    my $cl_order  = $c->request->params->{cl_order};
    if (empty($name)) {
        $c->stash->{mess} = "Name cannot be blank.";
        $c->stash->{template} = "cluster/error.tt2";
        return;
    }
    model($c, 'Cluster')->find($id)->update({
        name  => $name,
        type  => $type,
        cl_order => $cl_order,
    });
    $c->response->redirect($c->uri_for('/cluster/list'));
}

sub create : Local {
    my ($self, $c) = @_;

# obsoleted???
    $c->stash->{red  } = 127;
    $c->stash->{green} = 127;
    $c->stash->{blue } = 127;

    $c->stash->{type_opts} = <<"EOO";
<option value="indoors">Indoors
<option value="outdoors">Outdoors
<option value="special">Special
<option value="resident">Resident
EOO
    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "cluster/create_edit.tt2";
}

#
# check for dups???
#
sub create_do : Local {
    my ($self, $c) = @_;

    my $name  = $c->request->params->{name};
    my $type  = $c->request->params->{type};
    my $cl_order = $c->request->params->{cl_order};
    if (empty($name)) {
        $c->stash->{mess} = "Name cannot be blank.";
        $c->stash->{template} = "cluster/error.tt2";
        return;
    }
    model($c, 'Cluster')->create({
        name  => $name,
        type  => $type,
        cl_order => $cl_order,
    });
    # no need to reload Configuration - creating clusters
    # is quite rare and houses would be added soon afterwards
    # which would do a reload.
    #
    $c->response->redirect($c->uri_for('/cluster/list'));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

#
# need to plan this better rather than just hacking it.
# how about space between houses, top margin, bottom margin
# being all separate values.
#
sub show : Local {
    my ($self, $c, $date, $cur_clust, $ndays) = @_;

    clear_cache();
    Global->init($c);
    my $today = tt_today($c);
    my $last_date = date($string{sys_last_config_date});
    my $dt;
    if ($date) {
        $dt = date($date);
    }
    elsif (my $fdate = $c->request->params->{date}) {
        $dt = date($fdate);
        if ((! $dt)
#            || ($dt < $today)      # how far backwards in time can we go???
            || ($dt->as_d8() > $last_date)
        ) {
            # ??? better error message
            # in case it is beyond the last date?
            $c->stash->{mess} = "Illegal date: $fdate";
            $c->stash->{template} = "gen_error.tt2";
            return;
        }
    }
    else {
        $dt = $today;
    }
    $dt->set_format("%D");      # ensure it is mm/dd/yy for input purposes
    my $d8 = $dt->as_d8();

    # how many days?   messy.
    my $param_ndays = $c->request->params->{ndays};
    if ($param_ndays) {
        $ndays = $param_ndays;
    }
    elsif (! $ndays) {
        $ndays = 14;
    }
    if ($ndays !~ m{^\d+$}) {
        $ndays = 14;
    }
    my $ed8 = ($dt + $ndays - 1)->as_d8();

    if (!$cur_clust) {
        $cur_clust = $c->request->params->{cluster_id} || 1;
    }
    my $cl_name = $cluster{$cur_clust}->name();

    #
    # find everything that is happening in this date range.
    # dup'ed code (almost) from DailyPic.  perhaps take
    # it out into Util???
    #
    my $event_table = "";
    my @events = ();
    for my $type (qw/Event Rental Program/) {
        EVENT:
        for my $ev (model($c, $type)->search({
                        sdate => { '<=', $ed8 },
                        edate => { '>=', $d8  },
                    })
        ) {
            if ($type eq 'Program'
                && (
                    ($ev->name() =~ m{personal.*retreats}i)
                    ||
                    ($ev->level() =~ m{[DCM]})
                    ||
                    ($ev->category->name() ne 'Normal')
                   )
            ) {
                next EVENT;
            }
            if ($type eq 'Rental' && $ev->program_id()) {
                # skip this rental - the parallel program will be there
                next EVENT;
            }

            my $ev_type = ref($ev);
            $ev_type =~ s{.*::}{};
            $ev_type = lc $ev_type;
            my $ed;
            if ($type eq 'Program' && $ev->extradays() != 0) {
                $ed = date($ev->edate(), "%m/%d") + $ev->extradays();
            }
            else {
                $ed = date($ev->edate, "%m/%d"),
            }
            my $clusters = "";
            if ($type ne 'Event') {
                $clusters = join ', ',
                            map {
                                $_->name()
                            }
                            reserved_clusters($c, $ev->id, $ev_type);
            }
            my $color = "white";        # default background for this user???
            if ($type ne 'Event' && $ev->color()) {
                $color = $ev->color_bg();
            }
            push @events, {
                sdate => date($ev->sdate, "%m/%d"),
                edate => $ed,
                color => $color,
                name  => $ev->name(),
                type  => $ev_type,
                id    => $ev->id(),
                reserved_clusters => $clusters,
            };
        }
    }
    my $prog_staff = $c->check_user_roles('prog_staff');
    for my $ev (sort { $a->{sdate} <=> $b->{sdate} } @events) {
        if ($prog_staff) {
            $ev->{name} =
                "<a target=happening href=/$ev->{type}/view/$ev->{id}>"
              . $ev->{name}
              . "</a>";
        }
        $event_table .=
            "<tr>"
          . "<td>$ev->{sdate}</td>"
          . "<td>$ev->{edate}</td>"
          . "<td style='border: solid; border-width: thin;' bgcolor="
          .       $ev->{color} . "></td>"
          . "<td>$ev->{name}</td>"
          . "<td>$ev->{reserved_clusters}</td>"
          . "</tr>\n";
    }
    if ($event_table) {
        $event_table = <<EOT;
<p class=p2>
<table cellpadding=3>
<tr>
<th>Start</th>
<th>End</th>
<th width=25></th>
<th align=left>Name</th>
<th align=left>Reserved Clusters</th>
</tr>
$event_table
</table>
EOT
    }

=comment
this reserved table is
no longer needed since we now have the event table.
    #
    # which programs/rentals have reserved this cluster
    # during this date range $dt => $dt+$ndays?
    #
    my $sdate = $d8;
    my $edate = ($dt + $ndays - 1)->as_d8();
    my $res_table = "";
    my @progs = 
        map {
            $_->program()
        }
        model($c, 'ProgramCluster')->search(
            {
                cluster_id      => $cur_clust,
                'program.sdate' => { '<=' => $edate },
                'program.edate' => { '>'  => $sdate },
            },
            {
                join     => 'program',
                prefetch => 'program',
            }
        );
    my @rents =
        map {
            $_->rental()
        }
        model($c, 'RentalCluster')->search(
            {
                cluster_id     => $cur_clust,
                'rental.sdate' => { '<=' => $edate },
                'rental.edate' => { '>'  => $sdate },
            },
            {
                join     => 'rental',
                prefetch => 'rental',
            }
        );
    for my $ev (sort {
                    $a->sdate() <=> $b->edate()
                }
                @progs, @rents
    ) {
        $res_table .= "<tr>"
                   .  "<td>"
                   .  $ev->sdate_obj->format("%b %e")
                   .  "</td>"
                   .  "<td>"
                   .  $ev->edate_obj->format("%b %e")
                   .  "</td>"
                   .  "<td><a target=happening href=/"
                   .  $ev->event_type()
                   .  "/view/"
                   .  $ev->id()
                   .  ">"
                   .  $ev->name()
                   .  "</a></td>"
                   .  "</tr>"
                   ;
    }
    if ($res_table) {
        $res_table = <<"EOH";
<p>
<table cellpadding=3>
<tr>
<th colspan=3 align=center>Reserved for these Events:</th>
</tr>
$res_table
</table>
EOH
    }
=cut
    my ($height, $width) = (0, 0);
    my $hh = $string{house_height};
    my $hw = $string{house_width};
    my $hl = $string{house_let};
    my $space = 7;
    $width = $space;
    for my $h (@{$houses_in_cluster{$cur_clust}}) {
        my $wd = $h->max * $hw + 6;

        # is the name of the house wider than the house rectangle itself?
        #
        my $name = $h->name;
        if ($h->disp_code =~ m{t}) {
            $name =~ s{^\S*\s*}{};
        }
        my $nwd = length($name)*$hl;
        if ($nwd > $wd) {
            $wd = $nwd;
        }
        $width += $space + $wd;
    }
    $width += $hl*6;   # 'Oct 10'
    $width += $space;    # right hand margin
    $height = $ndays * ($space + $hh) + $space;
    $height += 16;  # house names

    my $cv = GD::Image->new($width+1, $height+1);
    my $pct = $string{dp_img_percent}/100;
    my $resize_height = $height*$pct;

    my $white = $cv->colorAllocate(255,255,255);    # 1st color = background
    my $black = $cv->colorAllocate(  0,  0,  0);

    my %char_color;
    for my $c (qw/ M F X R B S empty_bed resize /) {
        $char_color{$c} = $cv->colorAllocate(
                              $string{"dp_$c\_color"} =~ m{(\d+)}g);
    }

    $cv->rectangle(0, 0, $width, $height, $black);
    my ($x1, $y1, $x2, $y2);
    $x1 = $space + $hl*6;
    $y1 = $space;
    for my $h (@{$houses_in_cluster{$cur_clust}}) {
        # UNDUP this and above!???
        my $wd = $h->max * $hw + 6;
        # is the name of the house wider than the house rectangle itself?
        my $name = $h->name;
        if ($h->disp_code =~ m{t}) {
            $name =~ s{^\S*\s*}{};
        }
        my $nwd = length($name)*$hl;
        if ($nwd > $wd) {
            $wd = $nwd;
        }
        $cv->string(gdGiantFont, 
                    $x1, $y1,
                    $name, $black);
        $x1 += $wd + $space;
    }
    #
    # in preparation for drawing the houses and filling in the
    # current configuration, get all the config records that apply
    # and put them in a hash of hashes indexed by house_id and date.
    #
    my @house_ids = map { $_->id } @{$houses_in_cluster{$cur_clust}};
    my %config;
    if (@house_ids) {
        for my $cf (model($c, 'Config')->search({
                        house_id => { -in => \@house_ids },
                        the_date => {
                                        between => [
                                            $dt->as_d8(),
                                            ($dt + $ndays - 1)->as_d8(),
                                        ]
                                    },
                        cur      => { '>', 0 },
                    })
        ) {
            $config{$cf->house_id}{$cf->the_date} = $cf;
        }
    }
    $y1 += 16;      # font height???
    $x1 = $space;
    my ($sex, $cur, $curmax);
    my $prev_mon = -1;
    my $cv_map = "";
    for my $d (1 .. $ndays) {
        my $cur_dt = $dt + $d - 1;
        my $mon = $cur_dt->month();
        $cv->string(gdGiantFont, 
                    $x1, $y1,
                    $cur_dt->format(
                        ($mon == $prev_mon)? "    %e"
                        :                    "%b %e"
                    ), $black);
        $prev_mon = $mon;
        $x1 += 6*$hl;
        for my $h (@{$houses_in_cluster{$cur_clust}}) {
            my $hid = $h->id();
            my $hwd = $h->max * $hw + 6;
            $x2 = $x1 + $hwd;
            $y2 = $y1 + $hh;
            $cv->rectangle($x1, $y1, $x2, $y2, $black);

            my $room_color = $white;
            if (my $cf = $config{$hid}{$cur_dt->as_d8()}) {
                $sex    = $cf->sex();
                $cur    = $cf->cur();
                $curmax = $cf->curmax();
                #
                # we may have a color different than white
                #
                if (my $pid = $cf->program_id()) {
                    $room_color = cache_color($c, $cv,
                                              'Program', $pid, $room_color);
                }
                elsif (my $rid = $cf->rental_id()) {
                    $room_color = cache_color($c, $cv, 
                                              'Rental', $rid, $room_color);
                }
            }
            else {
                $sex = 'U';     # doesn't matter
                $cur = 0;
                $curmax = $h->max();
            }
            $cv->filledRectangle($x1+1, $y1+1, $x2-1, $y2-1, $room_color);

            my $cw = 9.2;      # char_width - seems to work, empirically derived
            # encode the config record in a string
            my $sexcode = ($sex x $cur);
            if ($sexcode eq 'XX') {
                $sexcode = (int(rand(2)) == 1)? 'MF': 'FM';
            }
            $cv->string(gdGiantFont, $x1+3, $y1+3,
                        $sexcode, $char_color{$sex})  if $cur;
            $cv->string(gdGiantFont, $x1+3 + $cw*$cur, $y1+3,
                        $string{dp_empty_bed_char} x ($curmax - $cur),
                        $char_color{empty_bed})            if ($curmax - $cur);
            $cv->string(gdGiantFont, $x1+3 + $cw*$curmax, $y1+3,
                        $string{dp_resize_char}    x ($h->max() - $curmax),
                        $char_color{resize})               if $curmax;
            if ($cur > 0) {
                # for the image maps to work we need to adjust
                # the coordinates according to how the browser
                # will resize the image.
                #
                my $nx1 = $x1*$pct;
                my $ny1 = $y1*$pct;
                my $nx2 = $x2*$pct;
                my $ny2 = $y2*$pct;
                $cv_map .= "<area shape=rect coords='$nx1, $ny1, $nx2, $ny2'"
                        . qq! onclick="Send('$sex', $hid, !
                        . $cur_dt->as_d8()
                        . qq!);"!
                        . qq! onmouseout="return nd();">\n!
                        ;
            }

            # time to advance x1.
            # is the name of the house wider than the house rectangle itself?
            my $name = $h->name;
            if ($h->disp_code =~ m{t}) {
                $name =~ s{^\S*\s*}{};
            }
            my $nwd = length($name)*$hl;
            if ($nwd < $hwd) {
                $nwd = $hwd;
            }
            $x1 += $nwd + $space;
        }
        $x1 = $space;
        $y1 = $y1 + $hh + $space;
    }
    my $im_name = "im"
                  . 'C'
                  . sprintf("%04d%02d%02d%02d%02d%02d",
                            (localtime())[reverse (0 .. 5)])
                  . ".png";
    my $im_uri = $c->uri_for("/static/images/$im_name");
    open my $imf, ">", "root/static/images/$im_name"
        or die "no $im_name: $!\n"; 
    print {$imf} $cv->png;
    close $imf;

    my $who_is_there = $c->uri_for("/registration/who_is_there");
    my $back = ($dt - $ndays)->as_d8();
    my $next = ($dt + $ndays)->as_d8();
    my $html = <<"EOH";
<html>
<head>
<title>Cluster View</title>
<link rel="stylesheet" type="text/css" href="/static/cal.css" />
<script type="text/javascript" src="/static/js/overlib.js">
<!-- overLIB (c) Erik Bosrup -->
</script>
<script type="text/javascript">

// prepare for an Ajax call:
var xmlhttp = false;
var ua = navigator.userAgent.toLowerCase();
if (!window.ActiveXObject)
    xmlhttp = new XMLHttpRequest();
else if (ua.indexOf('msie 5') == -1)
    xmlhttp = new ActiveXObject("Msxml2.XMLHTTP");
else
    xmlhttp = new ActiveXObject("Microsoft.XMLHTTP");

function Get() {
    if (xmlhttp.readyState == 4 && xmlhttp.status == 200) {
        return overlib(xmlhttp.responseText,
                       STICKY, MOUSEOFF, TEXTFONT,
                       'Verdana', TEXTSIZE, 5, WRAP, CELLPAD, 7,
                       FGCOLOR, '#FFFFFF', BORDER, 2)
    }
}

function Send(sex, house_id, date) {
    var url = '$who_is_there/'
            + sex
            + '/'
            + house_id
            + '/'
            + date
            ;
    xmlhttp.open('GET', url, true);
    xmlhttp.onreadystatechange = Get;
    xmlhttp.send(null);

    return true;
}
</script>
</head>
<body>
<form name=form action=/cluster/show method=post>
<span class=keyed>C</span>luster <select name=cluster_id onchange="document.form.submit();" accesskey='c'>
EOH
    $html .= join '',
             map {
                 "<option value="
                 . $_->id
                 .  (($_->id == $cur_clust)? " selected"
                     :                       ""         )
                 . ">"
                 . $_->name
                 . "\n"
             }
             @clusters;
    $html .= <<"EOH";
</select>
<a class=details href=/cluster/show/$back/$cur_clust/$ndays accesskey='b'><span class=keyed>B</span>ack</a>
<a class=details href=/cluster/show/$next/$cur_clust/$ndays accesskey='n'><span class=keyed>N</span>ext</a>
<span class=details><span class=keyed>D</span>ate<input type=text name=date size=10 value='$dt' accesskey='d'></span>&nbsp;# of Da<span class=keyed>y</span>s <input accesskey='y' type=text name=ndays size=2 value=$ndays>&nbsp;<input class=go type=submit value="Go">
</form>
<h2>$cl_name</h2>
<table cellpadding=3>
<tr><td>
<img src=$im_uri height=$resize_height border=0 usemap=#clusterview>
</td><td valign=center>
<table cellpadding=2>
<tr><td>$string{dp_empty_bed_char}</td><td>empty bed</td></tr>
<tr><td>$string{dp_resize_char}</td><td>resized room</td></tr>
<tr><td>B</td><td>block</td></tr>
<tr><td>F</td><td>female</td></tr>
<tr><td>M</td><td>male</td></tr>
<tr><td>R</td><td>rental</td></tr>
<tr><td>S</td><td>meeting space</td></tr>
<tr><td>X</td><td>mixed gender</td></tr>
</table>
</td>
</tr></table>
$event_table
<map name=clusterview>
$cv_map</map>
</body>
</html>
EOH
    $c->res->output($html);
}

#
# a complex mechanism to avoid re-allocation of colors in a GD image.
#
my %cached_colors;
sub clear_cache {
    %cached_colors = ();
}
sub cache_color {
    my ($c, $image, $type, $id, $def_color) = @_;

    my $key = "$type-$id";
    if (! exists $cached_colors{$key}) {
        my $hap = model($c, $type)->find($id);
        if ($hap && (my $col = $hap->color())) {
            $cached_colors{$key}
                = $image->colorAllocate($col =~ m{(\d+)}g);
        }
        else {
            $cached_colors{$key} = $def_color;
        }
    }
    return $cached_colors{$key};
}

1;
