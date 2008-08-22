use strict;
use warnings;

package Util;
use base 'Exporter';
our @EXPORT_OK = qw/
    affil_table
    meetingplace_table
    places
    role_table
    leader_table
    trim
    empty
    nsquish
    slurp
    expand
    expand2
    monthyear
    resize
    housing_types
    parse_zips
    sys_template
    compute_glnum
    valid_email
    digits
    model
    email_letter
    lunch_table
    clear_lunch
    get_lunch
    add_config
    type_max
    max_type
/;

use POSIX   qw/ceil/;
use Date::Simple qw/
    d8
    date
    today
/;

use Lookup;

my ($naffils, @affils, %checked);

sub _affil_elem {
    my ($i) = @_;
    if ($i >= $naffils) {
        return "<td>&nbsp;</td>";
    }
    my $a = $affils[$i];
    my $id = $a->id();
    my $descrip = $a->descrip();
    return "<td><input type=checkbox name=aff$id "
           . ($checked{$id} || "")
           . ">"
           . $descrip
           . "</td>";
}


#
# get the affiliations table ready for the template.
# this was too hard to do within the template...
# which affils should be checked?
#
# the first parameter is the Catalyst context.
# the next are Afill objects that you want checked.
#
sub affil_table {
    my ($c) = shift;
    %checked = map { $_->id() => 'checked' } @_;

    @affils = model($c, 'Affil')->search(
        undef,
        { order_by => 'descrip' },
    );
    # figure the number of affils in the first and second column.
    $naffils = @affils;
    my $n = ceil($naffils/3);

    my ($aff);
    for my $i (0 .. $n-1) {
        $aff .= "<tr>";

        $aff .= _affil_elem($i);
        $aff .= _affil_elem($i+$n);
        $aff .= _affil_elem($i+2*$n);

        $aff .= "</tr>\n";
    }
    $aff;
}

#
sub role_table {
    my ($c) = shift;

    my %checked = map { $_->id() => 'checked' } @_;

    join "\n",
    map {
        my $id = $_->id();
          "<tr><td>"
        . "<input type=checkbox name=role$id  $checked{$id}> "
        . $_->fullname
        . "</td></tr>"
    }
    sort {
        $a->fullname cmp $b->fullname
    }
    model($c, 'Role')->all();
}

#
# which meeting places are available in the
# date range sdate-edate?
#
# and worry about the max of rentals/programs as well.
#
# note: PRE = Program/Rental/Event
#
sub meetingplace_table {
    my ($c, $max, $sdate, $edate, @cur_bookings) = @_;

    $max ||= 0;

    # the other arguments are Bookings (which point to a
    # meeting place currently assigned to this PRE in question)
    my %checked    = map { $_->meet_id() => 'checked' }
                     grep { ! $_->breakout() }
                     @cur_bookings;
    # br = breakout
    my %br_checked = map { $_->meet_id() => 'checked' }
                     grep { $_->breakout() }
                     @cur_bookings;
    my $table = "";
    MEETING_PLACE:
    for my $mp (model($c, 'MeetingPlace')->search(
                    { max => { '>=', $max } },
                    { order_by => 'name' }
                )
    ) {
        my $id = $mp->id;
        if (! ($checked{$id} || $br_checked{$id})) {
            # this meeting place is not currently assigned to
            # the PRE in question.
            # are there any bookings for this place that overlap
            # with this request?
            my @bookings = model($c, 'Booking')->search({
                              meet_id => $id,
                              sdate => { '<' => $edate },
                              edate => { '>' => $sdate },
                           });
            next MEETING_PLACE if @bookings;
        }
        # it should be included in the table
        $table .= "<tr><td>"
                  . $mp->name
                  . "</td><td align=right>"
                  . $mp->max
                  . "</td><td align=center>"
                  . "<input type=checkbox name=mp$id  "
                  . ($checked{$id} || '')
                  . "> "
                  . "</td><td align=center>"
                  . "<input type=checkbox name=mpbr$id  "
                  . ($br_checked{$id} || '')
                  . "> "
                  . "</td></tr>\n";
    }
    if (! $table) {
        $table = "Sorry, there is no meeting place in the inn.";
    }
    else {
        $table = <<"EOH";
<table cellpadding=3>
<tr>
<th align=left>Name</th>
<th align=right>Max</th>
<th>Main</th>
<th>Breakout</th>
</tr>
$table
</table>
EOH
    }
    $table;
}

sub places {
    my ($event) = @_;

    join ", ", map { $_->meeting_place->abbr } $event->bookings;
}

