use strict;
use warnings;
package RetreatCenterDB::Program;
use base qw/DBIx::Class/;

use lib "..";       # so can do perl -c

# Load required DBIC stuff
__PACKAGE__->load_components(qw/PK::Auto Core/);
# Set the table name
__PACKAGE__->table('program');
# Set columns in table
__PACKAGE__->add_columns(qw/
    id
    name
    title
    subtitle
    glnum
    housecost_id
    retreat
    sdate
    edate
    tuition
    confnote
    url
    webdesc
    brdesc
    webready
    image
    kayakalpa
    canpol_id
    extradays
    full_tuition
    deposit
    collect_total
    linked
    unlinked_dir
    ptemplate
    cl_template
    sbath
    quad
    economy
    footnotes
    reg_start
    reg_end
    prog_start
    prog_end
    reg_count
    lunches
    school
    level
    max
    notify_on_reg
    summary_id
/);
__PACKAGE__->set_primary_key(qw/id/);

# cancellation policy
__PACKAGE__->belongs_to(canpol => 'RetreatCenterDB::CanPol', 'canpol_id');
# housecost
__PACKAGE__->belongs_to(housecost => 'RetreatCenterDB::HouseCost',
                        'housecost_id');
# summary
__PACKAGE__->belongs_to('summary' => 'RetreatCenterDB::Summary', 'summary_id');
# affiliations
__PACKAGE__->has_many(affil_program => 'RetreatCenterDB::AffilProgram',
                      'p_id');
__PACKAGE__->many_to_many(affils => 'affil_program', 'affil',
                          { order_by => 'descrip' },
                         );
# registrations
__PACKAGE__->has_many(registrations => 'RetreatCenterDB::Registration',
                      'program_id');
        # ??? how to sort by person names?

# leaders
__PACKAGE__->has_many(leader_program => 'RetreatCenterDB::LeaderProgram',
                      'p_id');
__PACKAGE__->many_to_many(leaders => 'leader_program', 'leader',
                          { order_by => 'l_order' });

# exceptions - maybe
__PACKAGE__->has_many(exceptions => 'RetreatCenterDB::Exception', 'prog_id');

# bookings
__PACKAGE__->has_many(bookings => 'RetreatCenterDB::Booking', 'program_id');

#
# we really can't call $self->{field}
# but must call $self->field()
# or just $self->field;
#
# something about when it actually does populate the object...???
#

use Date::Simple qw/date today/;
use Util qw/
    slurp
    expand
    housing_types
    places
/;
use Global qw/%string/;
use Image::Size;
use File::Copy;

my $default_template = slurp("default");
my %first_of_month;

# do I really need $c passed in???
sub future_programs {
    my ($class, $c) = @_;
    my @programs = $c->model('RetreatCenterDB::Program')->search(
        {
            sdate    => { '>=',    today()->as_d8() },
            webready => 'yes',
        },
        { order_by => [ 'sdate', 'edate' ] },
    );
    #
    # go through the programs in order
    # skipping the unlinked programs
    # setting the prev and next links.
    # and assigning a sequential program number.
    # these are used in subsequent methods.
    #
    my ($prev_prog);
    for my $p (grep { $_->linked } @programs) {
        $p->{prev}   = $prev_prog || $p;
        $prev_prog->{"next"} = $p;
        $prev_prog = $p;
    }
    # set the last program's next
    $prev_prog->{"next"} = $prev_prog;

    #
    # set the first of the month program hash.
    # we go backwards through the programs
    # so the last one overwritten will be the first of the month!
    #
    for my $p (reverse @programs) {
        next unless $p->linked;
        my $sd = $p->sdate_obj;
        $first_of_month{$sd->month . $sd->year} = $p;
    }
    @programs;
}
sub web_addr {
    my ($self) = @_;

    my $dir = "http://$string{ftp_site}/";

    return ($self->linked)? "$dir$string{ftp_dir2}/" . $self->fname
          :                 $dir . $self->unlinked_dir             ;
}
#
# a few convenience methods to transform the contents
# of a table column into something easily viewable
# within a template...
#
# ??? memoize these date object creations
# they only happen once and are stored in the object hash ref itself.
#
sub sdate_obj {
    my ($self) = @_;
    date($self->sdate) || "";
}
sub edate_obj {
    my ($self) = @_;
    date($self->edate) || "";
}
sub link {
    my ($self) = @_;
    return "/program/view/" . $self->id;
}

