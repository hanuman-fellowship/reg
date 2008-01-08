#!local/bin/perl -w
package Program;
use strict;
use Lookup;
use Exception qw/except/;
use Util qw/slurp expand monthyear/;

use Date::Simple;
use Image::Size qw/imgsize/;

my %field = map { $_, 1 } qw/
    pname footnotes desc subdesc sdate edate retreat tuition
    weburl num housing pres1 pres2 image
    webdesc brdesc prev next sbath econ quad
    extdays fulltuit colltot deposit
    linked template prognum canpol
/;

use Leader;
use Housing;
use Canpol;

my @programs;
my %first_of_month;
my $default_template = slurp "template";

sub template {
	my ($self) = @_;
	return ($self->{template})? 
		(slurp "templates/" . $self->{template}):
		$default_template;
}

sub title {
    my ($self) = @_;
    return ($self->leaders && $self->leaders !~ /staff/i)? $self->leaders
		  :                                                $self->{desc};
}
sub title_barnacles {
    my ($self) = @_;
	return (($self->leaders or $self->{subdesc})?
			   "":
			   $self->barnacles);
}
sub prog_dates_style {
    my ($self) = @_;
	return (($self->leaders or $self->{subdesc})?
			   "":
			   "style='vertical-align: bottom'");
}

sub subtitle {
    my ($self) = @_;
    if ($self->leaders && $self->leaders !~ /staff/i) {
        if ($self->{subdesc}) {
            $self->{desc} . " - " . $self->{subdesc};
        } else {
            $self->{desc};
        }
    } else {
        $self->{subdesc};
    }
}
sub subtitle_barnacles {
    my ($self) = @_;
	return (($self->leaders or $self->{subdesc})?
		       $self->barnacles:
		       "");
}

sub barnacles {
    my ($self) = @_;
    my $b = $self->{footnotes};
    $b =~ s/\+/&dagger;/g;
    $b =~ s/%/&sect;/g;
	$b = "<span class='barnacles'><sup>$b</sup></span>" if $b;
    $b;
}

sub webdesc_plus {
    my ($self) = @_;
    my $s = $self->{webdesc};
    my $barnacles = $self->{'footnotes'};
	if ($barnacles) {
		$s .= "<ul>\n";
		if ($barnacles =~ /\*\*/) {
			$s .= "<li>$lookup{'**'}\n";
		} elsif ($barnacles =~ /\*/) {
			$s .= "<li>$lookup{'*'}\n";
		}
		$s .= "<li>$lookup{'+'}\n" if $barnacles =~ /\+/;
		$s .= "<li>$lookup{'%'}\n" if $barnacles =~ /%/;
		$s .= "</ul>\n";
	}
    $s;
}

sub weburl {
    my ($self) = @_;
    my $url = $self->{'weburl'};
    return "" unless $url;
    return "<p>$lookup{'weburl'} <a href='http://$url' target='_blank'>$url</a>.";
}

sub month_calendar {
    my ($self) = @_;
    my $m = $self->{sdate}->month;
	my $cal = slurp "cal$m.tmp";
    $cal;
}

