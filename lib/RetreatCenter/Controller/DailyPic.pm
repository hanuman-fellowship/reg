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
    %houses_in
    %houses_in_cluster
    %annotations_for
    @clusters
/;
use Util qw/
    model
    empty
    tt_today
    reserved_clusters
    d3_to_hex
/;

sub index : Local {
    # ???
}

sub dp_form {
    my ($type, $dt) = @_;

    my $back = $dt - 1;      # how far back can we go???
    my $next = $dt + 1;
    my $last_date = date($string{sys_last_config_date});
    if ($next > $last_date) {
        $next = $last_date;
    }
    $back = $back->as_d8();
    $next = $next->as_d8();
    my $dt_fmt = $dt->format("%A %B %e, %Y");
    my $dtD = $dt->format("%D");
    my $d8 = $dt->as_d8();
    my $form = <<"EOH";
<span class=hdr>$dt_fmt</span>
<p>
<form method=POST action="/dailypic/show/$type">
<a href="/dailypic/show/$type/$back" accesskey='b'><span class=keyed>B</span>ack</a>
<a class=details href="/dailypic/show/$type/$next" accesskey='n'><span class=keyed>N</span>ext</a>
<span class=details> <span class=keyed>D</span>ate <input type=text name=date size=10 value='$dtD' accesskey='d'></span>
<input class=go type=submit value="Go">
EOH
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
        elsif ($s eq "resident") {
            $keylab = "accesskey='r'><span class=keyed>R</span>esident</a>\n";
        }
        $form .= "<a class=details $style href='/dailypic/show/$s/$d8' $keylab\n";
    }
    $form .= "</form>";
    return $form;
}