sub webdesc_br {
    my ($self) = @_;
    my $webdesc = $self->webdesc;
    $webdesc =~ s{\r?\n}{<br>\n}g;
    $webdesc;
}
sub brdesc_br {
    my ($self) = @_;
    my $brdesc = $self->brdesc;
    $brdesc =~ s{\r?\n}{<br>\n}g;
    $brdesc;
}
sub confnote_br  {
    my ($self) = @_;
    my $confnote = $self->confnote;
    $confnote =~ s{\r?\n}{<br>\n}g;
    $confnote;
}
sub fname {
    my ($self) = @_;

	# was it computed before?
	if (exists $self->{fname}) {
		return $self->{fname}
	}
    my $sd = $self->sdate_obj;
    my $name =
		   substr($self->name,  0, 3) .
           "-" .
           $sd->month .
           "-" .
           $sd->day;
	if (-f "$name.html") {
		# one extra should be enough, yes?
		$name .= "a";
	}
	$name .= ".html";
    if (! $self->linked) {   # ul = unlinked
        $name = "ul_$name";
    }
	$self->{fname} = $name;
	system("touch gen_files/$name");		# tricky!
			# we need the above or else the file will not
			# exist when we do the -f check above.
            # ??? really?   isn't it created immediately after
            # getting it?
	$name;
}
sub template_src {
	my ($self) = @_;
	return ($self->ptemplate)?  slurp($self->ptemplate)
          :                     $default_template;
}

sub main_meeting_place {
    my ($self) = @_;
    my @bookings = grep { $_->breakout() eq 'yes' } $self->bookings();
    @bookings? $bookings[0]->meeting_place()->name()
    :          "";
}

sub title1 {
    my ($self) = @_;
    return ($self->leader_names && $self->leader_names !~ m{staff}i)?
                $self->leader_names:
                $self->title;
}
sub title2 {
    my ($self) = @_;
    if ($self->leader_names && $self->leader_names !~ m{staff}i) {
        if ($self->subtitle) {
            $self->title . " - " . $self->subtitle;
        } else {
            $self->title;
        }
    } else {
        $self->subtitle;
    }
}
sub barnacles {
    my ($self) = @_;
    my $b = $self->footnotes;
    $b =~ s/\+/&dagger;/g;
    $b =~ s/%/&sect;/g;
	$b = "<span class='barnacles'><sup>$b</sup></span>" if $b;
    $b;
}
sub title1_barnacles {
    my ($self) = @_;
	return (($self->leader_names or $self->subtitle)?
			   "":
			   $self->barnacles);
}
sub title2_barnacles {
    my ($self) = @_;
	return (($self->leader_names or $self->subtitle)?
		       $self->barnacles:
		       "");
}