#
# after $c the parameters
# are an array of leader objects
# that should be checked in the display.
#
sub leader_table {
    my ($c) = shift;

    my %checked = map { $_->id() => 'checked' } @_;

    join "<br>\n",
    map {
        my $id = $_->id();
        my $last = $_->person->last();
        my $first = $_->person->first();
        "<input type=checkbox name=lead$id  $checked{$id}> $last, $first";
    }
    sort {
        $a->person->last()   cmp $b->person->last() or
        $a->person->first () cmp $b->person->first()
    }
    model($c, 'Leader')->all();
}

#
# trim leading and trailing blanks off the parameter
# and return the result
#
sub trim {
    my ($s) = @_;

    return $s unless $s;
    $s =~ s{^\s*|\s*$}{}g;
    $s;
}

#
# is the string empty?  i.e. only white space?
#
sub empty {
    my ($s) = @_;

    return $s =~ m{^\s*$};

}

#
# take the parameters, concatenate them,
# extract the digits in order and suffix
# them with the first letter.
#
# this is used during the efforts to locate
# a duplicate entry.   If an address is
# spelled differently or road instead of rd
# it will have the same nsquished value.
#
# this is a poor man's MD5.
# or an address-specific MD5.
#
sub nsquish {
    my $s = join '', @_;
    my ($c) = $s =~ m{([a-z])}i;
    $s =~ s{\D}{}g;
    $s.(uc $c);
}

#
# slurp an entire template (or other file) into one variable
#
sub slurp {
    my ($fname) = @_;

    if (index($fname, '.') == -1) {     # no period - so it's a web template
        $fname = "root/static/templates/web/$fname.html";
    }
    open my $in, "<", $fname
		or die "cannot open $fname: $!\n";
    local $/;
    my $s = <$in>;
    close $in;
    return $s;
}

