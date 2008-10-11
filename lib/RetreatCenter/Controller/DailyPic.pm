use strict;
use warnings;
package RetreatCenter::Controller::DailyPic;
use base 'Catalyst::Controller';

use lib "../..";

use GD;
use Date::Simple qw/
    date
/;
use Global qw/
    %string
    %clust_color
    %houses_in
    %annotations_for
/;
use Util qw/
    model
    empty
    tt_today
/;

sub index : Local {
    # ???
}

sub show : Local {
    my ($self, $c, $type, $date) = @_;

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
    my $d8 = $dt->as_d8();

    # first determine the size of the entire image
    # by looking at the coordinates and codes of the houses.
    my ($width, $height) = (0, 0);
    my @houses = @{ $houses_in{$type} };
    for my $h (@houses) {
        my $wd = $h->x + $h->max * $string{house_width} + 6;
        my $disp_code = $h->disp_code;
        if (substr($disp_code, 0, 1) eq 'R') {
            my $name = $h->name;
            if ($disp_code =~ m{t}) {
                $name =~ s{^\S*\s*}{};
            }
            $wd += length($name)*$string{house_let};
        }
        my $ht = $h->y + $string{house_height};
        if (substr($disp_code, 0, 1) eq 'B') {
            $ht += $string{house_height};
        }
        if ($wd > $width) {
            $width = $wd;
        }
        if ($ht > $height) {
            $height = $ht;
        }
    }
    # margin???
    $width += $string{house_height};
    $height += $string{house_height};

    my $dp = GD::Image->new($width+1, $height+1);
    my $pct = $string{dp_img_percent}/100;
    my $resize_height = $height*$pct;
    my $white = $dp->colorAllocate(255,255,255);    # 1st color = background
    my $black = $dp->colorAllocate(  0,  0,  0);
    my %char_color;
    for my $c (qw/ M F X R empty_bed resize /) {
        $char_color{$c} = $dp->colorAllocate(
                              $string{"dp_$c\_color"} =~ m{(\d+)}g);
    }
    $dp->rectangle(0, 0, $width, $height, $black);

    # we have the array_ref of colors for each color
    # no need to go to the database
    # but each new GD::Image must allocate its own colors ...
    # so ...
    my %clust_col = map { $_ => $dp->colorAllocate(@{$clust_color{$_}}) }
                    keys %clust_color;

    my $dp_map = "";    
    #
    # with one SQL request get all the needed config records
    # into a hash with keys of the house id.
    # ALSO??? also restrict it to config records where cur > 0?
    # if ! exists $config{$house_id} then we know it is empty.
    # sure!
    #
    my @house_ids = map { $_->id() } @houses;
    my %config;
    for my $cf (model($c, 'Config')->search({
                    house_id => { -in => \@house_ids },
                    the_date => $d8,
                    cur      => { '>', 0 },
                })
    ) {
        $config{$cf->house_id()} = $cf;
    }
    HOUSE:
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
        my $code = substr($disp_code, 0, 1);
        my ($offset) = $disp_code =~ m{(\d+)};
        $offset |= 0;
        # the 3 and 6 below are for margins
        my $x2 = $x1 + $h->max * $string{house_width} + 6;
        my $y2 = $y1 + $string{house_height};
        $dp->rectangle($x1, $y1, $x2, $y2, $black);
        $dp->filledRectangle($x1+1, $y1+1, $x2-1, $y2-1,
                             $clust_col{$h->cluster_id});
        # below we have a cool use of the ?: operator!  (what is its name?)
        $dp->string(gdGiantFont,
            ($code eq 'L')? ($x1-length($tname)*$string{house_let}-2,$y1+3)
           :($code eq 'R')? ($x2+3, $y1+3)
           :($code eq 'A')? ($x1-$offset, $y1-$string{house_height}+3)
           :($code eq 'B')? ($x1, $y1+$string{house_height}+3)
           :                (0, 0),    # shouldn't happen
                    $tname, $black);
        my ($sex, $cur, $curmax);
        if (exists $config{$hid}) {
            my $cf = $config{$hid};
            $sex    = $cf->sex();
            $cur    = $cf->cur();
            $curmax = $cf->curmax();
        }
        else {
            $sex = 'U';     # doesn't matter
            $cur = 0;
            $curmax = $h->max();
        }
        my $cw = 9.2;       # char_width - seems to work, empirically derived
        # encode the config record in a string
        $dp->string(gdGiantFont, $x1+3, $y1+3,
                    ($sex x $cur), $char_color{$sex})  if $cur;
        $dp->string(gdGiantFont, $x1+3 + $cw*$cur, $y1+3,
                    $string{dp_empty_bed_char} x ($curmax - $cur),
                    $char_color{empty_bed})            if ($curmax - $cur);
        $dp->string(gdGiantFont, $x1+3 + $cw*$curmax, $y1+3,
                    $string{dp_resize_char}    x ($h->max() - $curmax),
                    $char_color{resize})               if $curmax;
        if ($cur == 0) {
            next;       # assume that the config and the
                    # Registrations/RentalBookings are in synch.
                    # if not, we're screwed.
                    # this is why I made hcck!
        }
        # for the image maps to work we need to adjust
        # the coordinates according to how the browser
        # will resize the image.
        #
        $x1 *= $pct;
        $y1 *= $pct;
        $x2 *= $pct;
        $y2 *= $pct;
        $dp_map .= "<area shape=rect coords='$x1, $y1, $x2, $y2'"
                . qq! onclick="Send('$sex', $hid);"!
                . qq! onmouseout="return nd();">\n!
                ;
    }
    #
    # render any annotations for this cluster type
    #
    for my $a (@{$annotations_for{$type}} ) {
        my $color;
        if (! empty($a->color())) {
            $color = $dp->colorAllocate($a->color() =~ m{(\d+)}g);
        }
        else {
            $color = $black;
        }
        if (! empty($a->label())) {
            $dp->string(gdGiantFont,
                        $a->x(), $a->y(),
                        $a->label(),
                        $color);
        }
        elsif ($a->shape() ne 'none') {
            my $shape = $a->shape();
            $dp->$shape($a->x1(), $a->y1(),
                        $a->x2(), $a->y2(),
                        $color);
        }
    }
    # write the image to be used shortly
    open my $imf, ">", "root/static/images/dailypic.png"
        or die "no dailypic.png: $!\n"; 
    print {$imf} $dp->png;
    close $imf;
    my $image = $c->uri_for("/static/images/dailypic.png");
    my $back = $dt - 1;
    # how far back can we go???
    #if ($back < $today) {
    #    $back = $today;
    #}
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
                name  => $ev->name(),
                type  => $ev_type,
                id    => $ev->id(),
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
<table cellpadding=3>
<tr><th>Start</th><th>End</td><th align=left>Name</th></tr>
$event_table
</table>
EOT
    }
    my $links = "";
    for my $t (1 .. 5) {
        my $s = $string{"dp_type$t"};
        next if $s eq 'future use';
        my $style = "";
        if ($type eq $s) {
            $style = "style='font-weight: bold'";
        }
        my $keylab;
        # sorry
        if ($s eq "indoors") {
            $keylab = "accesskey='i'><span class=keyed>I</span>ndoors</a>\n";
        }
        elsif ($s eq "outdoors") {
            $keylab = "accesskey='o'><span class=keyed>O</span>utdoors</a>\n";
        }
        elsif ($s eq "special") {
            $keylab = "accesskey='p'>S<span class=keyed>p</span>ecial</a>\n";
        }
        $links .= "<a class=details $style href='/dailypic/show/$s/$d8' $keylab\n";
    }
    my $html = <<EOH;
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

function Send(sex, house_id) {
    var url = 'http://localhost:3000/registration/who_is_there/'
            + sex
            + '/'
            + house_id
            + '/'
            + $d8
            ;
    xmlhttp.open('GET', url, true);
    xmlhttp.onreadystatechange = Get;
    xmlhttp.send(null);

    return true;
}
</script>
</head>
<body>
<span class=hdr>$dt_fmt</span>
<p>
<form method=POST action="/dailypic/show/$type">
<a href="/dailypic/show/$type/$back" accesskey='b'><span class=keyed>B</span>ack</a>
<a class=details href="/dailypic/show/$type/$next" accesskey='n'><span class=keyed>N</span>ext</a>
<span class=details> <span class=keyed>D</span>ate <input type=text name=date size=10 value='$dt' accesskey='d'></span>
<input class=go type=submit value="Go">
$links
</form>
<p>
<img height=$resize_height src=$image usemap=#dailypic>
$event_table
<map name=dailypic>
$dp_map</map>
</body>
EOH
    $c->res->output($html);
}

1;