sub leader_names {
    my ($self) = @_;
    if ($self->{leader_names}) {
        return $self->{leader_names};
    }
    my $s = "";
    my @leaders = map {
                      $_->person->first . " " . $_->person->last
                  }
                  sort {
                      $a->person->last  cmp $b->person->last or
                      $a->person->first cmp $b->person->first
                  }
                  $self->leaders;
    return "" unless @leaders;
    my $last = pop @leaders;
    $s .= join ", ", @leaders;
    $s .= " and " if $s;
    $s .= $last;
    $self->{leader_names} = $s;
}
#
# format sdate to edate in a nice way
#
sub dates {
    my ($self) = @_;

    my $sd = $self->sdate_obj;
    my $ed = $self->edate_obj;
    my $dates = $sd->format("%B %e") . "-";
    if ($ed->month == $sd->month) {
        $dates .= $ed->day;
    } else {
        $dates .= $ed->format("%B %e");
    }
    my $extra = $self->extradays;
    if ($extra) {
        $ed += $extra;
        if ($ed->month == $sd->month) {
            $dates .= ", " . $sd->day . "-";
            $dates .= $ed->day;
        } else {
            $dates .= ", " . $sd->format("%B %e") . "-";
            $dates .= $ed->format("%B %e");
        }
    }
    $dates;
}
#
#
#
sub dates3 {
    my ($self) = @_;
    my $s = $self->dates();
    $s =~ s{(\w+)}{substr($1, 0, 3)}eg;
    $s =~ s{\s\s+}{ }g;
    $s;
}
#
# same as dates - but without the initial month name
# and any subsequent month name truncated to 3 chars.
#
sub dates_tr {
    my ($self) = @_;
    my $dates = $self->dates;
    my ($init_month) = $dates =~ /^(\w+)/;
    $dates =~ s/$init_month\s*//g;
    $dates =~ s/(\w\w\w)\w+/$1/g;
    $dates =~ s/,\s*/<br>/g;
    $dates;
}
#
# same as dates_tr but without the 3 letter abbreviation
# and no transformation of , to <br>
#
sub dates_tr2 {
    my ($self) = @_;
    my $dates = $self->dates;
    my ($init_month) = $dates =~ /^(\w+)/;
    $dates =~ s/$init_month\s*//g;
    $dates;
}
sub prog_dates_style {
    my ($self) = @_;
	return (($self->leader_names or $self->subtitle)?
			   "":
			   "style='vertical-align: bottom'");
}
sub webdesc_plus {
    my ($self) = @_;
    my $s = expand($self->webdesc);
    my $barnacles = $self->footnotes;
	if ($barnacles) {
		$s .= "<ul>\n";
		if ($barnacles =~ /\*\*/) {
			$s .= "<li>$string{'**'}\n";
		} elsif ($barnacles =~ /\*/) {
			$s .= "<li>$string{'*'}\n";
		}
		$s .= "<li>$string{'+'}\n" if $barnacles =~ /\+/;
		$s .= "<li>$string{'%'}\n" if $barnacles =~ /%/;
		$s .= "</ul>\n";
	}
    $s;
}
sub weburl {
    my ($self) = @_;
    my $url = $self->url;
    return "" unless $url;
    return "<p>$string{weburl} <a href='http://$url' target='_blank'>$url</a>.";
}
#
# generate HTML (yes :() for a fee table)
#
sub fee_table {
    my ($self) = @_;

    my $sdate = $self->sdate_obj;
    my $month = $sdate->month;
    my $edate = $self->edate_obj;
    my $extradays  = $self->extradays;
    my $ndays = ($edate-$sdate) || 1;		# personal retreats exception
    my $fulldays = $ndays + $extradays;
    my $cols  = ($extradays)? 3: 2;
	my $pr    = $self->name =~ m{personal retreat}i;
	my $tent  = $self->name =~ m{tnt}i;

    my $fee_table = <<EOH;
<p>
<table>
EOH
	$fee_table .= <<EOH unless $self->name =~ m{personal retreat}i;
<tr><th colspan=$cols>$string{heading}</th></tr>
<tr><td colspan=$cols>&nbsp;</td></tr>
EOH
    $fee_table .= "<tr><th align=left valign=bottom>$string{typehdr}</th>";
    if ($extradays) {
        my $plural = ($ndays > 1)? "s": "";
        $fee_table .= "<th align=right width=70>$ndays Day$plural</th>".
                      "<th align=right width=70>$fulldays Days</th></tr>\n";
    } else {
        $fee_table .= "<th align=right>$string{costhdr}</th></tr>\n";
    }
    # hard coded column names - another way???
    # somehow get them from HouseCost.pm???
    for my $t (housing_types()) {
        next if $t =~ m{unknown};
        next if $t =~ m{economy}     && ! $self->economy;
        next if $t =~ m{quad}        && ! $self->quad;
		next if $t =~ m{single_bath} && ! $self->sbath;

        next if $t =~ m{center_tent} && ! (5 <= $month and $month <= 10)
									 && ! ($pr || $tent);
										# ok for PR's - we don't
										# know what month...
		next if $pr and $t =~ m{triple|dormitory};
		my $cost = $self->fees(0, $t);
		next unless $cost;		# this type of housing is not offered at all.
        $fee_table .= "<tr><td>$string{$t}</td>";
        $fee_table .= "<td align=right>$cost</td>\n";
        if ($extradays) {
            $fee_table .= "<td align=right>" .
             $self->fees(1, $t) .
             "</td>\n";
        }
        $fee_table .= "</tr>\n";
    }
    $fee_table .= "</table>\n";
    return $fee_table;
}

