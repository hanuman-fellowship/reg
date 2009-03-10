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
    etrim
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
    lines
    _br
    normalize
    tt_today
    ceu_license
    commify
    wintertime
    dcm_registration
    stash
    error
    payment_warning
/;
use POSIX   qw/ceil/;
use Date::Simple qw/
    d8
    date
    today
/;
use Time::Simple;
use Template;
use Global qw/
    %string
/;
use Mail::Sender;

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
# highlight those > max in red.   Can't eliminate them
# because breakout spaces don't need to respect the max.
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
#                    { max => { '>=', $max } },
    for my $mp (model($c, 'MeetingPlace')->search(
                    {},
                    { order_by => 'disp_ord' }
                )
    ) {
        my $id = $mp->id;
        if (! ($checked{$id} || $br_checked{$id})) {
            # this meeting place is not currently assigned to
            # the PRE in question.
            # are there any bookings for this place that overlap
            # with this request?
            # some way to do this search without the meet_id
            # and cache the results???   yes.
            my @bookings = model($c, 'Booking')->search({
                              meet_id => $id,
                              sdate => { '<' => $edate },
                              edate => { '>' => $sdate },
                           });
            next MEETING_PLACE if @bookings;
        }
        my $mp_max = $mp->max();
        my $color = ($mp_max < $max)? "red": "black";
        # it should be included in the table
        $table .= "<tr><td>"
                  . $mp->name
                  . "</td><td align=right>"
                  . "<span style='color: $color'>$mp_max</span"
                  . "</td>"
                  . "<td></td>"     # spacer
                  . "<td align=center>"
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
<td width=10></td>
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
    my ($event, $breakout) = @_;

    join ", ",
         map { $_->meeting_place->abbr }
         grep { $_->breakout() eq $breakout }
         $event->bookings;
}

my @leaders;
my $nleaders;

sub _leader_elem {
    my ($i) = @_;
    if ($i > $nleaders) {
        return "&nbsp;";
    }
    $leaders[$i];
}

#
# after $c the parameters
# are an array of leader objects
# that should be checked in the display.
#
sub leader_table {
    my ($c) = shift;

    my %checked = map { $_->id() => 'checked' } @_;

    @leaders =
    map {
        my $name = $_->[0];
        my $id = $_->[1];
        my $assistant = ($_->[2])? " * ": "";
        "<input type=checkbox name=lead$id $checked{$id}> $name$assistant"
    }
    sort {
        $a->[0] cmp $b->[0]
    }
    map {
        my $p = $_->person();
        [ $p->last() . ", " . $p->first, $_->id(), $_->assistant ]
    }
    model($c, 'Leader')->all();
    $nleaders = @leaders;
    my $n = ceil($nleaders)/3;
    my $rows = "";
    for my $i (0 .. $n-1) {
        $rows .= "<tr>";

        $rows .= "<td>" . _leader_elem($i)      . "</td>";
        $rows .= "<td>" . _leader_elem($i+$n)   . "</td>";
        $rows .= "<td>" . _leader_elem($i+2*$n) . "</td>";

        $rows .= "</tr>\n";
    }
    $rows;
}

#
# trim leading and trailing blanks off the parameter
# and return the result
#
sub trim {
    my ($s) = @_;

    return $s unless $s;
    $s =~ s{^\s*|\s*$}{}gm;
    $s;
}
# only trim ending space
sub etrim {
    my ($s) = @_;

    return $s unless $s;
    $s =~ s{[\r ]*$}{}gm;
    $s =~ s{\s*$}{};        # new lines at the very end
                            # they creep into a textarea for some reason
    $s;
}