#
# generate HTML (yes :() for a fee table)
#
sub fee_table {
    my ($self) = @_;

    my $sdate = $self->{sdate};
    my $month = $sdate->month;
    my $edate = $self->{edate};
    my $extdays  = $self->{extdays};
    my $ndays = ($edate-$sdate) || 1;		# personal retreats exception
    my $fulldays = $ndays + $extdays;
    my $cols  = ($extdays)? 3: 2;
	my $pr    = $self->{pname} =~ /personal retreat/i;
	my $tent  = $self->{pname} =~ /tnt/i;

    my $fee_table = <<EOH;
<p>
<table>
EOH
	$fee_table .= <<EOH unless $self->{pname} eq "PERSONAL RETREATS";
<tr><th colspan=$cols>$lookup{heading}</th></tr>
<tr><td colspan=$cols>&nbsp;</td></tr>
EOH
    $fee_table .= "<tr><th align=left valign=bottom>$lookup{typehdr}</th>";
    if ($extdays) {
        $fee_table .= "<th align=right width=70>$ndays Days</th>".
                      "<th align=right width=70>$fulldays Days</th></tr>\n";
    } else {
        $fee_table .= "<th align=right>$lookup{costhdr}</th></tr>\n";
    }
    for my $t (Housing->types) {
        next if $t =~ /unknown/;
        next if $t =~ /economy/     and not $self->{econ};
        next if $t =~ /quad/        and not $self->{quad};
		next if $t =~ /single bath/ and not $self->{sbath};

        next if $t =~ /center tent/ and not (5 <= $month and $month <= 10)
									and not ($pr || $tent);
										# ok for PR's - we don't
										# know what month...
		next if $pr and $t =~ /triple|dorm/;
		my $cost = $self->_fees(0, $t);
		next unless $cost;		# this type of housing is not offered at all.
        $fee_table .= "<tr><td>$lookup{$t}</td>";
        $fee_table .= "<td align=right>$cost</td>\n";
        if ($extdays) {
            $fee_table .= "<td align=right>" .
             $self->_fees(1, $t) .
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
sub _fees {
    my ($self, $full, $type) = @_;

    $type =~ s/^\s*|\s*$//g;    # trim front and back
    die "illegal housing type: $type" unless Housing->valid($type);
    my $tuition = $self->{($full)? "fulltuit": "tuition"};
    my $housing = $self->{housing};
    my $ndays = ($self->{edate} - $self->{sdate}) || 1;
												# personal retreat exception
    $ndays += $self->{extdays} if $full;
    #
    # the 'housing' field is either 0 or 1-5 or 6-8
    # 0, 6-8 are per day costs
    # 1-5 are total costs
    #
    # there is a housing discount of 10% for programs of 7 days or longer
    # and a further housing discount of 10% MORE for programs 30 days or longer.
	#
	# what if there are extra days and 1 <= $housing <= 5?
	# this is as yet unanswered.
    #
    my $hcost = Housing->cost($housing, $type);
	unless (1 <= $housing and $housing <= 5) {
		$hcost = $ndays*$hcost;
		$hcost -= 0.10*$hcost  if $ndays >= 7;
		$hcost -= 0.10*$hcost  if $ndays >= 30;
		$hcost = int($hcost);
	}
	return 0 unless $hcost;		# don't offer this housing type if cost is zero
    return $tuition + $hcost;
}

sub firstprog_prevmonth {
    my ($self) = @_;
    my $sd = $self->{sdate};
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
    my $sd = $self->{sdate};
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

sub prevprog {
    my ($self) = @_;
    $self->{prev}->fname;
}

sub nextprog {
    my ($self) = @_;
    $self->{"next"}->fname;
}

sub fname {
    my ($self) = @_;

	# was it computed before?
	if (exists $self->{fname}) {
		print "already $self->{fname}\n";
		return $self->{fname}
	}
    my $sd = $self->{sdate};
    my $name =
		   substr($self->{pname},  0, 3) .
           "-" .
           $sd->month .
           "-" .
           $sd->day;
	if (-f "$name.html") {
		# one extra should be enough, yes?
		$name .= "a";
	}
	$name .= ".html";
	$name = "ul_$name" if not $self->{linked};  # ul = unlinked
	$self->{fname} = $name;
	system("touch $name");		# tricky!
			# we need the above or else the file will not
			# exist when we do the -f check above.
	$name;
}

sub cancellation_policy {
	my ($self) = @_;
	return expand(Canpol->policy($self->{canpol}));
}

#
# format sdate to edate in a nice way
#
sub dates {
    my ($self) = @_;

    my $sd = $self->{sdate};
    my $ed = $self->{edate};
    my $dates = $sd->format("%B %e") . "-";
    if ($ed->month == $sd->month) {
        $dates .= $ed->day;
    } else {
        $dates .= $ed->format("%B %e");
    }
    my $extra = $self->{extdays};
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

#
# need to mix case it
#
sub leaders {
    my ($self) = @_;
    my $leaders = "";
    if ($self->{pres1}) {
        my $l = Leader->get($self->{pres1});
		print $self->desc, " has no leader???\n"
			unless $l;
        $leaders .= $l->first . " " . $l->last;
    }
    if ($self->{pres2}) {
        my $l = Leader->get($self->{pres2});
        $leaders .= " and " if $leaders;
        $leaders .= $l->first . " " . $l->last;
    }
    $leaders;
}

sub leader_bio {
    my ($self) = @_;
    return "" unless $self->{pres1};
    my $bio = "<p>";
    if ($self->{pres1}) {
        my $l = Leader->get($self->{pres1});
        $bio .= $l->bio;
        my $email = $l->puemail;
        if ($email) {
            $bio .= "<p>$lookup{email1} " . $l->first . " " . $l->last .
                    " $lookup{email2} <a href='mailto:" . $email .
                    "'>$email</a>.";
        }
        my $url = $l->web;
        if ($url) {
            $bio .= "<p>$lookup{'weburl'} <a href='http://$url' target='_blank'>$url</a>.";
        }
    }
    if ($self->{pres2}) {
        my $l = Leader->get($self->{pres2});
        $bio .= "<p>" . $l->bio;
        my $email = $l->puemail;
        if ($email) {
            $bio .= "<p>$lookup{email1} " . $l->first . " " . $l->last .
                    " $lookup{email2} <a href='mailto:" . $email .
                    "'>$email</a>.";
        }
        my $url = $l->web;
        if ($url) {
            $bio .= "<p>$lookup{'weburl'} <a href='http://$url' target='_blank'>$url</a>.";
        }
    }
    $bio;
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

    my $full = $lookup{imgwidth} || 170;
    my $half = $full/2;

    my ($pic1, $pic2) = ("", "");
    if ($self->{pres1}) {
        my $l = Leader->get($self->{pres1});
        $pic1 = $l->image if $l->image;
    }
    if ($self->{pres2}) {
        my $l = Leader->get($self->{pres2});
        $pic2 = $l->image if $l->image;        # ??? what to do?
                                            # a table for them side by side?
    }
    if ($pic2 and not $pic1) {
        $pic1 = $pic2;
        $pic2 = "";
    }
	if ($self->{image}) {            # use program pic if present
		$pic1 = $self->{image};
		$pic2 = "";
	}
    return "" unless $pic1;          # no image at all

    my $pic_html;
    if ($pic2) {
        my $enlarge = 0;
        my $enlarge1 = "<td>&nbsp;</td>";
        my $pic1_html = "<img src='pics/$pic1' width=$half>";
        if (-f "pics/b-$pic1") {
            $pic1_html = gen_popup($pic1_html, $pic1);
            $enlarge1 =
                "<td class='click_enlarge'>$lookup{'click_enlarge'}</td>";
            $enlarge = 1;
        }
        my $pic2_html = "<img src='pics/$pic2' width=$half>";
        my $enlarge2 = "<td>&nbsp</td>";
        if (-f "pics/b-$pic2") {
            $pic2_html = gen_popup($pic2_html, $pic2);
            $enlarge2 =
                "<td class='click_enlarge'>$lookup{'click_enlarge'}</td>";
            $enlarge = 1;
        }
        my $enlarge_html = ($enlarge)? "<tr>$enlarge1$enlarge2</tr>": "";
        return <<EOH;
<TABLE cellspacing=0>
<TR><TD valign=bottom>$pic1_html</TD><TD valign=bottom>$pic2_html</TD></TR>
$enlarge_html
</TABLE>
EOH
    } else {
        $pic_html = "<img src='pics/$pic1' width=$full alt='".
					$self->leaders .
					"'>";
		if (-f "pics/b-$pic1") {
			$pic_html = "<table>" .
						gen_popup($pic_html, $pic1) .
			            "<tr><td class='click_enlarge'>".
						"$lookup{'click_enlarge'}</td></tr></table>";
		}
        return $pic_html;
    }
} 

sub gen_popup {
    my ($pic_html, $pic) = @_;
    my ($w, $h) = imgsize("pics/b-$pic");
    my $pw = $w + 80;
    my $ph = $h + 70;
    $pic_html = qq!<a target=_blank onclick='window.open("b-$pic.html","","width=$pw,height=$ph")'>$pic_html</a>!;
    my $fname = "b-$pic.html";
	open OUT, ">$fname" or die "cannot open $fname: $!\n";
	my $copy = slurp("popup");
	$copy =~ s#<!--\s*T\s+bigpic\s*-->#<img src="http://www.mountmadonna.org/staging/pics/b-$pic" width=$w height=$h border=0>#;
	print OUT $copy;
	close OUT;
    $pic_html;
}

sub init {
    open IN, "programs.tmp" or die "cannot open programs.tmp: $!\n";
    my %hash;
    my $prognum = 1;
    while (<IN>) {
        s/\cM\n//;
        my ($k, $v) = split /\t/;
        $v =~ s/^\s*|\s*$//g;
        if ($v eq "-") {
            $v = "";
            while (<IN>) {
                s/\cM\n//;
                last if $_ eq ".";
                $v .= "$_\n";
            }
        }
        if ($k =~ /date/) {
            my ($m, $d, $y) = split '/', $v;
			if ($m !~ /\S/) {
				$hash{$k} = Date::Simple->new(2099, 1, 1);	# never expires
				$hash{$k}++ if $k =~ /edate/;		# so it is one day
			} else {
				$hash{$k} = Date::Simple->new($y, $m, $d);
			}
        } else {
			$v = expand($v) if $k =~ /webdesc|brdesc/;
            $v =~ s#^\s*http://## if $k eq "weburl";    # remove any http://
            $hash{$k} = $v;
        }
        if ($k eq "colltot") {        # end marker - fragile!
            $hash{prognum} = $prognum++;
            push @programs, bless { %hash };
            %hash = ();
        }
    }
    close IN;
    #
    # ensure the programs are sorted by start date
	# and then end date
    #
    @programs = map $_->[2],
                sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] } 
                map { [ $_->{sdate}, $_->{edate}, $_ ] }
                @programs;
    #
    # go through the programs by start date
    # skipping the unlinked programs
    # and set the prev and next links.
    #
    my ($prev_prog);
    for my $p (grep { $_->{linked} } @programs) {
        $p->{prev}   = $prev_prog || $p;
        $prev_prog->{"next"} = $p;
        $prev_prog = $p;
    }
    # set the last program's next
    $prev_prog->{"next"} = $prev_prog;
    #
    # set the first of the month program hash
    # we go backwards through the programs
    # so the last one overwritten will be the first of the month!
    #
    for my $p (reverse @programs) {
        next unless $p->{linked};
        my $sd = $p->{sdate};
        $first_of_month{$sd->month . $sd->year} = $p;
    }
}

#
# go through the programs in ascending date order
# and create the monthly calendar files calX.html
# where X is the month number.
#
# skip the unlinked ones
#
sub gen_month_calendars {
    my $cur_month = 0;
    for my $p (grep { $_->{linked} } @programs) {
        my $m = $p->{sdate}->month;
        if ($m != $cur_month) {
            # finish the prior calendar file, if any
            if ($cur_month) {
                print CAL "</TABLE>\n";
                close CAL;
            }
            # start a new calendar file
            $cur_month = $m;
            open CAL, ">cal$m.tmp" or die "cannot open cal$m.tmp: $!\n";
            my $my = monthyear($p->sdate);
            print CAL <<EOH;
<TABLE class='caltable'>
<TBODY>
<TR><TD class="monthyear" colSpan=2>$my</TD></TR>
EOH
        }
        # the program info itself
        print CAL "<TR>\n<TD class='dates_tr'>",
                  $p->dates_tr, "</TD>",
                  "<TD class='title'><A href='",
                  $p->fname, "'>",
                  $p->title, 
                  "</A><BR><span class='subtitle'>",
                  except($p->pname, "subtitle") || $p->subtitle,
                  "</span></TD></TR>";
    }
    # finish the prior calendar file, if any
    if ($cur_month) {
        print CAL "</TABLE>\n";
        close CAL;
    }
}

sub programs {
    return @programs;
}

use vars '$AUTOLOAD';
sub AUTOLOAD {
    my ($self) = @_;
    $AUTOLOAD =~ s/.*:://;
    return if $AUTOLOAD eq "DESTROY";
    die "unknown program field: $AUTOLOAD\n"
        unless exists $field{$AUTOLOAD};
    return $self->{$AUTOLOAD};
}

init;
gen_month_calendars;		# for use in month_calendar()

1;