#
# fees for a given program, a given type and full/basic
#
sub fees {
    my ($self, $full, $type) = @_;

    $type =~ s{^\s*|\s*$}{}g;    # trim front and back
    my $tuition = $full? $self->full_tuition: $self->tuition;
    my $housecost = $self->housecost;
    my $ndays = ($self->edate_obj - $self->sdate_obj) || 1;
										# personal retreat exception
    $ndays += $self->extradays if $full;
    my $hcost = $housecost->$type;      # column name is correct, yes?
	if ($housecost->type eq "Perday") {
		$hcost = $ndays*$hcost;
		$hcost -= 0.10*$hcost  if $ndays >= 7;      # Strings???
		$hcost -= 0.10*$hcost  if $ndays >= 30;     # Strings???
		$hcost = int($hcost);
	}
	return 0 unless $hcost;		# don't offer this housing type if cost is zero
    return $tuition + $hcost;
}
sub firstprog_prevmonth {
    my ($self) = @_;
    my $sd = $self->sdate_obj;
    my $m = $sd->month;
    my $y = $sd->year;
	my $n = 0;
	while (1) {
		--$m;
		if ($m == 0) {
			$m = 12;
			--$y;
		}
		my $x = $first_of_month{"$m$y"};
		return $x->fname if $x;
		last if $n++ > 5;
	}
	return $self->fname;
}

sub firstprog_nextmonth {
    my ($self) = @_;
    my $sd = $self->sdate_obj;
    my $m = $sd->month;
    my $y = $sd->year;
	my $n = 0;
	while (1) {
		++$m;
		if ($m == 13) {
			$m = 1;
			++$y;
		}
    	my $x = $first_of_month{"$m$y"};
		return $x->fname if $x;
		last if $n++ > 5;
	}
	return $self->fname;
}
sub leader_bio {
    my ($self) = @_;
    my $bio = "";
    for my $l ($self->leaders) {
        $bio .= "<p>" . expand($l->biography);
        if (my $email = $l->public_email) {
            my $first = $l->person->first;
            my $last  = $l->person->last;
            $bio .= "<p>$string{email1} $first $last $string{email2}"
                   ." <a href='mailto:$email'>$email</a>";
        }
        if (my $url = $l->url) {
            $bio .= "<p>$string{weburl}"
                   ." <a href='http://$url' target='_blank'>$url</a>.";
        }
    }
    return $bio;
}
sub month_calendar {
    my ($self) = @_;
    my $m = $self->sdate_obj->month;
	my $cal = slurp "cal$m";
    $cal;
}
sub nextprog {
    my ($self) = @_;
    $self->{"next"}->fname;
}
sub prevprog {
    my ($self) = @_;
    $self->{prev}->fname;
}

