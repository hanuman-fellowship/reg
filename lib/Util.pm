use strict;
use warnings;

package Util;
use base 'Exporter';
our @EXPORT_OK = qw/
    affil_table
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
    type_max
    max_type
    lines
    _br
    normalize
    tt_today
    ceu_license
    show_ceu_license
    ceu_license_stash
    commify
    wintertime
    long_term_registration
    stash
    error
    payment_warning
    fillin_template
    ptrim
    gptrim
    mmi_glnum
    accpacc
    highlight
    other_reserved_cids
    PR_other_reserved_cids
    reserved_clusters
    palette
    esc_dquote
    invalid_amount
    get_grid_file
    avail_mps
    get_now
    penny
    avail_pic_num
    check_makeup_new
    check_makeup_vacate
    refresh_table
    d3_to_hex
    calc_mmi_glnum
    ensure_mmyy
    rand6
    randpass
    db_init
    digits_only
    add_or_update_deduping
    x_file_to_href
    phone_match
    outstanding_balance
    charges_and_payments_options
    @charge_type
    cf_expand
    PR_progtable
    months_calc
    new_event_alert
    JON
    strip_nl
    login_log
    no_comma
    time_travel_class
    too_far
/;
use POSIX   qw/ceil/;
use Date::Simple qw/
    d8
    date
    today
    days_in_month
/;
use Time::Simple qw/
    get_time
/;
use HLog;
use Template;
use Global qw/
    %string
/;
use Mail::Sender;
# no ping on new site :(
#use Net::Ping;
use Carp 'croak';
use Data::Dumper;

our @charge_type = (
    '',
    'Tuition',
    'Meals and Lodging',
    'Administration Fee',
    'Clinic Fee',
    'Other',
    'STRF',
    'Recordings',
    'CEU License Fee',
    'Materials Fees',
);

sub charges_and_payments_options {
    my ($selected) = @_;
    my $opts = "";
    for my $i (1 .. 9) {
        $opts .= "<option value=$i>$charge_type[$i]\n";
    }
    if ($selected) {
        $opts =~ s{=$selected}{=$selected selected}xms;
    }
    return $opts;
}

sub db_init {
    return RetreatCenterDB->connect($ENV{DBI_DSN}, "sahadev", "JonB");
}

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
           . "> "
           . $descrip
           . "</td>";
}


