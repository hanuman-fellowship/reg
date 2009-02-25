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
/;
use Date::Simple qw/
    date
/;
use Global qw/
    %string
    %clust_color
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
    my ($r, $g, $b) = $cl->color =~ m{\d+}g;
    $c->stash->{red  } = $r;
    $c->stash->{green} = $g;
    $c->stash->{blue } = $b;
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
    my $color = $c->request->params->{color};
    my $type  = $c->request->params->{type};
    for my $f (qw/name color/) {
        if (empty($f)) {
            $c->stash->{mess} = "\u$f cannot be blank.";
            $c->stash->{template} = "cluster/error.tt2";
            return;
        }
    }
    model($c, 'Cluster')->find($id)->update({
        name  => $name,
        color => $color,
        type  => $type,
    });
    # and update the Global.  no need to reload it all.
    $clust_color{$id} = [ $color =~ m{(\d+)}g ];
    $c->response->redirect($c->uri_for('/cluster/list'));
}

sub create : Local {
    my ($self, $c) = @_;

    $c->stash->{red  } = 255;
    $c->stash->{green} = 255;
    $c->stash->{blue } = 255;
    $c->stash->{type_opts} = <<"EOO";
<option value="indoors">Indoors
<option value="outdoors">Outdoors
<option value="special">Special
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
    my $color = $c->request->params->{color};
    my $type  = $c->request->params->{type};
    for my $f (qw/name color/) {
        if (empty($f)) {
            $c->stash->{mess} = "\u$f cannot be blank.";
            $c->stash->{template} = "cluster/error.tt2";
            return;
        }
    }
    model($c, 'Cluster')->create({
        name  => $name,
        color => $color,
        type  => $type,
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
    my ($self, $c, $date, $cur_clust) = @_;

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
    my $ndays = 14;     # parameter?
    if (!$cur_clust) {
        $cur_clust = $c->request->params->{cluster_id} || 1;
    }

    my ($height, $width) = (0, 0);
    my $hh = $string{house_height};
    my $hw = $string{house_width};
    my $hl = $string{house_let};
    my $space = 7;
    $width = $space;
    for my $h (@{$houses_in_cluster{$cur_clust}}) {
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
    my $color = $cv->colorAllocate(@{$clust_color{$cur_clust}});

    my %char_color;
    for my $c (qw/ M F X R empty_bed resize /) {
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
            $cv->filledRectangle($x1+1, $y1+1, $x2-1, $y2-1, $color);

            if (my $cf = $config{$hid}{$cur_dt->as_d8()}) {
                $sex    = $cf->sex();
                $cur    = $cf->cur();
                $curmax = $cf->curmax();
            }
            else {
                $sex = 'U';     # doesn't matter
                $cur = 0;
                $curmax = $h->max();
            }

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
<a class=details href=/cluster/show/$back/$cur_clust accesskey='b'><span class=keyed>B</span>ack</a>
<a class=details href=/cluster/show/$next/$cur_clust accesskey='n'><span class=keyed>N</span>ext</a>
<span class=details><span class=keyed>D</span>ate<input type=text name=date size=10 value='$dt' accesskey='d'></span> <input class=go type=submit value="Go">
</form>
<img src=$im_uri height=$resize_height border=0 usemap=#clusterview>
<map name=clusterview>
$cv_map</map>
</body>
</html>
EOH
    $c->res->output($html);
}

1;