#
# either the leader pic(s) or the program pic
# or nothing
# this is one place where we emit HTML :(
# not sure how to avoid this in the case where
# there IS no pic.
#
# what about clicking on the pic for a large one?
# open in new window easily closed, sized just right.
# have little note saying "click to enlarge"?
#
sub picture {
    my ($self) = @_;

    my $full = $string{imgwidth};
    my $half = $full/2;

    my @leaders = $self->leaders;
    my $nleaders = @leaders;
    # have an array of pictures instead???
    # which gets pushed onto?
    # and take the first two leaders that have images.
    my ($pic1, $pic2) = ("", "");
    if ($nleaders >= 1 && $leaders[0]->image) {
        $pic1 = "lth-" . $leaders[0]->id . ".jpg";
    }
    if ($nleaders >= 2 && $leaders[1]->image) {
        $pic2 = "lth-" . $leaders[1]->id . ".jpg";
    }
    if ($pic2 and ! $pic1) {
        $pic1 = $pic2;
        $pic2 = "";
    }
	if ($self->image) {  # use program pic if present
		$pic1 = "pth-" . $self->id . ".jpg";
		$pic2 = "";
	}
    return "" unless $pic1;          # no image at all

    # first copy the needed pictures to the 'holding area'
    for my $p ($pic1, $pic2) {
        next unless $p;
        if (! -f "root/static/images/$p") {
            $p =~ s{jpg}{gif};      # this modifies $pic1, $pic2
        }
        mkdir "gen_files/pics";
        copy("root/static/images/$p", "gen_files/pics/$p");
        my $big = $p;
        $big =~ s{th}{b};
        copy("root/static/images/$big", "gen_files/pics/$big");
    }
    if ($pic2) {
        my $pic1_html = "<img src='pics/$pic1' width=$half>";
        $pic1_html = gen_popup($pic1_html, $pic1);
        my $pic2_html = "<img src='pics/$pic2' width=$half>";
        $pic2_html = gen_popup($pic2_html, $pic2);
        return <<EOH;
<table cellspacing=0>
<tr><td valign=bottom>$pic1_html</td><td valign=bottom>$pic2_html</td></tr>
<tr><td align=center colspan=2 class='click_enlarge'>$string{'click_enlarge'}</td></tr>
</table>
EOH
    } else {
        my $pic_html = "<img src='pics/$pic1' width=$full>";
        $pic_html = "<table><tr><td>" .
					gen_popup($pic_html, $pic1) .
			        "</td></tr><tr><td align=center class='click_enlarge'>".
					"$string{click_enlarge}</td></tr></table>";
        return $pic_html;
    }
}
sub cl_picture {
    my ($self) = @_;

    my $full = $string{imgwidth};
    my $half = $full/2;

    my @leaders = $self->leaders;
    my $nleaders = @leaders;
    # have an array of pictures instead???
    # which gets pushed onto?
    # and take the first two leaders that have images.
    my ($pic1, $pic2) = ("", "");
    if ($nleaders >= 1 && $leaders[0]->image) {
        $pic1 = "lth-" . $leaders[0]->id . ".jpg";
    }
    if ($nleaders >= 2 && $leaders[1]->image) {
        $pic2 = "lth-" . $leaders[1]->id . ".jpg";
    }
    if ($pic2 and ! $pic1) {
        $pic1 = $pic2;
        $pic2 = "";
    }
	if ($self->image) {  # use program pic if present
		$pic1 = "pth-" . $self->id . ".jpg";
		$pic2 = "";
	}
    return "" unless $pic1;          # no image at all

    if ($pic2) {
                                                    #       live2
        my $pic1_html = "<img src='http://$string{ftp_site}/staging2/{pics/$pic1' width=$half>";
        my $pic2_html = "<img src='http://$string{ftp_site}/staging2/pics/$pic2' width=$half>";
        return <<EOH;
<table cellspacing=0>
<tr><td valign=bottom>$pic1_html</td><td valign=bottom>$pic2_html</td></tr>
</table>
EOH
    } else {
        return "<img src='http://$string{ftp_site}/staging2/pics/$pic1' width=$full>";
    }
}
sub cancellation_policy {
	my ($self) = @_;
	return expand($self->canpol->policy);
}
sub gen_popup {
    my ($pic_html, $pic) = @_;
    $pic =~ s{th}{b};
    my ($w, $h) = imgsize("gen_files/pics/$pic");
    my $pw = $w + 80;
    my $ph = $h + 70;
    $pic_html = qq!<a target=_blank onclick='window.open("$pic.html","","width=$pw,height=$ph")'>$pic_html</a>!;
    my $fname = "gen_files/$pic.html";
	open my $out, ">", $fname or die "cannot create $fname: $!\n";
	my $copy = slurp("popup");
    # used to have http://www.mountmadonna.org/staging/ in front
	$copy =~ s{<!--\s*T\s+bigpic\s*-->}{<img src="pics/$pic" width=$w height=$h border=0>};
	print {$out} $copy;
	close $out;
    $pic_html;
}

# class methods
sub current_date {
    my ($class) = @_;
    return today()->format("%B %e, %Y");
}
sub current_year {
    my ($class) = @_;
    return today()->year();
}

sub image_file {
    my ($self) = @_;
    my $path = "/static/images/pth-" . $self->id;
    (-f "root/$path.jpg")? "$path.jpg": "$path.gif";
}
sub count {
    my ($self) = @_;
    return scalar($self->reg_count);
}
sub meeting_places {
    my ($self) = @_;
    places($self);
}

1;