#
# get the affiliations table ready for the template.
# this was too hard to do within the template...
# which affils should be checked?
#
# the first parameter is the Catalyst context.
# the rest of the params are tricky - they are _either_ Afill objects
# OR integer affil ids.
#
sub affil_table {
    my ($c, $all, @to_check) = @_;
    %checked = map { (ref($_)? $_->id(): $_) => 'checked' } @to_check;

    my $bool = $all? undef
        :{ 
            -or => [
                system => { '!=' => 'yes' },
                selectable => 'yes',
            ],
        };
    @affils = model($c, 'Affil')->search(
        $bool,
        {
            order_by => 'descrip'
        },
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

    my $super = $c->check_user_roles('super_admin');

    join "\n",
    map {
        my $id = $_->id();
        my $checked = $checked{$id} || "";
          "<tr><td>"
        . "<input type=checkbox name=role$id $checked> "
        . $_->fullname
        . ' - '
        . $_->descr
        . "</td></tr>"
    }
    sort {
        $a->fullname cmp $b->fullname
    }
    grep {
        my $r = $_->role();
        ($r ne 'super_admin' && $r ne 'web_designer' && $r ne 'developer')
        || $super
    }
    model($c, 'Role')->all();
}

sub get_now {
    my ($c) = @_;

    return
        user_id  => $c->user->obj->id,
        the_date => tt_today($c)->as_d8(),
        time     => get_time()->t24()
        ;
    # we return an array of 6 values perfect
    # for passing to a DBI insert/update.
}

#
# type is 'meeting', 'breakout', 'dorm', or 'all'
#
sub places {
    my ($event, $type) = @_;

    $type ||= 'all';
    join ", ",
         map { $_->meeting_place->abbr }
         grep {
             $type eq 'all'
             || ($type eq 'meeting'  && ! $_->breakout && ! $_->dorm)
             || ($type eq 'breakout' && $_->breakout)
             || ($type eq 'dorm'     && $_->dorm)
         }
         $event->bookings;
}

my @leaders;
my $nleaders;

sub _leader_elem {
    my ($i) = @_;
    if ($i >= $nleaders) {
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
        my $checked = $checked{$id} || "";
        "<input type=checkbox name=lead$id $checked> $name$assistant"
    }
    sort {
        $a->[0] cmp $b->[0]
    }
    map {
        my $p = $_->person();
        [
            ( $_->just_first()? $p->first()
             :                  $p->last() . ", " . $p->first),
            $_->id(),
            $_->assistant
        ]
    }
    model($c, 'Leader')->all();
    $nleaders = @leaders;
    my $n = ceil($nleaders/3);
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

    my $in;
    if (! open $in, '<', $fname) {
        $fname = "root/static/templates/web/$fname.html";
        open $in, "<", $fname
            or die "cannot open $fname: $!\n";
    }
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
# rentals images are handled in a very special way
#
sub resize {
    my ($type, $id, $which) = @_;

    my $rst = "root/static/images";
    if ($type eq 'r') {
        # resize and crop centrally to 640x368
        system(
            "convert -resize 640x368^ -gravity center -crop 640x368+0+0 +repage"
          . " $rst/ro-$id.jpg $rst/r-$id.jpg"
        );
        # create the thumbnail
        system(
            "convert -scale 100x"
          . " $rst/r-$id.jpg $rst/rth-$id.jpg"
        );
        return;
    }
    if (!$which || $which eq "imgwidth") {
        system("convert -scale "
               . trim($string{imgwidth})
               . "x"
               . " $rst/${type}o-$id.jpg $rst/${type}th-$id.jpg"
        );
    }
    if (!$which || $which eq "big_imgwidth") {
        system("convert -scale "
               . trim($string{big_imgwidth})
               . "x"
               . " $rst/${type}o-$id.jpg $rst/${type}b-$id.jpg"
        );
    }
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

    $s ||= "";
    $s = trim($s);
    # Check for zip range validity
    if ($s =~ m{[^0-9, -]}) {
        return "Only digits, commas, spaces and hyphen allowed"
              ." in the zip range field.";
    }

    my @ranges = split m{\s*,\s*}, $s, -1;

    my $ranges_ref = [];
    for my $r (@ranges) {
        # Field must be either a zip range or a single zip
        if ($r =~ m/^(\d{5})\s*-\s*(\d{5})$/) {
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
    return 1 if $file =~ m{\A cal \d{6} }xms;
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
        if (length($e->glnum) >= 5) {
            my $digit = substr($e->glnum, 4, 1);
            if ('0' <= $digit && $digit <= '9' && $digit > $max) {
                $max = $digit;
            }
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
    return $s =~ m{^\s*[-a-zA-Z0-9._]+\@[-a-zA-Z0-9.]+\s*$};
}

# return only the digits
sub digits {
    my ($s) = @_;
    $s =~ s{\D}{}g;
    $s;
}

sub model {
    my ($ref, $table) = @_;

    if (ref $ref eq 'RetreatCenterDB') {
        return $ref->resultset($table);
    }
    else {
        return $ref->model("RetreatCenterDB::$table");
    }
}

my $mail_sender;

#
# must have to, from, subject and html in the %args.
# if $ENV{test_email} send it to that address instead of to and cc/bcc
# return a boolean - did it succeed?
#
sub email_letter {
    my ($c, %args) = @_;

    for my $k (qw/ to from subject html /) {
        if (! exists $args{$k}) {
            die "no $k in args for Util::email_letter\n";
        }
    }
    my @cc_bcc = ();
    if (exists $args{cc}) {
        push @cc_bcc, cc => $args{cc};
    }
    if (exists $args{bcc}) {
        push @cc_bcc, bcc => $args{bcc};
    }
    if ($ENV{test_email}) {
        $args{to} = $ENV{test_email};
        @cc_bcc = ();
    }
    open my $mlog, ">>", "mail.log";
    if (ref $args{to} eq 'ARRAY') {
        print {$mlog} localtime() . " @{$args{to}} - ";
    }
    else {
        print {$mlog} localtime() . " $args{to} - ";
    }
    if (@cc_bcc) {
        print {$mlog} " @cc_bcc - ";
    }
    if (! exists $args{which}) {
        $args{which} = $args{subject};
    }
    print {$mlog} "$args{which} - ";
    # no ping :(
    #my $p = Net::Ping->new();
    #if (!$p->ping("mountmadonna.org")) {
    #    print {$mlog} "no ping so just return\n";
    #    close $mlog;
    #    return;     # don't even try
    #}

    if (! ref $mail_sender) {
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
    }
    if (! ref $mail_sender) {
        print {$mlog} "could not create mail_sender\n";
        close $mlog;
        return;
    }
    my @fake_to;
    if ($args{fake_to}) {
        @fake_to = (fake_to => $args{fake_to});
    }
    if (! $mail_sender->Open({
        to       => $args{to},
        @fake_to,
        @cc_bcc,
        from     => $args{from},
        replyto  => ($args{replyto} || $args{from}),
        subject  => $args{subject},
        ctype    => $args{ctype}? $args{ctype}: "text/html",
        encoding => "7bit",
    })) {
        $mail_sender = undef;
        print {$mlog} "no Mail::Sender->Open $Mail::Sender::Error\n";
        close $mlog;
        return;
    }
    $mail_sender->SendLineEnc($args{html});
    if (! $mail_sender->Close()) {
        print {$mlog} "no Mail::Sender->Close $Mail::Sender::Error\n";
        close $mlog;
        $mail_sender = undef;
        return;
    }
    print {$mlog} "sent\n";
    close $mlog;
    if (@cc_bcc) {
        $mail_sender = undef;
        # need to recreate or else the cc/bcc people
        # will receive ALL email! :(
    }
    return 1;
}

sub lunch_table {
    my ($view, $lunches, $sdate, $edate, $start_time) = @_;

    my $one = get_time("1300");
    my @lunches = split //, ($lunches || "");
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
    my ($c, $id, $type) = @_;

    if (! exists $lunch_cache{$type}{$id}) {
        my $event = model($c, $type)->find($id);
        $lunch_cache{$type}{$id} = [ $event->sdate_obj, $event->lunches ];
    }
    return @{$lunch_cache{$type}{$id}};
}

my %tmax = qw/
    single_bath 1
    single      1
    dble        2
    dble_bath   2
    triple      3
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
    elsif ($max <= 7) {
        return "dormitory";
    }
    else {
        return "economy";
    }
}

sub lines {
    my ($s) = @_;

    return 0 if ! defined $s;
    my @items = $s =~ m{<(p|div|li)\b[^>]*>}gi;
    return scalar(@items);
}

#
# still needed with tinyMCE?
#
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
# SMITH-JOHNSON    => Smith-Johnson
# smith-johnson    => Smith-Johnson
# Mckenzie         => McKenzie
# mary jane-louise => Mary Jane-Louise
#
sub normalize {
    my ($s) = @_;
    if (! $s) {
        return "";
    }
    my $t = "";
    my @words = split m{[ ]}xms, $s;
    for my $w (@words) {
        $w = join '-',
             map { s{^Mc(.)}{Mc\u$1}; $_ }
             map { ucfirst lc }
             split m{-}, $w
             ;
    }
    return join ' ', @words;
}

sub tt_today {
    my ($c) = @_;    

    my ($s) = model($c, 'String')->search({ the_key => 'tt_today' });
    $s = $s->value();
    if (empty($s)) {
        return today();
    }
    my %date_for = $s =~ m{(\w+) \s+ (\d+/\d+/\d+)}xmsg;
    my $login = $c->user->username();
    if (! exists $date_for{$login}) {
        return today();
    }
    return date($date_for{$login});
}

sub time_travel_class {
    my ($c) = @_;
    return time_travel_class => ((today() != tt_today($c))? 'red': '');
}

sub ceu_license {
    my ($reg) = @_;

    show_ceu_license(ceu_license_stash($reg));
}

# given a stash of license info, generate the license.
#
sub show_ceu_license {
    my ($stash) = @_;

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
    return $html;
}

# given a Registration return the ceu_license stash
#
sub ceu_license_stash {
    my ($reg) = @_;

    my $person = $reg->person;
    my $program = $reg->program;
    my $lic = uc $reg->ceu_license;
	$lic =~ s{^\s*}{};
    my ($license, $has_completed, $provider);
	if ($lic =~ /^RN/) {
		$license  = "Registered Nurse License Number: $lic";
		$has_completed = "Has completed the following course work<br>". 
                               "for Continuing Education Credit:";
		$provider = "This Certificate must be retained by the ".
						  "licensee for a period of four years after ".
						  "the course ends.<br>".
		                  "Board of Registered Nursing, Provider #05557";
	}
	elsif ($lic =~ /COMP/i) {
		# extra space so it's the same size and spacing as the others
		$license  = "&nbsp;";
		$provider = "&nbsp;<br>&nbsp;";
		$has_completed = "Has completed the following course work:<br>".
							   "&nbsp;";
	}
	else {
		$license  = "License Number: $lic";
		$has_completed = "Has completed the following course work<br>".
                               "for Continuing Education Credit:";
		$provider = "This Certificate must be retained by the ".
						  "licensee for a period of four years after ".
						  "the course ends.<br>".
		                  "Board of Behavioral Sciences, Provider #PCE632";
	}
    my $sdate = $reg->date_start_obj();
    my $ps = $program->sdate_obj();
    if ($sdate < $ps) {
        # they came early
        #
        $sdate = $ps;
    }
    my $pe = $program->edate_obj() + $program->extradays();
    my $edate = $reg->date_end_obj();
    if ($edate > $pe) {
        # they stayed afterwards
        #
        $edate = $pe;
    }
    my $ndays = $edate - $sdate;
    my $hours = ($program->retreat() && $ndays == 4)? 18
               ##:($program->name =~ m{YTT}          )? 120
               :                                      $ndays*5
               ;
    my $date = $sdate->format("%B %e");
    if (   $sdate->month() == $edate->month() 
        && $sdate->year()  == $sdate->year() )
    {
        # February 4-6, 2005
        $date .= sprintf "-%d, %d",
                         $edate->day(),
                         $sdate->format("%Y");
    }
    elsif ($edate->year() == $sdate->year()) {
        # February 4 - March 6, 2005
        $date .= $edate->format(" - %B&nbsp;%e, %Y");
    }
    else {
        # December 31, 2005 - January 3, 2006
        $date .= sprintf ", %s - %s",
                         $sdate->format("%Y"),
                         $edate->format("%B %e, %Y");
    }
    return {
        name          => $person->first() . " " . $person->last(),
        topic         => $program->title(),
        date          => $date,
        instructor    => $program->leader_names(),
        license       => $license,
        has_completed => $has_completed,
        provider      => $provider,
        hours         => $hours . " (" . _spell($hours) . ")",
        program_director => $string{program_director},
    };
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
    $n = scalar reverse $n;
    return penny($n);
}

#
# the date is in d8 format perfect for comparison.
# we don't need the year
#
sub wintertime {
    my ($d) = @_;
    $d = substr($d, 4, 4);
    return ($d < $string{center_tent_start} || $string{center_tent_end} < $d);
}

#
# what Credentialed program is the person currently enrolled in?
#
# should this be a method in the Person data object instead???
#
sub long_term_registration {
    my ($c, $person_id) = @_;

    my @regs = model($c, 'Registration')->search(
        {
            person_id => $person_id,
            date_end  => { '>=' => tt_today($c)->as_d8() },
            cancelled => { '!=' => 'yes' },
        },
        {
            order_by => 'date_start asc',
        }
    );
    @regs = grep {
                $_->program->level->long_term()
            }
            @regs;
    if (! @regs) {
        return 0;
    }
    else {
        return $regs[0];
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
    my ($host) = @_;

    return "";
    my $person = $string{"$host\_reconciling"};
    if ($person) {
        return "Warning! \u$person is doing a reconciliation!";
    }
    return "";
}

sub fillin_template {
    my ($tt2, $stash) = @_;

    my $html = "";
    my $tt = Template->new({
        INTERPOLATE  => 1,
        INCLUDE_PATH => 'root/static/templates/',
        EVAL_PERL    => 0,
    });
    $tt->process(
        $tt2,     # template
        $stash,   # variables
        \$html,   # output
    );
    return $html;
}

#
# trim off unneeded trailing paragraphs inserted by tinyMCE
#
sub ptrim {
    my ($s) = @_;

    if (! defined $s) {
        return "";
    }
    $s =~ s{(<p>&nbsp;</p>\s*)+$}{}g;
    $s;
}

#
# remove all unneeded paragraphs inserted by tinyMCE
#
sub gptrim {
    my ($s) = @_;

    $s =~ s{<p>&nbsp;</p>\s*}{}g;
    $s =~ s{<p><br mce_bogus="1"></p>}{}g;
    $s;
}

#
# return a description of and a link to the MMI account having
# 'glnum' as its GL Number.  See the MMI testplan
# for a description of what the various digits of
# the GL Number mean.
#
# if we cannot find the glnum return a link
# that will dig deeper into the payments and reveal
# their source.  For this we pass the date range.
#
sub mmi_glnum {
    my ($c, $glnum, $start_d8, $end_d8) = @_;

    my $d1 = substr($glnum, 0, 1);
    my $purpose = ($d1 eq '1'? 'Tuition'
                  :$d1 eq '2'? 'Meals & Lodging'
                  :$d1 eq '3'? 'Application Fee'
                  :$d1 eq '4'? 'Registration Fee'
                  :            'Other');
    $purpose = " - $purpose";
    my $d6 = substr($glnum, 5, 1);
    # ??? needs work!!!
    if ($d6 =~ m{[DCM]} && length($glnum) == 6) {
        # d6 is D, C, or M - the kind of MMI program.
        # Diploma, Certificate, or Masters.
        #
        my $school = substr($glnum, 1, 1);
        my $year10 = substr($glnum, 2, 2);
        my $month  = substr($glnum, 4, 1);
        if ($month =~ m{[XYZ]}) {
            $month = 10 + ord($month) - ord('X');
                # the above works because X, Y, Z
                # are sequential in the ASCII table
        }
        my @progs = model($c, 'Program')->search({
            school_id => $school,       # ??? needs work!!!
            level_id  => $d6,           # ditto
        });
        for my $p (@progs) {
            my $sdate = $p->sdate_obj;
            if (($sdate->year() % 100) == $year10
                && $sdate->month() == $month
            ) {
                return ($p->name() . $purpose,
                        "/program/view/" . $p->id . "/3");
                # it is possible that we would get the wrong program.
                # e.g. what if in July 2109 there is an Ayurveda
                # Master's program like there was in July 2009.
                # don't worry about it.
            }
        }
        return ("Unknown - Click for List " . $purpose,
                "/finance/mmi_dig/$glnum/$start_d8/$end_d8");
    }
    else {
        # This is a payment for an auditor.
        # Digits in $glnum beyond the first are the glnum number
        # of an MMI Course.  Search for it.  It will
        # be there and it will be unique.  Right?
        #
        my @progs = model($c, 'Program')->search(
            {
                school_id => { '!=' => 1 },        # not MMC
                glnum     => substr($glnum, 1),
            },
        );
        if (@progs) {
            return ($progs[0]->name() . $purpose,
                    "/program/view/" . $progs[0]->id() . "/3");
        }
        else {
            return ("Unknown MMI DCM Course" . $purpose,
                    "/program/view/3");
        }
    }
}

sub accpacc {
    my ($gl) = @_;

    $gl =~ s{^(.)(.)(....?(.))$}
            {
                ((index('DCM', $4) >= 0)? "410"
                 :                        "420")
                . "$1-0$2-$3"
            }e;
    $gl;
}

sub highlight {
    my ($s) = @_;
    if (! defined $s) {
        return "";
    }
    return ($s =~ m{TBD|\?|\*}? "<span class=highlight>$s</span>"
            :                   $s                               );
}

sub other_reserved_cids {
    my ($c, $event) = @_;

    my $id    = $event->id();
    my $sdate = $event->sdate();
    my $edate = $event->edate();
    my $edate1 = (date($edate)-1)->as_d8();

    my @optp = ();
    my @optr = ();
    if ($event->event_type() eq 'program') {
        @optp = ('me.id' => { '!=' => $id });
    }
    else {
        @optr = (id => { '!=' => $id });
    }

    # ol = overlapping
    my @ol_prog_ids =
        map {
            $_->id()
        }
        model($c, 'Program')->search(
            {
                @optp,
                'level.long_term' => '',
                'me.name'    => { -not_like => '%personal%retreat%' },
                    # had to be 'me' not 'program'
                    # both program and level have a 'name' column
                sdate             => { '<' => $edate1 },     # and it overlaps
                edate             => { '>' => $sdate },      # with this program
            },
            {
                join => [qw/ level /],
            }
        );
    my @ol_rent_ids =
        map {
            $_->id()
        }
        model($c, 'Rental')->search({
            @optr,
            sdate => { '<' => $edate1 }, # it overlaps
            edate => { '>' => $sdate },  # with this rental
        });
    my @cids = ();
    if (@ol_prog_ids) {
        push @cids,
        map {
            $_->cluster_id() => 1
        }
        model($c, 'ProgramCluster')->search({
            program_id => { -in => \@ol_prog_ids },
        });
    }
    if (@ol_rent_ids) {
        push @cids,
        map {
            $_->cluster_id() => 1
        }
        model($c, 'RentalCluster')->search({
            rental_id  => { -in => \@ol_rent_ids },
        });
    }
    return @cids;
}

#
# could factor out common code with above sub???
# but don't do too much refactoring - terribly refactored
# code is quite unreadable and unmaintainable.
#
sub PR_other_reserved_cids {
    my ($c, $date_start, $date_end) = @_;

    # ol = overlapping
    my @ol_prog_ids =
        map {
            $_->id()
        }
        model($c, 'Program')->search(
            {
            'level.long_term' => '',
            'me.name'         => { -not_like => '%personal%retreat%' },
            sdate => { '<' => $date_end },       # and it overlaps
            edate => { '>' => $date_start },     # with this PR registration
            },
            {
                join => [qw/ level /],
            });
    my @ol_rent_ids =
        map {
            $_->id()
        }
        model($c, 'Rental')->search({
            sdate => { '<' => $date_end },       # it overlaps
            edate => { '>' => $date_start },     # with this PR registration
        });
    my @cids = ();
    if (@ol_prog_ids) {
        push @cids,
        map {
            $_->cluster_id() => 1
        }
        model($c, 'ProgramCluster')->search({
            program_id => { -in => \@ol_prog_ids },
        });
    }
    if (@ol_rent_ids) {
        push @cids,
        map {
            $_->cluster_id() => 1
        }
        model($c, 'RentalCluster')->search({
            rental_id  => { -in => \@ol_rent_ids },
        });
    }
    return @cids;
}

#
# Something tells me that reserved clusters could
# have been specified as a relationship in the Program model.
# This is a task for a future refactorer.
#
sub reserved_clusters {
    my ($c, $id, $type) = @_;
    return map {
               $_->cluster()
           }
           model($c, "${type}Cluster")->search(
               {
                   "${type}_id" => $id,
               },
               {
                   prefetch => 'cluster',
                   join     => 'cluster',
                   order_by => 'cluster.name',
               },
           );
}

sub palette {
    my $html = "<table style='margin-top: 6mm' border=1>\n";
    for my $y (1 .. 6) {
        $html .= "<tr>\n";
        for my $x (1 .. 6) {
            my $rgb = $string{"pal_$x$y\_color"};
            $html .= "<td class=square6"
                  .  " onclick='colorSet($rgb)'"
                  .  " style='background-color: rgb($rgb)'"
                  .  "></td>\n"
                  ;
        }
        $html .= "</tr>\n";
    }
    $html .= "</table>\n";
    return $html;
}

#
# escape double quotes - and dollar signs
#
sub esc_dquote {
    my ($s) = @_;

    if (! defined $s) {
        return '';
    }
    $s =~ s{"}{\\"}g;
    $s =~ s{\$}{\\\$}g;
    $s;
}

sub invalid_amount {
    my ($amt) = @_;
    return 1 if ! defined $amt;
    return $amt !~ m{^-?\d+([.]\d+)?$};
}

#
# any new changes are gotten by grab_new
#
sub get_grid_file {
    my ($code) = @_;

    return "root/static/grid/$code-data.txt";
}

#
# available meeting places with/without a zero disp_ord
# dates come as objects
#
sub avail_mps {
    my ($c, $sdate, $edate, $zero) = @_;

    my $edate1 = $edate->prev->as_d8();

    $sdate = $sdate->as_d8();
    $edate = $edate->as_d8();

    my @avail = ();
    my @param;
    if ($zero) {
        @param = (
             { disp_ord => 0 },
             { order_by => 'name' },
        );
    }
    else {
        @param = (
            { disp_ord => { '!=' => 0 } },
            { order_by => 'disp_ord' },
        );
    }
    MEETING_PLACE:
    for my $mp (model($c, 'MeetingPlace')->search(
                    @param,
                )
    ) {
        next MEETING_PLACE if $mp->name() eq 'No Where';      # no no
        my $id = $mp->id;
        # are there any bookings for this place that overlap
        # with this request?
        # some way to do this search without the meet_id
        # and cache the results???
        #
        my @bookings = model($c, 'Booking')->search({
                          meet_id => $id,
                          sdate => { '<' => $edate },
                          edate => { '>' => $sdate },
                       });
        next MEETING_PLACE if @bookings;
        #
        # so far so good
        # if this meeting place allows sleeping
        # is anyone sleeping there?
        #
        if ($mp->sleep_too()) {
            # find the house with the same name (abbreviation)
            # there must be one, yes?  yes.
            my ($house) = model($c, 'House')->search({
                              name => $mp->abbr(),
                          });
            my @config = model($c, 'Config')->search({
                             house_id => $house->id(),
                             cur      => { '>' => 0 },  # someone there
                             the_date => { 'between' => [ $sdate, $edate1 ] },
                                                        # on some day
                         });
            if (! @config) {
                push @avail, $mp;
            }
            next MEETING_PLACE;
        }
        push @avail, $mp;
    }
    return @avail;
}

sub penny {
    my ($amt) = @_;
    if (! defined $amt) {
        return "";
    }
    $amt =~ s{[.]00$}{};
    # for sqlite we need:
    if ($amt =~ m{[.]\d$}) {
        $amt .= "0";
    }
    $amt;
}

sub avail_pic_num {
    my ($type, $id) = @_;
    my $n = 1;
    while (-f "root/static/images/${type}o-$id-$n.jpg") {
        ++$n;
    }
    return $n;
}

# check the make up list and see
# if the given house is currently on it.  
# If it is will the new use of it on
# $sdate alter the 'date_needed'?
#
sub check_makeup_new {
    my ($c, $house_id, $sdate) = @_;

    my ($makeup) = model($c, 'MakeUp')->search({
        house_id => $house_id,
    });
    if ($makeup) {
        my $needed = $makeup->date_needed();
        if (empty($needed) || $needed > $sdate) {
            $makeup->update({
                date_needed => $sdate,
            });
        }
    }
}

# a house has been vacated.
# check the make_up list to see
# if this vacating act alters a date_needed.
#
sub check_makeup_vacate {
    my ($c, $house_id, $sdate) = @_;

    my ($makeup) = model($c, 'MakeUp')->search({
        house_id => $house_id,
    });
    if ($makeup && $makeup->date_needed() eq $sdate) {
        # it does.
        # so when is the next date this house is needed?
        # look at the Config records. we can trust them, right?
        #
        my @configs = model($c, 'Config')->search(
            {
                house_id => $house_id,
                the_date => { '>', $sdate },
                cur      => { '>', 0 },
            },
            {
                order_by => 'the_date',
            }
        );
        $makeup->update({
            date_needed => (@configs? $configs[0]->the_date()
                            :         ""),
        });
    }
}

# duplicated from lunch table
# DRY???
#
sub refresh_table {
    my ($view, $refresh, $sdate, $edate) = @_;

    my @refresh = split //, ($refresh || "");
    my $s = <<"EOH";
<table class=lunch border=1 cellpadding=5 cellspacing=2>
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
        my $refresh = $refresh[$d];
        my $color = ($refresh && $view)? '#99FF99': '#FFFFFF';
        $s .= "<td align=left bgcolor=$color>" . $cur->day;
        if ($view) {
            my $w = $refresh? '': 'w';
            $s .= "<img src='/static/images/${w}checked.gif' border=0>";
        }
        else {
            $s .= " <input type=checkbox name=d$d"
                . ($refresh? " checked": "")
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
    $s .= <<"EOH";
</tr></table>
EOH
    $s;
}

sub d3_to_hex {
    my ($d3) = @_;

    my ($r, $g, $b) = (0, 0, 0);
    if (defined $d3
        && $d3 =~ m{^\D*(\d+)\D+(\d+)\D+(\d+)\D*$}
    ) {
        $r = $1;
        $g = $2;
        $b = $3;
    }
    return sprintf("#%02x%02x%02x", $r, $g, $b);
}

#
# calculate a General Ledger number for an MMI payment
#
sub calc_mmi_glnum {
    my ($c, $person_id, $public, $for_what, $reg_program_glnum) = @_;

    my $glnum;
    my $lt_reg = long_term_registration($c, $person_id);
    if (! $public && ref($lt_reg)) {
        # this person is enrolled in a Credentialed program
        # perhaps more than one...
        #
        $glnum = $for_what . $lt_reg->program->level->glnum_suffix();
    }
    else {
        # this person is an auditor or a student in a stand alone program.
        # (OR they are enrolled in more than one Credentialed program! :( )
        #
        # we use the glnum of the program itself (plus 'for_what').
        #
        if ($for_what == 3 || $for_what == 4) {
            # shouldn't be allowed to happen
            return 'illegal';
        }
        $glnum = $for_what . $reg_program_glnum;
    }
    return $glnum;
}

sub ensure_mmyy {
    my ($name, $date) = @_;

    $name = trim($name);
    my $d_mm = $date->month;
    my $d_yy = $date->year % 100;
    my ($mm, $yy) = $name =~ m{(\d\d?)/(\d\d)}xms;
    if (!$mm || !$yy) {
        $name .= "  $d_mm/$d_yy";
    }
    elsif ($mm != $d_mm || $yy != $d_yy) {
        $name =~ s{\s*\d\d?/\d\d}{  $d_mm/$d_yy}xms;
    }
    return $name;
}

#
# 6 random letters
#
sub rand6 {
    my ($c) = @_;

    CODE_LOOP:
    while (1) {
        my $lets = '';
        $lets .= ('a' .. 'z')[rand 26] for 1 .. 6;
        if (my ($person) = model($c, 'Person')->search({
                               secure_code => $lets,
                           })
        ) {
            next CODE_LOOP;     # dup - try again
        }
        if (my ($rental) = model($c, 'Rental')->search({
                               grid_code => $lets,
                           })
        ) {
            next CODE_LOOP;     # dup - try again
        }
        return $lets;
    }
}

#
# a random password for temporary purposes
# we require that it is changed immediately.
#
sub randpass {
    my @lets = split '', 'abcdefghjkmnpqrstvwxz'
                         . uc 'abcdefghjkmnpqrstvwxz';
    my @digs = split '', '23456789';
    return 
        $lets[rand @lets]
      . $digs[rand @digs]
      . $lets[rand @lets]
      . $digs[rand @digs]
      ;
}

# return only the digits
sub digits_only {
    my ($s) = @_;
    if (! defined $s || $s !~ m{\S}xms) {
        return '';
    }
    $s =~ s{\D}{}xmsg;
    $s;
}

# look carefully at $href for the keys - normalize them
# several are required or else!
#
# match on first, last
# consider phone numbers, email for a further match
# input phone numbers: tel_cell, tel_work, tel_home
#     normalize them to ddd-ddd-dddd
#     they could match anything
#     these days we mostly just have cell, yes?
# there are two address lines - these days there's usually
#     just one street - given the long extendible line of a web form.
#
# update if we found a match otherwise add anew.
# check if anything has changed
# return a status 'added', 'updated', or 'no change'.
#
# if provided ensure the affil_id - or an array of such?
# return a person_id and a status of 'added' or 'updated'
#
# what about online reg - multiple phone #s???
# use this when doing a People > Add as well?
#     to avoid duplicates, yes?  YES.
# if you do an update recompute the akey
#
# opt_in ???    online reg is more sophisticated than the temple, yes???
# mlist (MMC/MMI) opt in???
# can pass e_mailings etc as '-1', '', or 'yes'
# -1 means don't change anything - or, if
# it is a new person make it '' (the default).
#
# control these things with %args:
#     affil_id
#     request_to_comment
#
# ??? inactive, deceased
# ??? multiple affils - pass an array OR a scalar
#
# there may be a request in the $href.
# if there is an $args{request_to_comment} put the request
# in the comment field of the person - otherwise ignore it.
# it'll be a comment for an online registration.
#
sub add_or_update_deduping {
    my ($c, $href, %args) = @_;

    # add temple_id to $href if it is missing.
    # it is only used for temple visitors
    $href->{temple_id} ||= 0;

    my @mailing_keys = qw/
        e_mailings
        snail_mailings
        share_mailings
    /;

    # validate the input parameters that are REQUIRED.
    # there will sometimes be several in the input that
    # are not used at all.
    my @needed = (qw/
        first
        last
        tel_home
        tel_cell
        tel_work
        addr1
        addr2
        city
        st_prov
        zip_post
        sex
        email
        temple_id
    /,
    @mailing_keys);

    # check that all required are present ...
    my @missing;
    for my $k (@needed) {
        if (! exists $href->{$k}) {
            push @missing, $k;        
        }
    }
    if (@missing) {
        croak "missing keys for Util::add_update_deduping: @missing";
        # yes, die.  this is a programming problem not user error.
    }
    # ensure the mailing keys are consistent
    # they should be either '', 'yes', or '-1' (which means don't change it).
    KEY:
    for my $k (@mailing_keys) {
        next KEY if $href->{$k} eq '-1';
        if ($href->{$k} eq '1') {
            $href->{$k} = 'yes';
        }
        elsif ($href->{$k} eq 'yes') {
            ;  # okay
        }
        else {
            $href->{$k} = '';
        }
    }
    # should the above be '' and 'yes' instead of 0 and 1???
    # look in the database.  they ARE booleans.

    # normalize first, last and phone numbers
    $href->{first} = normalize($href->{first});
    $href->{last} = normalize($href->{last});
    for my $phone (@{$href}{qw/ tel_cell tel_home tel_work/}) {
        my $tmp = $phone;
        $tmp =~ s{\D}{}xms;
        if ($tmp =~ s{\A(\d\d\d)(\d\d\d)(\d\d\d\d)\z}{$1-$2-$3}xms) {
            $phone = $tmp;  # this modifies the $href
        }
        else {
            # leave it be - it is likely an international number
            # that doesn't have 10 digits
        }
    }
    # get the digits only version of the phones
    my $cell = digits_only($href->{tel_cell});
    my $home = digits_only($href->{tel_home});
    my $work = digits_only($href->{tel_work});

    # a few other initializations
    my $akey = nsquish($href->{addr1}, $href->{addr2}, $href->{zip_post});
    $href->{akey} = $akey;
    if (exists $href->{country} && _is_usa($href->{country})) {
        $href->{country} = '';
    }
    my $today_d8 = today()->as_d8();

    my @people = model($c, 'Person')->search({
                     first => $href->{first},
                     last  => $href->{last},
                 });
    my ($person_id, $person, $status);
    for my $p (@people) {
        if (phone_match(digits_only($p->tel_cell),
                        digits_only($p->tel_home),
                        digits_only($p->tel_work),
                        $cell,
                        $home,
                        $work)
            ||
            $p->email eq $href->{email}
            ||
            ($p->temple_id || -1) == $href->{temple_id}
        ) {
            # a match - THIS is the person we're looking for.
            # they're already in our database.
            # update their information - their address may have changed.
            #
            for my $k (@mailing_keys) {
                if (! defined $href->{$k} || $href->{$k} eq '-1') {
                    # don't change what is already there...
                    delete $href->{$k} 
                }
            }
            # has anything changed at all?
            my ($same, $what) = _all_the_same($p, $href, \@needed);
            if ($same) {
                $status = 'no change';
            }
            else {
                # do the update
                $p->update({
                    map({ $_ => $href->{$_} } @needed, 'akey'),
                    date_updat => $today_d8,
                });
                $status = "updated: $what";
            }
            $person_id = $p->id;
            $person = $p;
        }
    }
    if (! $person_id) {
        # either no match on first/last
        # or didn't find a match of phone/email/temple_id.
        # so we add a new person.
        #
        my @comment;
        if ($args{request_to_comment}) {
            push @comment, comment => $href->{request};
        }
        $person = model($c, 'Person')->create({
            map({ $_ => $href->{$_} } @needed, 'akey'),
            @comment,
            id_sps      => 0,
            date_entrd  => $today_d8,
            date_updat  => $today_d8,
            temple_id   => $href->{temple_id},
            secure_code => rand6($c),
        });
        $person_id = $person->id;
        $status = 'added';
    }
    if (exists $args{affil_ids}) {
        # ensure the person has all of the affil_ids
        # we do not _remove_ affiliations here
        # this does not change $status
        my @affil_ids;
        if (ref $args{affil_ids} eq 'ARRAY') {
            @affil_ids = @{$args{affil_ids}};
        }
        else {
            @affil_ids = $args{affil_ids};
        }
        my %has_affil = map { $_->a_id => 1 }
                        model($c, 'AffilPerson')->search({
                            p_id => $person_id,
                         });
        AFFIL:
        for my $a_id (@affil_ids) {
            next AFFIL if $has_affil{$a_id};
            model($c, 'AffilPerson')->create({
                p_id => $person_id,
                a_id => $a_id,
            });
        }
    }
    return $person_id, $person, $status;
}

# given a person object and a hashref and an array of needed keys
# see if the needed key-values of the hashref exactly match
# what is in the object.
# if something changed return a description of it in the 2nd return value
sub _all_the_same {
    my ($p, $href, $needed_aref) = @_;
    KEY:
    for my $k (@$needed_aref) {
        next KEY if $k eq 'request' or $k eq 'opt_in';
        if ($href->{$k} ne $p->$k) {    # hash index, method call
            return 0, "$k: '$href->{$k}' != " . "'" . $p->$k . "'";
        }
    }
    return 1, "";
}

my %is_usa = map { $_ => 1 } (
    'unitedstates',
    'usa',
    'us',
    'usofa',
    'unitedstatesofamerica',

);
sub _is_usa {
    my ($country) = @_;
    $country =~ s{[. ]}{}xmsg;  # normalize
    return exists $is_usa{lc $country};
}

# we have 6 phone numbers.
# they are all digits unless they are empty.
# do any of the first 3 match any of the last 3?
# if this were written today we would not have
# home or work numbers - just cell.  this shows the
# long history of Reg going back to pre-cell days.
#
sub phone_match {
    my (@nums) = @_;
    for my $i (0 .. 2) {
        for my $j (3 .. 5) {
            if ($nums[$i] && $nums[$j] && $nums[$i] eq $nums[$j]) {
                return 1;
            }
        }
    }
    return 0;
}

# parse the typical file we get from authorize.
# return an href.
# rename fields as appropriate to make it ready for add_or_update_deduping.
sub x_file_to_href {
    my ($fname) = @_;
    my %hash;
    my $in;
    if (! open $in, '<', $fname) {
        print "could not open $fname: $!\n";
        return {};
    }
    while (my $line = <$in>) {
        chomp $line;
        my ($key, $value) = $line =~ m{\A \s* x_(\w+) \s* => \s* (.*) \z}xms;
        if ($key) {
            $hash{$key} = $value;
        }
        else {
            # a file might have reg_id => ...
        }
    }
    close $in;
    $hash{first} = delete $hash{fname};
    $hash{last}  = delete $hash{lname};
    $hash{addr1} = delete $hash{address};
    $hash{addr2} = '';
    $hash{st_prov} = delete $hash{state};
    $hash{zip_post} = delete $hash{zip};
    $hash{sex} = delete $hash{gender};
    $hash{sex} =   $hash{sex} eq       'Male'? 'M'
                 : $hash{sex} eq     'Female'? 'F'
                 : $hash{sex} eq 'Non-Binary'? 'X'  # mixed gender
                 :                             ''
                 ;
    if ($hash{phone} && ! exists $hash{tel_cell}) {
        $hash{tel_cell} = delete $hash{phone};
    }
    $hash{tel_home} = '' if ! exists $hash{tel_home};
    $hash{tel_work} = '' if ! exists $hash{tel_work};
    $hash{request} = "";
    my $i = 1;
    while (exists $hash{"request$i"}) {
        $hash{request} .= delete $hash{"request$i"};
        $hash{request} .= "\n";
        ++$i;
    }
    $hash{request} =~ s{\xa0}{ }xmsg;      # space out a stray non-ASCII char
                                           # don't know the source
    $hash{green_amount} ||= 0;      # in case it was not given
    return \%hash;
}

sub outstanding_balance {
    my ($c, $person) = @_;

    my $outstand_str = "";
    my $alert;
    my $today = tt_today($c);
    REG:
    for my $r ($person->registrations) {
        # skip registrations that were cancelled, that were
        # a long time ago, or are in the future.
        next REG if $r->cancelled();
        next REG if ($today - $r->date_end_obj) > 365*$string{nyears_forgiven};
        next REG if $r->date_start_obj >= $today;
        if ($r->balance != 0) {
            my $alert = $person->first() . " "
                      . "has an outstanding balance of "
                      . '$' . $r->balance()
                      . " in ". $r->program->name() . "."
                      ;
            $outstand_str = '<p><span style="background-color: red;">'
                          . 'Outstanding balance of $'
                          . $r->balance
                          . " in " . $r->program->name
                          . "</span></p><p>&nbsp;</p>";
            last REG;
        }
    }
    return $outstand_str, $alert;
}

sub cf_expand {
    my ($c, $s) = @_;
    return "" if ! defined $s;
    $s = etrim($s);
    return $s if empty($s);
    # ??? get these each time??? cache them!
    # certainly!  in Global.
    my %note;
    for my $cf (model($c, 'ConfNote')->all()) {
        $note{$cf->abbr()} = etrim($cf->expansion());
    }
    $s =~ s{<p>([^<]+)</p>}{'<p>' . ($note{$1} || $1) . '</p>'}gem;
    $s;
}

#
# generate a progtable for personal retreats
# write it to the given file.
#
# return currHC and nextHC and change_date
#
sub PR_progtable {
    my ($c, $fname) = @_;

    my $today = tt_today($c);
    my $fom = $today - $today->day() + 1;     # first of month
    my $fom_d8 = $fom->as_d8();
    #
    # find personal retreat programs now and in the future.
    # get the housing cost for today and for the first PR
    # in the future with a different housing cost.
    #
    # the only time this would not be correct is if
    # there are two price changes within a period of time
    # that someone would schedule a PR in advance.
    # e.g. today's cost is $40.  In four months it changes to $45.
    # in tens months it increases to $50.  today someone
    # comes along and schedules a PR for a year hence.
    # they would think the cost would be $45 whereas it is actually $50.
    # this might make them unhappy.
    #
    # the past schedule of increases is every 2 years.
    # If no one would schedule a PR more than 2 years in
    # advance this mechanism will be fine and no one will
    # be unhappy.  We should be okay.
    #
    my @PRs = model($c, 'Program')->search(
                  {
                      name  => { like => '%personal%retreat%' },
                      sdate => { '>=' => $fom_d8 },
                  },
                  {
                      order_by => 'sdate'
                  },
              );
    if (! @PRs) {
        die "No Personal Retreats are scheduled!";
    }
    my $currPR = shift @PRs;
    my $curr_hc_id = $currPR->housecost->id();
    my $currHC = $currPR->housecost();
    my $next_hc = 0;        # boolean
    my $nextHC;             # HousingCost
    my $sdate = 0;
    PR:
    for my $pr (@PRs) {
        if ($pr->housecost->id() != $curr_hc_id) {
            $next_hc = 1;
            $nextHC = $pr->housecost();
            $sdate = $pr->sdate();
            last PR;
        }
    }
    my $href = {
        title         => 'Personal Retreat',
        dates         => '',
        leader_names  => '',
        name          => 'Personal Retreat',
        canpol        => $currPR->cancellation_policy(),
        plink         => 'http://www.mountmadonna.org/personal',
        image1        => '',
        image2        => '',
        basicfull     => '0',
        ndays         => '0',
        fulldays      => '0',
        disc_pr       => $string{disc_pr},
        disc_pr_start => $string{disc_pr_start},
        disc_pr_end   => $string{disc_pr_end},
        footnotes     => '',
        do_not_compute_costs => '0',
        dncc_why      => '',
        next_hc       => $next_hc,
        next_date     => $sdate,
        type          => 'Per Day',
    };
    TYPE:
    for my $type (reverse housing_types(1)) {
        next TYPE if $type =~ m{^economy|dormitory|triple$};
        $href->{"basic $type"} = $currHC->$type;
        if ($next_hc) {
            $href->{"next $type"} = $nextHC->$type;
        }
    }
    open my $out, '>', $fname
        or die "cannot create $fname: $!\n";
    $Data::Dumper::Indent = 1;
    $Data::Dumper::Sortkeys = 1;
    print {$out} Dumper({ 0 => $href });
    close $out;
    return $currHC, $nextHC, $sdate;
}

# how many months are included from start to end inclusive?
sub months_calc {
    my ($start, $end) = @_;
    $start -= $start->day() - 1;       # move to the first of the month
    # move to the last day of the month
    $end += days_in_month($end->year(), $end->month()) - $end->day();
    return int(($end - $start)/31) + 1;
}

sub new_event_alert {
    my ($c, $mmc, $type, $name, $url) = @_;

    my $to = $mmc? $string{mmc_event_alert}: $string{mmi_event_alert};
    return unless $to =~ /\S/;
    email_letter($c,
        to      => $to,
        from    => "$string{from_title} <$string{from}>",
        subject => "ADDED: New $type: $name",
        html    => <<"EOH",
A new $type was added:<br>
Its name is:
<ul>
<a href=$url>$name</a>
</ul>
EOH
    );
}

# append to the file /tmp/jon with timestamp
# named 'JON' to make it easy to find these calls and remove them
sub JON {
    open my $out, '>>', '/tmp/jon';
    print {$out} scalar(localtime(time)), " @_\n";
    close $out;
}

sub strip_nl {
    my ($s) = @_;
    $s =~ s{\n}{}gxms;
    $s;
}

sub login_log {
    my ($username, $msg) = @_;
    return unless $username;
    if (open my $out, '>>', 'login.log') {
        print {$out} scalar(localtime), " $username - $msg\n";
        close $out;
    }
}

sub no_comma {
    my ($s) = @_;
    $s =~ s{,}{}xmsg;
    return $s;
}

#
# Is the end date of the program/rental/block
# beyond where we have config records?  I even add a 
# fudge factor of 30 days.
#
sub too_far {
    my ($c, $d8) = @_;
    my ($str) = model($c, 'String')->search({
                  the_key => 'sys_last_config_date',
              });
    my $last = $str->value;
    if (date($d8) + 30 > date($last)) {
        return "Sorry. The End Date "
             . date($d8)->format("%F")
             . " is too far in the future.<br>"
             . " The last date you can currently use for housing is "
             . date($last)->format("%F") . ".<br>"
             . " On the first of every month this is extended by one month."
             ;
    }
    else {
        return 0;
    }
}

1;