#
# __, **, %%%, ~~ expansions into <i>, <b>, <a href=>, <a mailto>
#
# the first _ and * need to appear either after a blank
# or at the beginning of the line - in case an underscore
# is needed elsewhere - like in a web address.
#
sub expand {
	my ($v) = @_;
    $v =~ s{\r?\n}{\n}g;
	$v =~ s#(^|\W)\*(.*?)\*#$1<b>$2</b>#smg;
	$v =~ s#(^|\W)_(.*?)\_#$1<i>$2</i>#smg;
	$v =~ s{%(.*?)%(.*?)%}
           {
               my ($clickpoint, $link) = (trim($1), trim($2));
               $link =~ s{http://}{};   # string http:// if any
               "<a href='http://$link' target=_blank>$clickpoint</a>";
           }esg;
	$v =~ s{~\s*(\S+)\s*~}{<a href="mailto:$1">$1</a>}sg;
	my $in_list = "";
	my $out = "";
	for (split /\n/, $v) {
		unless (/\S/) {
			if ($in_list) {
				$out .= $in_list;
				$in_list = "";
			}
			$out .= "<p>\n";
			next;
		}
		if (s/^(#|-)/<li>/) {
			unless ($in_list) {
				if ($1 eq '#') {
					$out .= "<ol>\n";
					$in_list = "</ol>\n";
				} else {
					$out .= "<ul>\n";
					$in_list = "</ul>\n";
				}
			}
		}
		$out .= "$_\n";
	}
	$out .= $in_list if $in_list;
	$out;
}
#
# for the brochure
#
sub expand2 {
    my ($v) = @_;

    $v = expand($v);
    my $quote = 0;
    while ($v =~ m{"}) {
        $v =~ s{"}{chr(0332+$quote)}e;
        $quote = 1-$quote;
    }
    $v =~ s{'}{\325}g;
    $v =~ s{<b>}{\@bolded}ig;
    $v =~ s{<i>}{\@italicized}ig;
    $v =~ s{<\/[ib]>}{<\@\$p>}ig;
    $v =~ s{</?[ui]l>}{}ig;
    $v =~ s{<li>}{<\\n\*}ig;
    $v =~ s{<a[^>]*>([^<]*)</a>}{$1}ig;
    $v;
}

sub monthyear {
    my ($sdate) = @_;
    return $sdate->format("%B %Y");
}

#
# invoke ImageMagick convert to create
# the thumbnail and large images from the original
#
# if you only want to resize one of the two
# give the optional third parameter.
#
sub resize {
    my ($type, $id, $which) = @_;

    chdir "root/static/images";
    if (!$which || $which eq "imgwidth") {
        system("convert -scale $lookup{imgwidth}x"
              ." ${type}o-$id.jpg ${type}th-$id.jpg");
    }
    if (!$which || $which eq "big_imgwidth") {
        system("convert -scale $lookup{big_imgwidth}x"
              ." ${type}o-$id.jpg ${type}b-$id.jpg");
    }
    chdir "../../..";       # must cd back!   not stateless HTTP, exactly
}

sub housing_types {
    return qw/
		unknown
		commuting
		own_tent
		own_van
		center_tent
		economy
		dormitory
		quad
		triple
		dble
		dble_bath
		single
		single_bath
    /;
}

#
# returns either an array_ref of array_ref of zip code ranges
# or a scalar which is an error message.
#
sub parse_zips {
    my ($s) = @_;
    $s =~ s/\s*,\s*/,/g;

    # Check for zip range validity
    if ($s =~ m/[^0-9,-]/) {
        return "Only digits, commas, spaces and hyphen allowed"
              ." in the zip range field.";
    }

    my @ranges = split /,/, $s, -1;

    my $ranges_ref = [];
    for my $r (@ranges) {
        # Field must be either a zip range or a single zip
        if ($r =~ m/^(\d{5})-(\d{5})$/) {
            my ($startzip, $endzip) = ($1, $2);

            if ($startzip > $endzip) {
                return "Zip range start is greater than end";
            }
            push @$ranges_ref, [ $startzip, $endzip ];
        } 
        elsif ($r =~ m/^\d{5}$/) {
            push @$ranges_ref, [ $r, $r ];
        }
        else {
            return "Please provide a valid 5 digit zip code (xxxxx)"
                  ." or zip range (xxxxx-yyyyy)";
        }
    }
    return $ranges_ref;
}

my %sys_template = map { $_ => 1 } qw/
    progRow
    e_progRow
    e_rentalRow
    events
    popup
    programs
    default
/;

sub sys_template {
    my ($file) = @_;
    return exists $sys_template{$file};
}

#
# a very tricky calculation
# I think it's right.
#
sub compute_glnum {
    my ($c, $sdate) = @_;

    my $dt = date($sdate);
    my $week = $dt->week_of_month;
    my $day = $dt->day;
    my $mon = $dt->month;
    my $dow = $dt->day_of_week;

    # start of that week
    my $sow = $dt - $dow;
    if ($sow->month != $mon) {
        $sow = $dt - ($day - 1);
    }
    $sow = $sow->as_d8();

    # end of that week
    my $eow = $dt + (6-$dow);
    if ($eow->month != $mon) {
        $eow = $dt + ($dt->days_in_month - $day);
    }
    $eow = $eow->as_d8();

    #
    # are there other already existing programs or rentals
    # beginning this same week?  We can't assume
    # that these events have gl numbers ascending from 1.
    # an event may have been deleted.
    #
    my $num = 1;
    my @programs = model($c, 'Program')->search({
        sdate => { between => [ $sow, $eow ] },
    });
    my @rentals = model($c, 'Rental')->search({
        sdate => { between => [ $sow, $eow ] },
    });
    my $max = 0;
    for my $e (@programs, @rentals) {
        my $digit = substr($e->glnum, 4, 1);
        if ($digit > $max) {
            $max = $digit;
        }
    }
    return sprintf "%d%02d%d%d", $dt->year % 10, $dt->month, $week, $max+1;
}

#
# See: http://en.wikipedia.org/wiki/E-mail_address
# This should be good enough for MMC.
#
sub valid_email {
    my ($s) = @_;
    return $s =~ m{[-a-zA-Z0-9.&'+=_]+\@[a-zA-Z0-9.\-]+};
}

# return only the digits
sub digits {
    my ($s) = @_;
    $s =~ s{\D}{}g;
    $s;
}

sub model {
    my ($c, $table) = @_;
    return $c->model("RetreatCenterDB::$table");
}

my $mail_sender;

sub email_letter {
    my ($c, %args) = @_;

    # check args for keys letter, subject, to, from???

    #
    # convert the HTML letter to text with lynx
    # ??? any way to do this without creating a tmp text file?
    # keeping it all in memory?
    #
    open my $lynx_dump, "|lynx -stdin -dump -width=95>/tmp/$$"
        or die "cannot open |lynx: $!\n";
    print {$lynx_dump} $args{html};
    close $lynx_dump;
    open my $text_in, "<", "/tmp/$$"
        or die "cannot open /tmp/$$: $!\n";
    my $text;
    {
        local $/;
        $text = <$text_in>;
        close $text_in;
        unlink "/tmp/$$";
    }
    if (! $mail_sender) {
        Lookup->init($c);
        $mail_sender = Mail::SendEasy->new(
            smtp => $lookup{smtp_server},
            user => $lookup{smtp_user},
            pass => $lookup{smtp_pass},
        )
    }
    my $status = $mail_sender->send(
        %args,
        msg => $text,
    );
    if (! $status) {
        # what to do about this???
        $c->log->info('mail error: ' . $mail_sender->error);
    }
}

sub lunch_table {
    my ($view, $lunches, $sdate, $edate) = @_;

    my @lunches = split //, $lunches;
    my $s = <<"EOH";
<table border=1 cellpadding=5 cellspacing=2>
<tr>
<td align=center>Sun</td>
<td align=center>Mon</td>
<td align=center>Tue</td>
<td align=center>Wed</td>
<td align=center>Thu</td>
<td align=center>Fri</td>
<td align=center>Sat</td>
</tr>
<tr>
EOH
    my $sdow = $sdate->day_of_week();
    my $ndays = $edate - $sdate + 1;
    my $dow = 0;
    while ($dow < $sdow) {
        $s .= "<td>&nbsp;</td>";
        ++$dow;
    }
    my $d = 0;
    my $cur = $sdate;
    while ($d < $ndays) {
        my $lunch = $lunches[$d];
        my $color = ($lunch && $view)? '#99FF99': '#FFFFFF';
        $s .= "<td align=left bgcolor=$color>" . $cur->day;
        if ($dow == 6) {
            ;                # no lunch on Saturday
        }
        elsif ($view) {
            my $w = $lunch? '': 'w';
            $s .= "<img src='/static/images/${w}checked.gif'>";
        }
        else {
            $s .= " <input type=checkbox name=d$d"
                . ($lunch? " checked": "")
                . ">";
        }
        $s .= "</td>";
        ++$cur;
        ++$dow;
        ++$d;
        if ($dow == 7) {
            $s .= "</tr>\n";
            if ($d < $ndays) {
                $s .= "<tr>\n";
            }
            $dow = 0;
        }
    }
    if ($dow > 0) {
        while ($dow <= 6) {
            $s .= "<td>&nbsp;</td>";
            ++$dow;
        }
    }
    $s .= "</tr></table>\n";
    $s;
}

my %lunch_cache;

sub clear_lunch {
    %lunch_cache = ();
}
sub get_lunch {
    my ($c, $id) = @_;

    if (! exists $lunch_cache{$id}) {
        my $prog = model($c, 'Program')->find($id);
        $lunch_cache{$id} = [ $prog->sdate_obj, $prog->lunches ];
    }
    return @{$lunch_cache{$id}};
}

#
# add a bunch of Config records
# so that we're ready for the future.
#
# $new_last_date is a string in d8 format
# OR a Date::Simple object.
#
# if we pass a $house object just add config
# records for that one house - otherwise all houses.
#
# in the one house case (a new house was added)
# begin adding from today() - otherwise add from
# when we last added a config record.
#
sub add_config {
    my ($c, $new_last_date, $house) = @_;

    if (! ref($new_last_date)) {
        $new_last_date = date($new_last_date);
    }
    my $last;
    my @houses;
    if ($house) {
        $last = today();
    }
    else {
        $last = date($lookup{sys_last_config_date});
        ++$last;
    }
    if ($last >= $new_last_date) {
        # we have just added a program or rental
        # that ends before an existing one.
        # so there is nothing to do.
        return;
    }

    if ($house) {
        push @houses, [ $house->id, $house->max ];
    }
    else {
        for my $h (model($c, 'House')->all()) {
            push @houses, [ $h->id, $h->max ];
        }
    }
    my $d8;
    while ($last <= $new_last_date) {
        $d8 = $last->as_d8();
        for my $h (@houses) {
            model($c, 'Config')->create({
                house_id   => $h->[0],
                the_date   => $d8,
                sex        => 'U',
                curmax     => $h->[1],
                cur        => 0,
                program_id => 0,
                rental_id  => 0,
            });
        }
        ++$last;
    }
    return if $d8 eq $lookup{sys_last_config_date};

    $lookup{sys_last_config_date} = $d8;
    model($c, 'String')->find('sys_last_config_date')->update({
        value => $d8,
    });
}

# economy and dormitory???
my %tmax = qw/
    single_bath 1
    single      1
    dble        2
    dble_bath   2
    triple      3
    quad        4
    dormitory   7
    economy    20
    center_tent 1
    own_tent    1
/;
sub type_max {
    my ($h_type) = @_;
    return $tmax{$h_type};
}

sub max_type {
    my ($max, $bath, $tent, $center) = @_;
    if ($max == 1) {
        if ($tent) {
            return ($center)? "center_tent"
                  :           "own_tent"
                  ;
        }
        else {
            return ($bath)? "single_bath"
                  :         "single"
                  ;
        }
    }
    elsif ($max == 2) {
            return ($bath)? "dble_bath"
                  :         "dble"
                  ;
    }
    elsif ($max == 3) {
        return "triple";
    }
    elsif ($max == 4) {
        return "quad";
    }
    elsif ($max <= 7) {
        return "dormitory";
    }
    else {
        return "economy";
    }
}

1;