#
# is the string empty?  i.e. only white space?
#
sub empty {
    my ($s) = @_;

    if (! defined $s) {
        return 1;
    }
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
    my ($addr1, $addr2, $zip) = @_;
    my $s = uc($addr1 . $addr2 . $zip);
    my $n = $s;
    $n =~ s{\D}{}g;
    $s =~ s{[^A-Z]}{}g;
    $s = substr($s, 0, 3);
    return ($n . $s); 
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
# __, ++, **, %%%, ~~ expansions into <u>, <i>, <b>, <a href=>, <a mailto>
# and #, - into lists
#
# the first _ needs to appear either after a non-word char
# or at the beginning of the line - in case an underscore
# is needed elsewhere - like in a web address.
#
sub expand {
	my ($v) = @_;
    $v =~ s{\r?\n}{\n}g;
	$v =~ s{(^|\W)_([^_]*?)\_}{$1<u>$2</u>}smg;
	$v =~ s{\*([^*]*?)\*}{<b>$1</b>}mg;
	$v =~ s{\+([^+]*?)\+}{<i>$1</i>}mg;
    $v =~ s{\^\^([^^]*)\^\^}{<span style="font-size: 20pt; font-weight: bold">$1</span>}mg;
    $v =~ s{\^([^^]*)\^}{<span style="font-size: 16pt;">$1</span>}mg;
    $v =~ s{\|([^|]*)\|:(#?\w+)}{<span style="background: $2;">$1</span>}mg;
    $v =~ s{\|([^|]*)\|}{<span style="background: yellow;">$1</span>}mg;
	$v =~ s{%([^%]*?)%([^%]*?)%}
           {
               my ($clickpoint, $link) = (trim($1), trim($2));
               $link =~ s{http://}{};   # string http:// if any
               "<a href='http://$link' target=_blank>$clickpoint</a>";
           }esg;
	$v =~ s{~\s*(\S+)\s*~}{<a href="mailto:$1">$1</a>}sg;
    $v =~ s{/\s*$}{<br>}mg;
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
    $out =~ s{\n\n}{<p>\n}g;      # last to not mess with the ending of lists.
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
        system("convert -scale $string{imgwidth}x"
              ." ${type}o-$id.jpg ${type}th-$id.jpg");
    }
    if (!$which || $which eq "big_imgwidth") {
        system("convert -scale $string{big_imgwidth}x"
              ." ${type}o-$id.jpg ${type}b-$id.jpg");
    }
    chdir "../../..";       # must cd back!   not stateless HTTP, exactly
}

sub housing_types {
    my ($extra) = @_;

    # types for which the field staff
    # will need to tidy up after:
    return qw/
		single_bath
		single
		dble_bath
		dble
		triple
		quad
		dormitory
		economy
		center_tent
		own_tent
    /,
    # optionally, the other types
    (($extra >= 1)? qw/ own_van commuting  /: ()),
    (($extra >= 2)? qw/ unknown not_needed /: ()),
    ;
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

#
# must have to, from, subject and html in the %args.
# check for it!???
#
sub email_letter {
    my ($c, %args) = @_;

    if (! $mail_sender) {
        Global->init($c);
        my @auth = ();
        if ($string{smtp_auth}) {
            @auth = (
                auth    => $string{smtp_auth},
                authid  => $string{smtp_user},
                authpwd => $string{smtp_pass},
            );
        }
        $mail_sender = Mail::Sender->new({
            smtp => $string{smtp_server},
            port => $string{smtp_port},
            @auth,
        });
        if (! $mail_sender) {
            # ???
        }
    }
    $mail_sender->Open({
        to       => $args{to},
        from     => $args{from},
        subject  => $args{subject},
        ctype    => "text/html",
        encoding => "7bit",
    })
        or die "no Mail::Sender->Open $Mail::Sender::error";
        # ??? better failure behavior?
    $mail_sender->SendLineEnc($args{html});
    $mail_sender->Close()
        or die "no Mail::Sender->Close $Mail::Sender::Error";
}

sub lunch_table {
    my ($view, $lunches, $sdate, $edate, $start_time) = @_;

    my $one = Time::Simple->new("1:00");
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
        #
        # no lunch on Saturday or on the
        # first day if they start on or after 1:00.
        #
        if ($dow == 6
            || ($d == 0 && $start_time >= $one)
        ) {
            ;
        }
        elsif ($view) {
            my $w = $lunch? '': 'w';
            $s .= "<img src='/static/images/${w}checked.gif' border=0>";
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
        $last = today();        # not tt_today()
    }
    else {
        $last = date($string{sys_last_config_date});
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
    return if $d8 eq $string{sys_last_config_date};

    $string{sys_last_config_date} = $d8;
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

sub lines {
    my ($s) = @_;
    $s =~ tr/\n/\n/;
}

sub _br {
    my ($s) = @_;
 
    if (! $s) {
        return $s; 
    }
    $s =~ s{\r?\n$}{};      # chop last
    $s =~ s{\r?\n}{<br>\n}g;   # internal newlines
    $s =~ s{^(\s+)}{"&nbsp;" x length($1)}emg;
    $s .= "<br>" if $s;
    $s;
}

#
# hyphenated names need an extra capital
# SMITH-JOHNSON => Smith-Johnson
# smith-johnson => Smith-Johnson
# Mckenzie      => McKenzie
#
sub normalize {
    my ($s) = @_;
    join '-',
         map { s{^Mc(.)}{Mc\u$1}; $_ }
         map { ucfirst lc }
         split m{-}, $s;
}

sub tt_today {
    my ($c) = @_;    

    my $s = $string{tt_today};
    if (! $s) {
        return today();
    }
    my $login = $c->user->username();
    my ($user, $dt) = split m{\s+}, $string{tt_today};
    $dt = date($dt);
    return ($user eq $login && $dt)? $dt: today();
}

# given a Registration return the ceu_license
sub ceu_license {
    my ($reg, $override_hours) = @_;
    my $person = $reg->person;
    my $program = $reg->program;
    my $lic = uc $reg->ceu_license;
	$lic =~ s{^\s*}{};
    my ($license, $has_completed, $provider);
	if ($lic =~ /^RN/) {
		$license  = "Registered Nurse License Number: $lic<br>";
		$has_completed = "Has completed the following course work<br>". 
                               "for Continuing Education Credit:";
		$provider = "This Certificate must be retained by the ".
						  "licensee for a period of four years after ".
						  "the course ends.<br>".
		                  "Board of Registered Nursing, Provider #05557";
	}
	elsif ($lic =~ /COMP/i) {
		# extra space so it's the same size and spacing as the others
		$license  = "&nbsp;<br>";
		$provider = "&nbsp;<br>&nbsp;";
		$has_completed = "Has completed the following course work:<br>".
							   "&nbsp;";
	}
	else {
		$license  = "License Number: $lic<br>";
		$has_completed = "Has completed the following course work<br>".
                               "for Continuing Education Credit:";
		$provider = "This Certificate must be retained by the ".
						  "licensee for a period of four years after ".
						  "the course ends.<br>".
		                  "Board of Behavioral Sciences, Provider #PCE632";
	}
    my $ndays = $program->edate - $program->sdate;
    my $hours = ($program->retreat && $ndays == 4)? 18
               :($program->name =~ m{YTT}        )? 120
               :                                    $ndays*5
               ;
    if ($override_hours) {
        $hours = $override_hours;
    }
    my $sdate = $program->sdate_obj;
    my $edate = $program->edate_obj;
    my $date = $sdate->format("%B %e");
    if (   $sdate->month == $edate->month 
        && $sdate->year  == $sdate->year )
    {
        # February 4-6, 2005
        $date .= sprintf "-%d, %d",
                         $edate->day,
                         $sdate->format("%Y");
    }
    elsif ($edate->year == $sdate->year) {
        # February 4 - March 6, 2005
        $date .= $edate->format(" - %B&nbsp;%e, %Y");
    }
    else {
        # December 31, 2005 - January 3, 2006
        $date .= sprintf ", %s - %s",
                         $sdate->format("%Y"),
                         $edate->format("%B %e, %Y");
    }
    my $stash = {
        name          => $person->first . " " . $person->last,
        topic         => $program->title,
        date          => $date,
        instructor    => $program->leader_names,
        license       => $license,
        has_completed => $has_completed,
        provider      => $provider,
        hours         => $hours . " (" . _spell($hours) . ")",
    };
    my $html = "";
    my $tt = Template->new({
        INCLUDE_PATH => 'root/src/registration',
        EVAL_PERL    => 0,
    }) or die Template->error();
    $tt->process(
        "ceu.tt2",   # template
        $stash,      # variables
        \$html,      # output
    ) or die $tt->error();
    $html;
}

#
# spell out a number in words
# < 1000, please.
#
sub _spell {
	my ($x) = @_;
	my %ones = (
		1 => "One",
		2 => "Two",
		3 => "Three",
		4 => "Four",
		5 => "Five",
		6 => "Six",
		7 => "Seven",
		8 => "Eight",
		9 => "Nine",
		10 => "Ten",
		11 => "Eleven",
		12 => "Twelve",
		13 => "Thirteen",
		14 => "Fourteen",
		15 => "Fifteen",
		16 => "Sixteen",
		17 => "Seventeen",
		18 => "Eighteen",
		19 => "Nineteen",
	);
	my $sp = "";
	if ($x >= 100) {
        my $h = 100*int($x/100);
		$x -= $h;
		$sp = "$ones{$h/100} Hundred";
		if ($x > 0) {
			$sp .= " and ";
		}
	}
	if ($x > 19) {
		my $tens = int($x/10)*10;
		$x %= 10;
		my %tens = (
			20 => "Twenty",
			30 => "Thirty",
			40 => "Forty",
			50 => "Fifty",
			60 => "Sixty",
			70 => "Seventy",
			80 => "Eighty",
			90 => "Ninety",
		);
		$sp .= "$tens{$tens}";
		if ($x > 0) {
			$sp .= q{ };
		}
	}
	if ($x > 0) {
		$sp .= $ones{$x}
	}
	return $sp;
}

sub commify {
    my ($n) = @_;
    $n = reverse $n;
    $n =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
    return scalar reverse $n;
}

sub wintertime {
    my ($mon) = @_;
    return(11 <= $mon || $mon <= 4);
}

#
# can use a prefetch/join to help further with this...???
# to add another search condition
#
# should this be a method in the Person data object instead???
#
sub dcm_registration {
    my ($c, $person_id) = @_;

    my @regs = model($c, 'Registration')->search(
        {
            person_id => $person_id,
        },
        {
            prefetch => [qw/program/],
        }
    );
    @regs = grep {
                $_->program->level() =~ m{[DCM]}
            }
            @regs;
    if (@regs == 1) {
        return $regs[0];
    }
    elsif (! @regs) {
        return 0;
    }
    else {
        return scalar(@regs);
    }
}

#sub stash {
#    my ($c, %args) = @_;
#
#    for my $k (keys %args) {
#        $c->stash->{$k} = $args{$k};
#    }
#}

# equivalent and likely more efficient:
sub stash {
    my $st_ref = shift->stash;
    for (my $i = 0; $i < @_; $i += 2) {
        $st_ref->{$_[$i]} = $_[$i+1];
    }
}

sub error {
    my $st_ref = shift->stash;
    $st_ref->{mess}     = shift;
    $st_ref->{template} = shift;
}

sub payment_warning {
    my ($c) = @_;

    if ($string{reconciling}) {
        return "Warning! \u$string{reconciling} is doing a reconciliation!";
    }
    if (tt_today($c)->as_d8() eq $string{last_deposit_date}) {
        return "This payment will be posted tomorrow<br>"
             . "since a deposit has already been done today.";
    }
    return "";
}

1;