#
# find everything that is happening on this day
#
sub event_table {
    my ($c, $d8) = @_;

    my $event_table = "";
    my @events = ();
    for my $event_type (qw/Event Rental Program/) {
        EVENT:
        for my $ev (model($c, $event_type)->search({
                        sdate => { '<=', $d8 },
                        edate => { '>=', $d8 },
                    })
        ) {
            if ($event_type eq 'Program'
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
            if ($event_type eq 'Rental' && $ev->program_id()) {
                # skip this rental - the parallel program will be there
                next EVENT;
            }
            my $ev_type = ref($ev);
            $ev_type =~ s{.*::}{};
            $ev_type = lc $ev_type;
            my $ed;
            if ($event_type eq 'Program' && $ev->extradays() != 0) {
                $ed = date($ev->edate(), "%m/%d") + $ev->extradays();
            }
            else {
                $ed = date($ev->edate, "%m/%d"),
            }
            my $clusters = "";
            if ($event_type ne 'Event') {
                $clusters = join ', ',
                            map {
                                $_->name()
                            }
                            reserved_clusters($c, $ev->id, $ev_type);
            }
            my $color = "white";     # default background for this happening?
            if ($event_type ne 'Event' && $ev->color()) {
                $color = $ev->color_bg();
            }
            push @events, {
                sdate => date($ev->sdate, "%m/%d"),
                edate => $ed,
                color => $color,
                name  => $ev->name(),
                count => $ev->count(),
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
          . "<td align=right>$ev->{count}&nbsp;&nbsp;</td>"
          . "<td>$ev->{reserved_clusters}</td>"
          . "</tr>\n";
    }
    if ($event_table) {
        $event_table = <<EOT;
<table cellpadding=3>
<tr>
<th>Start</th>
<th>End</th>
<th width=25></th>
<th align=left>Name</th>
<th align=left>Count</th>
<th align=left>Reserved Clusters</th>
</tr>
$event_table
</table>
EOT
    }
    return $event_table;
}

sub show : Local {
    my ($self, $c, $type, $date) = @_;

    $type ||= "indoors";
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
    my $d8 = $dt->as_d8();

    if ($type eq 'resident') {
        html_show($c, $dt);
        return;
    }
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
    $width += $string{dp_margin_right};
    $height += $string{dp_margin_bottom};

    my $dp = GD::Image->new($width+1, $height+1);
    my $pct = $string{dp_img_percent}/100;
    my $resize_height = $height*$pct;
    my $white = $dp->colorAllocate(255,255,255);    # 1st color = background
    my $black = $dp->colorAllocate(  0,  0,  0);
    my %char_color;
    for my $c (qw/ M F X R B S empty_bed resize /) {
        $char_color{$c} = $dp->colorAllocate(
                              $string{"dp_$c\_color"} =~ m{(\d+)}g);
    }
    $dp->rectangle(0, 0, $width, $height, $black);

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
        # below we have a cool use of the ?: operator!  (what is its name?)
        $dp->string(gdGiantFont,
            ($code eq 'L')? ($x1-length($tname)*$string{house_let}-2,$y1+3)
           :($code eq 'R')? ($x2+3, $y1+3)
           :($code eq 'A')? ($x1-$offset, $y1-$string{house_height}+3)
           :($code eq 'B')? ($x1, $y1+$string{house_height}+3)
           :                (0, 0),    # shouldn't happen
                    $tname, $black);
        my ($sex, $cur, $curmax);
        my $color = $white;
        if (exists $config{$hid}) {
            my $cf = $config{$hid};
            $sex    = $cf->sex();
            $cur    = $cf->cur();
            $curmax = $cf->curmax();

            # we may have a color different than white.
            #
            if (my $pid = $cf->program_id()) {
                $color = cache_color($c, $dp, 'Program', $pid, $color);
            }
            elsif (my $rid = $cf->rental_id()) {
                $color = cache_color($c, $dp, 'Rental', $rid, $color);
            }
        }
        else {
            $sex = 'U';     # doesn't matter
            $cur = 0;
            $curmax = $h->max();
        }
        $dp->filledRectangle($x1+1, $y1+1, $x2-1, $y2-1, $color);
        my $cw = 9.2;       # char_width - seems to work, empirically derived
        # encode the config record in a string
        my $sexcode = ($sex x $cur);
        if ($sexcode eq 'XX') {
            # for non-sexist purposes...
            # to not make the women angry ...
            $sexcode = (int(rand(2)) == 1)? 'MF': 'FM';
        }
        $dp->string(gdGiantFont, $x1+3, $y1+3,
                    $sexcode, $char_color{$sex})  if $cur;
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
        if ($a->shape() ne 'none') {
            my $shape = $a->shape();
            $dp->setThickness($a->thickness());
            $dp->$shape($a->x1(), $a->y1(),
                        $a->x2(), $a->y2(),
                        $color);
            $dp->setThickness(1);
        }
        else {
            $dp->string(gdGiantFont,
                        $a->x(), $a->y(),
                        $a->label(),
                        $color);
        }
    }
    # write the image (to be used shortly) to a file
    # with a well defined name
    #
    my $im_name = "im"
                  . uc(substr($type, 0, 1)) 
                  . sprintf("%04d%02d%02d%02d%02d%02d",
                            (localtime())[reverse (0 .. 5)])
                  . ".png";
    open my $imf, ">", "root/static/images/$im_name"
        or die "no $im_name: $!\n"; 
    print {$imf} $dp->png;
    close $imf;
    my $image = $c->uri_for("/static/images/$im_name");
    my $campsites = "";
    if ($type eq 'outdoors') {
        $campsites = join '<br>',
                     map {
                         "<img border=0 src="
                         . $c->uri_for("/static/images/$_")
                         . ">"
                     }
                     qw/
                         oaks.gif
                         mad.jpg
                     /;
                   ;
    }
    my $event_table = event_table($c, $d8);
    my $who_is_there = $c->uri_for("/registration/who_is_there");
    my $dp_form = dp_form($type, $dt);
    my $ucf_type = ucfirst $type;
    my $html = <<"EOH";
<head>
<title>$ucf_type Daily Picture</title>
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
    var url = '$who_is_there/'
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
$dp_form
<table cellpadding=3>
<tr><td>
<img height=$resize_height src=$image border=0 usemap=#dailypic>
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
$campsites
<map name=dailypic>
$dp_map</map>
</body>
EOH
    $c->res->output($html);
}

#
# for now, only resident clusters/houses
#
sub html_show {
    my ($c, $dt) = @_; 

    my $d8 = $dt->as_d8();
    my $type = 'resident';
    my @house_ids = ();
    my %cat_abode = ();
    my %sq_foot   = ();
    for my $h (@{$houses_in{'resident'}}) {
        my $h_id = $h->id();
        push @house_ids, $h_id;
        $cat_abode{$h_id} = $h->cat_abode();
        $sq_foot  {$h_id} = $h->sq_foot();
    }
    my %info_for_house_id = ();
    for my $reg (model($c, 'Registration')->search({
                     date_start => { '<=' => $d8 },
                     date_end   => { '>=' => $d8 },
                     house_id   => { -in => \@house_ids },
                 })
    ) {
        my $per = $reg->person();
        my $pr  = $reg->program();
        push @{$info_for_house_id{$reg->house_id()}}, {
            reg_id => $reg->id(),
            first  => $per->first(),
            last   => $per->last(),
            uniq   => "",           # to be determined after
                                    # gathering all names
            category => $pr->category->name(),
            color    => d3_to_hex($pr->color()),
        };
        # note that we may have more than one person per room
        # with a different category/color.
    }
    # do two people in the %info_for_house_id hash
    # have the same first name and so need to be unique-ized
    # with a unique prefix of their last name?
    #
    # first gather all the last names for a given first name
    #
    my %lastnames_for = ();
    for my $h (keys %info_for_house_id) {
        for my $p (@{$info_for_house_id{$h}}) {
            push @{$lastnames_for{$p->{first}}}, $p->{last};
        }
    }
    use Text::Abbrev;
    my %uniq_for = ();
    for my $f (keys %lastnames_for) {
        if (@{$lastnames_for{$f}} >= 2) {
            #
            # the first name $f has two or more last names
            #
            my %abbrevs = abbrev(@{$lastnames_for{$f}});
            for my $ab (sort { length $a <=> length $b } keys %abbrevs) {
                my $lname = $abbrevs{$ab};
                if (!exists $uniq_for{"$f|$lname"}) {
                    $uniq_for{"$f|$lname"} = $ab;
                }
            }
        }
    }
    # now set the uniq value for those names
    # that we determined do need it.
    #
    for my $id (keys %info_for_house_id) {
        for my $p (@{$info_for_house_id{$id}}) {
            my $first = $p->{first};
            my $last  = $p->{last};
            if (exists $uniq_for{"$first|$last"}) {
                $p->{uniq} = " " . $uniq_for{"$first|$last"};
            }
        }
    }
    my @res_clusters = sort { $a->cl_order() <=> $b->cl_order() }
                       grep { $_->type eq 'resident'            }
                       @clusters;
=comment
use Data::Dumper;
    my $html = "<pre>";
    $html .= "house_ids\n";
    $html .= Dumper(\@house_ids);
    $html .= "cat abode\n";
    $html .= Dumper(\%cat_abode);
    $html .= "sq_foot\n";
    $html .= Dumper(\%sq_foot);
    $html .= "info for house_id\n";
    $html .= Dumper(\%info_for_house_id);
    $html .= "lastnames_for\n";
    $html .= Dumper(\%lastnames_for);
    $html .= "houses in cluster\n";
    for my $cl (@res_clusters) {
        $html .= $cl->name() . "\n";
        for my $h (@{$houses_in_cluster{$cl->id()}}) {
            $html .= "    " . $h->id() . "\n";
        }
    }
    $c->res->output($html);
=cut
    my $dp_form = dp_form($type, $dt);
    my $event_table = event_table($c, $d8);
    my $html = <<"EOH";
<html>
<head>
<title>Resident Daily Picture</title>
<link rel="stylesheet" type="text/css" href="/static/cal.css" />
</head>
<body>
$dp_form
EOH
    for my $cl (@res_clusters) {
        my $cl_name = $cl->name();
        $html .= <<"EOH";
<div style="float: left; margin-left: 10mm">
<h3>$cl_name</h3>
<table cellpadding=3 border=1>
EOH
        for my $h (@{$houses_in_cluster{$cl->id()}}) {
            my $h_id = $h->id();
            $html .= "<tr>\n";

            # name
            $html .= "<td width=100>"
                  .  $h->name()     # truncated?
                  .  "</td>\n"
                  ;

            # people's names - properly colored according to their program
            $html .= "<td width=100>";
            my @people = exists $info_for_house_id{$h_id}?
                             @{$info_for_house_id{$h_id}}
                         :   ();
            for my $p (@people) {       # does the sort matter?
                $html .= "<a style='color: $p->{color}' target=happening"
                      .  " href=/registration/view/$p->{reg_id}>"
                      .  "$p->{first}$p->{uniq}</a><br>"
                      ;
            }
            # a dash for empty beds
            if (@people > 0 && $h->max > @people) {
                $html .= "-<br>" x ($h->max() - @people);
            }
            $html .= "</td>\n";

            # cat abode?
            $html .= "<td width=20>"
                  .  ($cat_abode{$h_id}? 'cat': '')
                  .  "</td>\n"
                  ;

            # square footage
            $html .= "<td width=30 align=right>$sq_foot{$h_id}</td>\n";

            $html .= "</tr>";
        }
        $html .= <<"EOH";
</table>
</div>
EOH
    }
    # I don't know why I need 2 divs here to give
    # some separation for the event_table.
    #
    $html .= <<"EOH";
<div style="clear: both">
</div>
<div style="margin-top: 8mm">
$event_table
</div>
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
