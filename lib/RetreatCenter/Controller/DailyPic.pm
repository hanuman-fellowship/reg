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
    my $dt;
    if ($date) {
        $dt = date($date);
    }
    else {
        $dt = today();
    }
    my $d8 = $dt->as_d8();

    my ($width, $height) = (0, 0);
    my @houses = model($c, 'House')->all();
    for my $h (@houses) {
        my $wd = $h->x + $h->max * $lookup{house_width};
        my $ht = $h->y + $lookup{house_height};
        if ($wd > $width) {
            $width = $wd;
        }
        if ($ht > $height) {
            $height = $ht;
        }
    }
    # a little right, bottom margin
    $width += 10;
    $height += 10;
    my $dp = GD::Image->new($width, $height);
    my $dp_map = "";    
    my $white = $dp->colorAllocate(255,255,255);    # 1st color = background
    my $black = $dp->colorAllocate(0, 0, 0);
    my %clust_color;
    my @clusters = model($c, 'Cluster')->all();
    for my $c (@clusters) {
        $clust_color{$c->id} = $dp->colorAllocate($c->color =~ m{\d+}g);
    }
    for my $h (@houses) {
        my $x1 = $h->x;
        my $y1 = $h->y;
        my $name = $h->name;
        my $hid = $h->id;
        my $x2 = $x1 + $h->max * $lookup{house_width} + 3;
        my $y2 = $y1 + $lookup{house_height};
        $dp->rectangle($x1, $y1, $x2, $y2, $black);
        $dp->filledRectangle($x1+1, $y1+1, $x2-1, $y2-1,
                             $clust_color{$h->clust_id});
        $dp->string(gdLargeFont,
                    $x1-length($name)*$lookup{house_let}, $y1+3,
                    $name, $black);
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
        $dp->string(gdLargeFont,
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
    my $next = $dt + 1;
    $back = $back->as_d8();
    $next = $next->as_d8();
    my $dt_fmt = $dt->format("%D %E %y");
    my $html = <<EOH;
<head>
<link rel="stylesheet" type="text/css" href="/static/cal.css" />
<script type="text/javascript" src="/static/js/overlib.js"><!-- overLIB (c) Erik Bosrup --></script>
<style type="text/css">
body {
    background: #888888;
}
</style>
</head>
<body>
<h2>Daily Picture for $dt_fmt</h2>
<a href="/dailypic/show/$back">Back</a>
&nbsp;&nbsp;&nbsp;
<a href="/dailypic/show/$next">Next</a>
<br>
<img src=$image usemap=#dailypic>
<map name=dailypic>
$dp_map
</map>
</body>
EOH
    $c->res->output($html);
}

1;
