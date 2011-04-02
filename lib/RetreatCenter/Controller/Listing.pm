use strict;
use warnings;
package RetreatCenter::Controller::Listing;
use base 'Catalyst::Controller';

use Person;
use Util qw/
    valid_email
    model
    clear_lunch
    get_lunch
    trim
    tt_today
    commify
    housing_types
    stash
    error
    normalize
    affil_table
    empty
    nsquish
/;
use Date::Simple qw/
    date
    today
    days_in_month
/;
use DateRange;
use Global qw/
    %string
/;

sub index : Local {
    my ($self, $c) = @_;

    my $today = today();
    my $from = $today->format("%D");
    my $to   = (today()+6*30)->format("%D");
    stash($c,
        gc_from  => $from,
        gc_to    => $to,
        ow_from  => $from,
        ow_to    => $to,
        template => "listing/index.tt2",
    );
}

#
# better way to do this the DBIx::Class way???
# must be a way.  join, prefetch.
# no inactive people please???
#
sub _phone_list {
    my @people = @{ Person->search(<<"EOS") };
select p.*
  from people p, affil_people ap, affils a
 where a.descrip like '%phone list%'
       and ap.a_id = a.id
       and ap.p_id = p.id
       and p.inactive != 'yes'
EOS
    # if no sanskrit name take the first name
    # ??? okay poking inside object?   not really.
    for my $p (@people) {
        if (!$p->{sanskrit}) {
            $p->{sanskrit} = $p->{first};
        }
    }
    # sort by sanskrit name
    @people = sort {
                  $a->{sanskrit} cmp $b->{sanskrit};
              }
              @people;
    return @people;
}

#
# in columns
#
sub phone_columns : Local {
    my ($self, $c) = @_;

    my @people = _phone_list();
    open my $ph, ">", "root/static/phone_columns.html"
        or die "cannot create phone_columns.html";
    print {$ph} <<"EOH";
<html>
<head>
<link rel="stylesheet" type="text/css" href="phone_columns.css" />
</head>
<body>
<span class=fl_heading>Hanuman Fellowship Phone List</span>
<table>
<tr class=fl_th>
    <th align=left>Sanskrit</th>
    <th align=left>Name</th>
    <th align=center>Home</th>
    <th align=center>Work</th>
    <th align=left>&nbsp;&nbsp;Address</th>
</tr>
EOH
    my $class = 1;
    my $address;
    for my $p (@people) {
        $address = $p->address();      # method call
        print {$ph} <<"EOH";
<tr class=fl_row$class>
    <td class=fl_name>$p->{sanskrit}</td>
    <td class=fl_name>$p->{first} $p->{last}</td>
    <td class=fl_phone>&nbsp;&nbsp;$p->{tel_home}</td>
    <td class=fl_phone>&nbsp;&nbsp;$p->{tel_work}</td>
    <td class=fl_address>&nbsp;&nbsp;$address</td>
</tr>
EOH
        $class = 1-$class;
    }
    print {$ph} <<"EOH";
</table>
</body>
</html>
EOH
    $c->response->redirect($c->uri_for("/static/phone_columns.html"));
}

#
# no addr
#
sub phone_noaddr : Local {
    my ($self, $c) = @_;

    my @people = _phone_list();
    open my $ph, ">", "root/static/phone_noaddr.html"
        or die "cannot create phone_noaddr.html";
    print {$ph} <<"EOH";
<html>
<head>
<link rel="stylesheet" type="text/css" href="phone_noaddr.css" />
</head>
<body>
<span class=fl_heading>Hanuman Fellowship Phone List</span>
<table>
<tr class=fl_th>
    <th align=left>Sanskrit</th>
    <th align=left>Name</th>
    <th align=center>Home</th>
    <th align=center>Work</th>
    <th align=center>Cell</th>
</tr>
EOH
    my $class = 1;
    for my $p (@people) {
        print {$ph} <<"EOH";
<tr class=fl_row$class>
    <td class=fl_name>$p->{sanskrit}</td>
    <td class=fl_name>$p->{first} $p->{last}</td>
    <td class=fl_phone>&nbsp;&nbsp;$p->{tel_home}</td>
    <td class=fl_phone>&nbsp;&nbsp;$p->{tel_work}</td>
    <td class=fl_phone>&nbsp;&nbsp;$p->{tel_cell}</td>
</tr>
EOH
        $class = 1-$class;
    }
print {$ph} <<"EOH";
</table>
</body>
</html>
EOH
    $c->response->redirect($c->uri_for("/static/phone_noaddr.html"));
}

sub _tel_get {
    my ($fone, $let) = @_;
    $fone .= " $let " if $let && $fone;
    return $fone;
}
#
# in one line
#
sub phone_line : Local {
    my ($self, $c) = @_;

    open my $ph, ">", "root/static/phone_line.html"
        or die "cannot create phone_line.html";
    print {$ph} <<"EOH";
<html>
<head>
<link rel="stylesheet" type="text/css" href="phone_line.css" />
</head>
<body>
<span class=heading>Hanuman Fellowship Phone List</span>
EOH
    my @people = _phone_list();
    for my $p (@people) {
        my $fones = _tel_get($p->{tel_home}, 'h')
                  . _tel_get($p->{tel_work}, 'w')
                  . _tel_get($p->{tel_cell}, 'c');
        chop $fones;    # final space
        $fones =~ s{ [hwc]$}{} if length($fones) <= 14;
        my $addr = $p->address();
        print {$ph} <<"EOH";
<span class='person'>
<span class='sanskrit'>$p->{sanskrit}</span>
<span class='name'>$p->{first} $p->{last}</span>
<span class='phones'>$fones</span>
<span class='address'>$addr</span>
</span>
EOH
    }
print {$ph} <<"EOH";
</body>
</html>
EOH
    $c->response->redirect($c->uri_for("/static/phone_line.html"));
}

sub undup : Local {
    my ($self, $c) = @_;

    my $fname = "root/static/undup.html";
    open my $out, ">", $fname
        or die "cannot create $fname: $!\n";
    print {$out} "<pre>\n";
    #
    # name dup
    # need both addresses as well???
    #
    my $sth = Person->search_start(<<"EOS");
select last, first, id
  from people
order by last, first
EOS
    my $n_same_name = 0;
    my $n_people = 0;
    my ($prev_last, $prev_first, $prev_id) = ("", "", 0);
    my ($last, $first, $id);
    my $p;
    print {$out} "Same Last, First Names\n";
    print {$out} "======================\n";
    while ($p = Person->search_next($sth)) {
        ++$n_people;
        $last  = $p->{last};
        $first = $p->{first};
        $id    = $p->{id};
        if ($last eq $prev_last && $first eq $prev_first) {
            print {$out} "<a target=other href='/person/undup/$id-$prev_id'>"
                        ."$last, $first</a>\n";    
            ++$n_same_name;
        }
        $prev_last  = $last;
        $prev_first = $first;
        $prev_id    = $id;
    }
    $sth->finish();
    #
    # address dup
    #
    my $n_addr_dup = 0;
    $sth = Person->search_start(<<"EOS");
select *
  from people
 where akey != ''
order by akey
EOS
    my ($prev);
    print {$out} "\n\n";
    print {$out} "Similar Address (and not partnered)\n";
    print {$out} "===============\n";
    while ($p = Person->search_next($sth)) {
        if ($prev
            && $p->{akey} eq $prev->{akey}
            && ($p->{id_sps} == 0 || $prev->{id_sps} == 0)
        ) {
            print {$out} "<a target=other href='/person/undup_akey/$p->{akey}'>$p->{last}, $p->{first}</a>\n";    
            if ($p->{addr1} ne $prev->{addr1} 
                ||
                $p->{zip_post} ne $prev->{zip_post}
            ) {
                print {$out} "    $p->{addr1} $p->{zip_post}\n";
            }
            print {$out} "<a target=other href='/person/undup_akey/$prev->{akey}'>$prev->{last}, $prev->{first}</a>\n";    
            print {$out} "    $prev->{addr1} $prev->{zip_post}\n";
            print {$out} "\n";
            ++$n_addr_dup;
        }
        $prev = $p;
    }
    #
    # unreported gender
    #
    my $n_no_gender = 0;
    $sth = Person->search_start(<<"EOS");
select id, last, first
  from people
 where sex != 'M' and sex != 'F'
order by last, first
EOS
    print {$out} "\n\n";
    print {$out} "Unreported Gender\n";
    print {$out} "=================\n";
    while ($p = Person->search_next($sth)) {
        print {$out} "<a target=other href='/person/view/$p->{id}'>$p->{last}, $p->{first}</a>\n";
        ++$n_no_gender;
    }
    print {$out} <<"EOF";

Tallies:
       People: $n_people
    Same Name: $n_same_name
     Addr Dup: $n_addr_dup
    No Gender: $n_no_gender
</pre>
EOF
    close $out;
    $c->response->redirect($c->uri_for("/static/undup.html"));
}

#
# we need to accomodate the weirdest most complex
# least likely situation.  this is the bane of the
# software engineer.
#
# assume that they arrive after breakfast
# and leave after lunch and before dinner.
#
# awkward globals - do better???
#
my ($event_start, $lunches, $len_lunches);
sub lunch {
    my ($d) = @_;

    my $i = $d-$event_start;
    return $i >= 0 && $i < $len_lunches && substr($lunches, $i, 1);
}

# the details are mostly for testing purposes - maybe.
# i'm not afraid of using global variables... it's simpler!
# we have a complex structure here!  whatever it takes to
# get the job done.
#
my (@meals, @detls);
my ($d8, $info, $details);
sub add {
    my ($meal, $n) = @_;
    $n ||= 1;           # !!!??? amazing.   put a space between || and =
                        # and all kinds of syntax errors are produced.
                        # hard to find the origin.
    $meals[$d8]{$meal} += $n;
    push @{$detls[$d8]{$meal}}, $info if $details;
}
sub detail_disp {
    my ($aref) = @_;
    # should be an array ref of array refs.
    return "" unless defined $aref;
    "<table>\n"
    . (join "\n",
       map { 
           "<tr><td>$_->[0]</td><td>$_->[1]</td></tr>"
       }
       sort {
           $a->[0] cmp $b->[0]
       }
       @$aref
      )
    . "</table>\n";
}

#
# very tricky.  Pay Attention.
# we consider the date range of the requested meal list.
# breakfast does not happen on the arrival date - programs and rentals.
#   well, unless the program start time is before 9:00 am.
# program lunches could happen on the first day of the program
#     if that day's lunch is selected (which it _could_ be if the
#     _program_ _start_ time is before 1:00 pm).
# similarily rental lunches CAN happen on the first
#   day - depending on the start time.
# dinner does not happen on the departure date - for programs and rentals.
# but for MMI _courses_ dinner IS served on the last day.
# people in DCM programs do not eat at all.
# PRs always have lunch except for their arrival day (but never
#     on a Saturday).
# Blocks with people in them will eat as if they were in a PR
#   for the date range.
# the number of rental people on any given day is determined
#     by looking at the web grid - maintained by the rental coordinator.
#     if that grid is empty we use the maximum specified in the rental
#     for each day.
#
sub meal_list : Local {
    my ($self, $c) = @_;

    my $sdate = trim($c->request->params->{sdate});
    my $edate = trim($c->request->params->{edate});
    $details = $c->request->params->{details};

    my $fmt = "%b %e"; # easier for the kitchen to read

    # validation
    my $start = $sdate? date($sdate): tt_today($c);
    if (! $start) {
        $c->stash->{mess} = "Illegal start date: $sdate";
        $c->stash->{template} = "gen_error.tt2";
        return;
    }
    $start->set_format($fmt);

    Date::Simple->relative_date($start);
    my $end = $edate? date($edate, $fmt): $start + 29;
    Date::Simple->relative_date();

    if (! $end) {
        $c->stash->{mess} = "Illegal end date: $edate";
        $c->stash->{template} = "gen_error.tt2";
        return;
    }
    $end->set_format($fmt);
    if ($end < $start) {
        $c->stash->{mess} = "End date must be after Start date.";
        $c->stash->{template} = "gen_error.tt2";
        return;
    }

    my $dr    = DateRange->new($start, $end);

    my $start_d8 = $start->as_d8();
    my $end_d8   = $end->as_d8();

    #
    # people enrolled in a DCM program do not eat meals.
    # resident programs are considered community and not included.
    #
    my @regs = model($c, 'Registration')->search(
                   {
                       date_start => { '<=' => $end_d8   },
                       date_end   => { '>=' => $start_d8 },
                       'program.category_id' => 1,    # must be 'normal' program
                            # could do some multi-step join 
                            # do program.category.name => 'Normal'
                            # but not now ...
                       cancelled  => '',
                       -or => [
                           'program.level' => 'S',
                           'program.level' => ' ',
                       ],
                   },
                   {
                       join     => [qw/ program /],
                       prefetch => [qw/ program /],   
                   }
               );
    my @rentals = model($c, 'Rental')->search({
                      sdate => { '<=' => $end_d8   },
                      edate => { '>=' => $start_d8 },
                      name  => { -not_like => 'XL %' },
                      -or => [
                          program_id => 0,      # non-hybrid rentals only
                          program_id => undef,  # null
                      ],
                                # hybrid rental/programs are counted
                                # on the program side by individual
                                # registration
                                # BUT we look to the parallel rental
                                # to see what days the program has lunches!
                  });
    my @blocks  = model($c, 'Block')->search({
                      sdate   => { '<=' => $end_d8 },
                      edate   => { '>=' => $start_d8 },
                      npeople => { '>'  => 0 },
                      allocated => 'yes',
                  });

    my $breakfast_end = '0900';    # 9:00 am
    my $lunch_end     = '1300';    # 1:00 pm
    @meals = ();   # hashrefs from $start to $end
    @detls = ();   # names, sources
    clear_lunch();
    my $d;      # to loop through days
    for my $r (@regs) {

        if ($details) {
            my $person = $r->person;
            $info = [ $person->last . ", " . $person->first,
                      $r->program->name
                    ];
        }
        my $pr = $r->program();
        if ($pr->rental_id()) {
            ($event_start, $lunches) = get_lunch($c, $pr->rental_id, 'Rental');
        }
        else {
            ($event_start, $lunches) = get_lunch($c, $r->program_id, 'Program');
        }
        $len_lunches = length($lunches);

        my $r_start = $r->date_start_obj();
        my $r_end   = $r->date_end_obj();

        my $ol = $dr->overlap(DateRange->new($r_start,
                                             $r_end   ));
        my $sd = $ol->sdate();
        my $ed = $ol->edate();

        my $prog = $r->program();
        my $mmi_prog = $prog->school() != 0;
        my $PR = $prog->PR();
        #
        # optimizations???
        # have a $n = day number?  so $d++; $n++; and then 'if lunch($n)'
        # then not so much date arithmetic!

        for ($d = $sd; $d <= $ed; ++$d) {
            $d8 = $d->as_d8();
            add('breakfast') if ($d != $r_start
                                 || $prog->prog_start() < $breakfast_end)
                                ;
            add('lunch')     if $d->day_of_week() != 6
                                &&
                                ($d != $r_start
                                 || $prog->prog_start() < $lunch_end)
                                &&
                                (lunch($d) || $PR)
                                ;
            add('dinner')    if $d != $r_end || $mmi_prog;
        }
    }
    for my $bl (@blocks) {
        my $npeople = $bl->npeople();
        my $bl_start = $bl->sdate_obj();
        my $bl_end   = $bl->edate_obj();
        my $ol = $dr->overlap(DateRange->new($bl_start,
                                             $bl_end   ));
        if ($details) {
            $info = [
                        "$npeople "
                        . (($npeople == 1)? "person"
                           :                "people"),
                        "block - " . $bl->reason()
                    ]
                    ;
        }
        my $sd = $ol->sdate;
        my $ed = $ol->edate;
        for ($d = $sd; $d <= $ed; ++$d) {
            $d8 = $d->as_d8();
            add('breakfast', $npeople) if $d != $bl_start;
            add('lunch')     if $d->day_of_week() != 6
                                && $d != $bl_start;
            add('dinner',    $npeople) if $d != $bl_end;
        }
    }
    RENTAL:
    for my $r (@rentals) {
        # set globals

        $event_start = $r->sdate_obj();
        $lunches = $r->lunches();
        my @counts = $r->daily_counts();

        ($event_start, $lunches)  = get_lunch($c, $r->id(), 'Rental');
        $len_lunches = length($lunches);

        my $r_start = $r->sdate_obj();
        my $r_end   = $r->edate_obj();
        my $r_name  = $r->name();
        my $start_hour = $r->start_hour();

        my $ol = $dr->overlap(DateRange->new($r_start, $r_end));
        my $sd = $ol->sdate();
        my $ed = $ol->edate();
        for ($d = $sd; $d <= $ed; ++$d) {
            $d8 = $d->as_d8();
            my $n = $r->expected() || $counts[$d - $event_start];
            if ($details) {
                $info = [ "$n People" , $r_name ];
            }
            add('breakfast', $n) if $d != $r_start;
            add('lunch',     $n) if ($d != $r_start || $start_hour < $lunch_end)
                                    && lunch($d);
            add('dinner',    $n) if $d != $r_end;
        }
    }
    my $css = $c->uri_for("/static/meal_list.css");
    my $list .= <<"EOL";
<h2>Meal List</h2>
<table cellpadding=3>
<tr>
<th colspan=2 align=center>Date</th>
<th>Breakfast</th>
<th>Lunch</th>
<th>Dinner</th>
</tr>
EOL
    $d = $start;
    while ($d <= $end) {
        my $key = $d->as_d8();
        $list .= "<tr>\n";
        $list .= "<td align=right>" . $d->format("%a") . "</td>\n";
        $list .= "<td>$d</td>\n";
        for my $m (qw/breakfast lunch dinner/) {
            $list .= "<td align=right>"
                      . ((defined $meals[$key]{$m})? $meals[$key]{$m}: "-")
                      . "&nbsp;&nbsp;</td>\n";
        }
        $list .= "</tr>\n";
        ++$d;
    }
    $list .= "</table>\n";
    if ($details) {
        $list .= "<p class=p2>\n";
        $d = $start;
        while ($d <= $end) {
            my $key = $d->as_d8();
            $list .= $d->format("%a") . " $d\n<ul>\n";
            for my $m (qw/breakfast lunch dinner/) {
                $list .= "\u$m\n\t<ul>\n"
                       . detail_disp($detls[$key]{$m})
                       . "\n\t</ul>\n";
            }
            $list .= "</ul>\n";
            ++$d;
        }
        
    }
    #
    # any special food service needs within this date range?
    #
    my @programs = model($c, 'Program')->search(
        {
            sdate => { '<=' => $end_d8   },
            edate => { '>=' => $start_d8 },
            "summary.food_service" => { '!=' => '' },
        },
        {
            join     => [qw/ summary /],
            prefetch => [qw/ summary /],   
        }
    );
    #
    # get rentals again but only the ones with an
    # entry in the summary for food_service.
    #
    @rentals = model($c, 'Rental')->search(
        {
            sdate => { '<=' => $end_d8   },
            edate => { '>=' => $start_d8 },
            "summary.food_service" => { '!=' => '' },
        },
        {
            join     => [qw/ summary /],
            prefetch => [qw/ summary /],   
        }
    );
    stash($c,
        daily_list => $list,
        special    => [
            sort { $a->sdate <=> $b->sdate }
            @rentals, @programs
        ],
        template   => "listing/meal_list.tt2",
    );
}

sub stale : Local {
    my ($self, $c) = @_;

    my $upload = $c->request->upload('stale_emails');
    my $n = 0;
    if ($upload) {
        my @emails = $upload->slurp =~ m{[^'",\s]+\@[^'",\s]+}g;
        $n = @emails;
        if (@emails) {
            model($c, 'Person')->search({
                email => { -in => \@emails },
            })->update({
                email => '',
            });
        }
    }
    $c->stash->{mess} = "$n emails purged.";
    $c->stash->{template} = "gen_message.tt2";
}

sub unsubscribe : Local {
    my ($self, $c) = @_;

    my $upload = $c->request->upload('unsub_emails');
    my $type = $c->request->params->{unsub_type} eq 'mmi'? "mmi_"
               :                                          "";
    my $n = 0;
    if ($upload) {
        my @emails = $upload->slurp =~ m{[^'",\s]+\@[^'",\s]+}g;
        $n = @emails;
        if (@emails) {
            model($c, 'Person')->search({
                email => { -in => \@emails },
            })->update({
                "${type}e_mailings" => '',
            });
        }
    }
    $c->stash->{mess} = "$n emails unsubscribed.";
    $c->stash->{template} = "gen_message.tt2";
}

sub email_check : Local {
    my ($self, $c) = @_;

    my @people;
    my $email;
    for my $p (model($c, 'Person')->search(
        { email => { "!=", "" }},
        { order_by => 'email' },
    )) {
        if (($email = $p->email) && ! valid_email($email)) {
            push @people, $p;
        }
    }
    @people = sort {
                  $a->email cmp $b->email
              }
              @people;
    $c->stash->{people} = \@people;
    $c->stash->{template} = "listing/bad_email.tt2";
}

#
#
#
sub activity_tally : Local {
    my ($self, $c) = @_;

    
    my $n_tot = model($c, 'Person')->all();
    my $n_inact = model($c, 'Person')->search({
        inactive => 'yes',
    });
    my $n_noupd = model($c, 'Person')->search({
        -or => [
            date_updat => '',
            date_updat => undef,
        ],
    });
    my $n_act = $n_tot - $n_inact;

    my $html = <<"EOH";
Total $n_tot, InActive $n_inact, Active $n_act, No Last Update $n_noupd
<p>
EOH
    my $cur_year = today()->year();
    $html .= <<"EOH";
<h3>Last Active Tally by Year</h3>
<ul>
<table cellpadding=2 border=0>
<tr>
<th>Year</th>
<th align=right>Number</th>
<th align=right>SubTotal</th>
</tr>
EOH
    my $subtot = 0;
    for my $y (1980 .. $cur_year) {
        my $n = model($c, 'Person')->search({
            date_updat => { between => [ $y."0101", $y."1231" ] },
        })->count();
        $subtot += $n;
        my $cn = commify($n);
        my $csubtot = commify($subtot);
        $html .= <<"EOH";
<tr>
<td>$y</td>
<td align=right>$cn</td>
<td align=right>$csubtot</td>
</tr>
EOH
    }
    $html .= <<"EOH";
</table>
</ul>
EOH
    $c->res->output($html);
}

#
# ???members should not be marked inactive.
# nor should anyone at 445 Summit Rd 95076
#
sub mark_inactive : Local {
    my ($self, $c) = @_;

    my ($date_last) = $c->request->params->{date_last};
    my $dt = date($date_last);
    if (! $dt) {
        $c->stash->{mess} = "Invalid date: $date_last";
        $c->stash->{template} = "listing/error.tt2";
        return;
    }
    my $dt8 = $dt->as_d8();
    my @people = model($c, 'Person')->search(
        {
            inactive   => { '!=' => 'yes' },
            -or => [
                date_updat => { "<=", $dt8 },
                date_updat => undef,
            ],
            akey       => { '!=' => '44595076SUM' },
        },
        {
            order_by => [qw/ last first /],
        });
    $c->stash->{date_last} = $dt;
    $c->stash->{people} = \@people;
    $c->stash->{npeople} = scalar(@people);
    $c->stash->{template} = "listing/inactive.tt2";
}

sub mark_inactive_do : Local {
    my ($self, $c, $date_last) = @_;

    if ($c->request->params->{no}) {
        $c->response->redirect($c->uri_for('/listing/people'));
        return;
    }
    my $dt8 = date($date_last)->as_d8();
    model($c, 'Person')->search({
        inactive   => { '!=' => 'yes' },
        -or => [
            date_updat => { "<=", $dt8 },
            date_updat => undef,
        ],
        akey       => { '!=' => '44595076SUM' },
    })->update({
        inactive => 'yes',
    });
    $c->response->redirect($c->uri_for('/listing/people'));
}

#
# Comings on Saturday include people who are coming on Sunday.
# Goings are only for the day requested - even on Saturday.
# PRs and people coming early to a program are listed by name.
# For other people in programs and rentals we list just the number
# in that program/rental.
#
sub comings_goings : Local {
    my ($self, $c, $date) = @_;

    my $cg_date = trim($c->request->params->{cg_date});
    my $dt;
    if ($cg_date) {
        my $d = date($cg_date);
        if (! $d) {
            $c->stash->{mess} = "Illegal date: $cg_date";
            $c->stash->{template} = "gen_error.tt2";
            return;
        }
        $dt = $d;
    }
    elsif ($date) {
        $dt = date($date);
    }
    else {
        $dt = tt_today($c);
    }
    my $edt = ($dt->day_of_week == 6)? $dt+1: $dt;

    my $dt8  = $dt->as_d8();
    my $edt8 = $edt->as_d8();

    my @coming = model($c, 'Registration')->search({
                     date_start => { 'between' => [ $dt8, $edt8 ] },
                     cancelled  => '',
                 });
    my (@ind_coming) = map {
                           $_->[1],
                       }
                       sort {
                           $a->[0] cmp $b->[0]
                       }
                       map {
                           my $p = $_->person;
                           [ $p->last . $p->first, $_ ],
                       }
                       grep { $_->early }
                       @coming;
    my (@prg_coming) = grep { ! $_->early } @coming;
    my %prg_coming;
    for my $r (@prg_coming) {
        ++$prg_coming{$r->program_id};
    }
    @prg_coming = ();
    for my $p_id (keys %prg_coming) {
        my $p = model($c, 'Program')->find($p_id);
        push @prg_coming, {
            id    => $p_id,
            dow   => $p->sdate_obj->day_of_week(),
            name  => $p->name,
            count => $prg_coming{$p_id},
            noun  => ($prg_coming{$p_id} == 1)? "person": "people",
        };
    }
    @prg_coming = sort {
                      $a->{name} cmp $b->{name}
                  }
                  @prg_coming;
    my (@rnt_coming) = sort {
                           $a->name cmp $b->name
                       }
                       model($c, 'Rental')->search({
                           sdate      => { 'between' => [ $dt8, $edt8 ] },
                           program_id => 0,
                       });

    my (@going) = model($c, 'Registration')->search({
                      date_end => $dt8,
                      cancelled => '',
                  });
    my (@ind_going) = map {
                          $_->[1],
                      }
                      sort {
                          $a->[0] cmp $b->[0]
                      }
                      map {
                          my $p = $_->person;
                          [ $p->last . $p->first, $_ ],
                      }
                      grep { $_->late }
                      @going;
    my (@prg_going ) = grep { ! $_->late } @going;
    my %prg_going;
    for my $r (@prg_going) {
        ++$prg_going{$r->program_id};
    }
    @prg_going = ();
    for my $p_id (keys %prg_going) {
        push @prg_going, {
            id    => $p_id,
            name  => model($c, 'Program')->find($p_id)->name,
            count => $prg_going{$p_id},
            noun  => ($prg_going{$p_id} == 1)? "person": "people",
        };
    }
    @prg_going = sort {
                      $a->{name} cmp $b->{name}
                  }
                  @prg_going;
    my (@rnt_going) = sort {
                          $a->name cmp $b->name
                      }
                      model($c, 'Rental')->search({
                          edate      => $dt8,
                          program_id => 0,
                      });

    stash($c,
        date       => $dt,
        prev_date  => ($dt-1)->as_d8(),
        next_date  => ($dt+1)->as_d8(),
        ind_coming => \@ind_coming,
        ind_going  => \@ind_going,
        prg_coming => \@prg_coming,
        prg_going  => \@prg_going,
        rnt_coming => \@rnt_coming,
        rnt_going  => \@rnt_going,
        template   => "listing/comings_goings.tt2",
    );
}

sub late_notices : Local {
    my ($self, $c, $date) = @_;

    my $d8;
    if ($date) {
        $d8 = $date;
    }
    else {
        $d8 = tt_today($c)->as_d8();
    }
    my @date_bool = ();
    if (date($d8)->day_of_week() == 6) {    # Saturday
        # also look for PRs arriving on Sunday
        # not other programs.
        #
        @date_bool = (
                         -or => [
                             date_start => $d8,
                             -and => [
                                date_start => (date($d8)+1)->as_d8(),
                                'program.name' => 
                                    { like => '%Personal Retreat%' },
                             ],
                         ],
                     );
    }
    else {
        @date_bool = (date_start => $d8);
    }
    my @late_arr = model($c, 'Registration')->search(
                       {
                           @date_bool,
                           arrived    => '',
                           cancelled  => '',
                           'program.school' => 0,       # only MMC, not MMI
                       },
                       {
                           join     => [qw/ program person /],
                           prefetch => [qw/ program person /],   
                           order_by => [qw/ person.last person.first /],
                       }
                   );
    my $tt = Template->new({
        INCLUDE_PATH => "root/static/templates/letter",
        EVAL_PERL    => 0,
    });
    my $html;
    $tt->process(
        "late_notices.tt2",             # template
        { late_arr => \@late_arr },     # variables
        \$html,                         # output
    );
    $c->res->output($html);
}

sub housekeeping : Local {
    my ($self, $c, $tent, $the_date) = @_;

    my $bool_tent = ($tent)? "yes": "";
    my $hs_date = trim($c->request->params->{hs_date});
    my $d8;
    if ($hs_date) {
        my $d = date($hs_date);
        if (! $d) {
            $c->stash->{mess} = "Illegal date: $hs_date";
            $c->stash->{template} = "gen_error.tt2";
            return;
        }
        $d8 = $d->as_d8();
    }
    elsif ($the_date) {
        $d8 = $the_date;
    }
    else {
        $d8 = tt_today($c)->as_d8();
    }
    my $d8_1 = (date($d8)-1)->as_d8();      # for RentalBookings

    my %seen = ();
    my %cluster_name = map {
                           $_->id => $_->name
                       }
                       model($c, 'Cluster')->all();
    my @arriving_houses =
        grep {
            !$seen{$_->id}++
        }
        map {
            $_->house
        }
        model($c, 'Registration')->search(
            {
                house_id     => { '!=', 0 },
                date_start   => $d8,
                'house.tent' => $bool_tent,
            },
            {
                join     => [qw/ house /],
                prefetch => [qw/ house /],   
            }
        );
    push @arriving_houses,
        grep {
            !$seen{$_->id}++
        }
        map {
            $_->house
        }
        model($c, 'RentalBooking')->search(
            {
                date_start   => $d8,
                'house.tent' => $bool_tent,
            },
            {
                join     => [qw/ house /],
                prefetch => [qw/ house /],   
            }
        );
    push @arriving_houses,
        grep {
            !$seen{$_->id}++
        }
        map {
            $_->house
        }
        model($c, 'Block')->search(
            {
                sdate        => $d8,
                npeople      => { '>' => 0 },
                'house.tent' => $bool_tent,
                allocated    => 'yes',
            },
            {
                join     => [qw/ house /],
                prefetch => [qw/ house /],   
            }
        );
    @arriving_houses =
        sort {
            $cluster_name{$a->cluster_id} cmp $cluster_name{$b->cluster_id}
            or
            $a->cluster_order <=> $b->cluster_order
        }
        @arriving_houses;

    # and now for the rooms vacated today
    # start things over.
    %seen = ();
    my @departing_houses =
        grep {
            !$seen{$_->id}++
        }
        map {
            $_->house
        }
        model($c, 'Registration')->search(
            {
                house_id     => { '!=', 0 },
                date_end     => $d8,
                'house.tent' => $bool_tent,
            },
            {
                join     => [qw/ house /],
                prefetch => [qw/ house /],   
            }
        );
    push @departing_houses,
        grep {
            !$seen{$_->id}++
        }
        map {
            $_->house
        }
        model($c, 'RentalBooking')->search(
            {
                date_end => $d8_1,
                    # $d8_1 and not $d8 since
                    # the end date in RentalBooking is
                    # one less than edate in the Rental.
                    # this is different from Registrations.
                'house.tent' => $bool_tent,
            },
            {
                join     => [qw/ house /],
                prefetch => [qw/ house /],   
            }
        );
    push @departing_houses,
        grep {
            !$seen{$_->id}++
        }
        map {
            $_->house
        }
        model($c, 'Block')->search(
            {
                edate        => $d8,
                npeople      => { '>' => 0 },
                'house.tent' => $bool_tent,
            },
            {
                join     => [qw/ house /],
                prefetch => [qw/ house /],   
            }
        );
    @departing_houses =
        sort {
            $cluster_name{$a->cluster_id} cmp $cluster_name{$b->cluster_id}
            or
            $a->cluster_order <=> $b->cluster_order
        }
        @departing_houses;
    my %next_needed;
    for my $h (@departing_houses) {
        my $hid = $h->id();

        # find the next day this house is needed.
        #
        my ($config) = model($c, 'Config')->search(
            {
                house_id => $hid,
                the_date => { '>=', $d8 },
                cur      => { '>', 0   },
                    # even if this bed is not needed...
                    # there may be someone else in the room so it would
                    # be nice to make up the bed for the tidyness of it all.
            },
            {
                rows     => 1,
            }
        );
        if ($config) {
            my $n = date($config->the_date()) - date($d8);
            my $name = $h->name();
            if ($n == 0) {
                $next_needed{$name} = " - needed TODAY";
                #
                # see if the person(s) occupying it today
                # is/are actually arriving today or if they
                # are already occupying it and their roommate
                # has departed leaving an unmade bed.
                if (! (my (@regs) = model($c, 'Registration')->search({
                                     date_start => $d8,
                                     house_id   => $hid,
                                 }))
                ) {
                    $next_needed{$name} .= " (already occupied)";
                }
            }
            else {
                $next_needed{$name}  = " - needed in $n day";
                $next_needed{$name} .= "s" if $n != 1;
            }
        }
    }
    stash($c,
        tent             => $tent,
        the_date         => date($d8),
        daily_pic_date   => "indoors/$d8",
        cluster_date     => $d8,
        next_date        => (date($d8)+1)->as_d8(),
        prev_date        => (date($d8)-1)->as_d8(),
        arriving_houses  => \@arriving_houses,
        departing_houses => \@departing_houses,
        next_needed      => \%next_needed,
        template         => "listing/housekeeping.tt2",
    );
}

#
# display all of the records in the made_up table.
#
sub make_up : Local {
    my ($self, $c, $tent) = @_;
    
    $tent ||= 0;
    my $today = tt_today($c);
    my $prev_clust = '';
    my $type = ($tent)? "Campsite"
               :        "Room"
               ;
    my $html = "";
    my $clust_num = 0;
    my $house_num = 0;
    MAKE_UP_HOUSE:
    for my $mu (model($c, 'MakeUp')->search(
                    { },
                    {
                        join => {
                            house => 'cluster',
                        },
                        prefetch => {
                            house => 'cluster',
                        },
                        order_by => [qw/ cluster.name house.cluster_order /],
                    }
                )
    ) {
        my $htent = $mu->house->tent();
        if (($tent && !$htent)
            ||
            (!$tent && $htent)
        ) {
            next MAKE_UP_HOUSE;
        }
        my $clust = $mu->house->cluster->name;
        if ($clust ne $prev_clust) {
            if ($prev_clust) {
                $html .= "</table></ul>\n";
            }
            ++$clust_num;
            $house_num = 0;
            $html .= <<"EOH";
<h2>$clust
<span class=all>All <input type=checkbox onclick="toggle_all($clust_num)"></span>
</h2>
<ul>
<table>
EOH
            $prev_clust = $clust;
        }
        my $needed;
        if ($mu->date_needed()) {
            $needed = $mu->date_needed_obj() - $today;
            if ($needed <= $string{make_up_urgent_days}) {
                $needed = $needed ==  0? 'Today'
                         :$needed ==  1? 'Tomorrow'
                         :$needed == -1? 'Yesterday'
                         :               "$needed days"
                         ;
                if ($mu->refresh()) {
                    # most likely Today
                    $needed .= " - Refresh";
                }
                $needed = "<span style='color: red'>$needed</span>";
            }
            else {
                $needed .= " days";
            }
        }
        else {
            $needed = "Never";
        }
        ++$house_num;
        $html .= "<tr><td><input type=checkbox id=$clust_num-$house_num name=h"
              .  $mu->house_id()
              .  "> "
              .  $mu->house->name()
              .  "</td><td>&nbsp;&nbsp;&nbsp;$needed"
              .  "</td></tr>\n"
              ;
    }
    $html .= "</table></ul>\n";
    $c->stash->{heading} ="<span class=heading>$type Make-Up List</span>\n"
                        . "<span class=timestamp>As of "
                        . localtime() 
                        . "</span>\n"
                        ;
    $c->stash->{content}  = $html;
    $c->stash->{tent}     = $tent;
    $c->stash->{template} = "listing/make_up.tt2";
}

sub make_up_do : Local {
    my ($self, $c, $tent) = @_;

    my @ids = ();
    for my $hid (keys %{ $c->request->params() }) {
        $hid =~ s{^h}{};
        push @ids, $hid;
    }
    if (@ids) {
        model($c, 'MakeUp')->search({
            house_id => { -in => \@ids },
        })->delete();
    }
    if ($c->check_user_roles('field_staff')) {
        $c->stash->{template} = "listing/field.tt2";
    }
    else {
        $c->response->redirect($c->uri_for("/listing/"));
    }
}

#
# listings for the field staff
# so they see nothing else.
#
sub field : Local {
    my ($self, $c) = @_;
    $c->stash->{template} = "listing/field.tt2";
}

#
# on a given date how many beds will be needed?
# numbers of people that are arriving at a campsite - not sites.
#   but for a rental we won't know the number of people - just sites.
#
sub field_plan : Local {
    my ($self, $c) = @_;

    my ($sdate, $edate);
    $sdate = trim($c->request->params->{sdate});
    if ($sdate eq "t30") {
        # couldn't put sdate=t&edate=+30 or
        #              sdate=t&edate=%2B30
        # in listing/index.tt2 or listing/field.tt2
        # for some reason.
        $sdate = "t";
        $edate = "+29";
    }
    else {
        $edate = trim($c->request->params->{edate});
    }

    # validation
    my $start = $sdate? date($sdate): tt_today($c);
    if (! $start) {
        $c->stash->{mess} = "Illegal start date: $sdate";
        $c->stash->{template} = "gen_error.tt2";
        return;
    }
    my $start_d8 = $start->as_d8();

    Date::Simple->relative_date($start);
    my $end = $edate? date($edate): $start + 13;
    Date::Simple->relative_date();

    if (! $end) {
        $c->stash->{mess} = "Illegal end date: $edate";
        $c->stash->{template} = "gen_error.tt2";
        return;
    }
    my $end_d8 = $end->as_d8();

    if ($end < $start) {
        $c->stash->{mess} = "End date must be after Start date.";
        $c->stash->{template} = "gen_error.tt2";
        return;
    }

    my (%beds, %sites);
    my $d = $start;
    while ($d <= $end) {
        my $d8 = $d->as_d8();
        $beds{$d8} = 0;
        $sites{$d8} = 0;
        ++$d;
    }
    my @regs = model($c, 'Registration')->search({
                   date_start => { between => [ $start_d8, $end_d8 ] },
                   house_id   => { '!='    => 0                      },
                   cancelled  => '',
               });
    for my $r (@regs) {
        my $sd = $r->date_start();
        if ($r->h_type() =~ m{tent}) {
            ++$sites{$sd};
        }
        else {
            ++$beds{$sd};
        }
    }
    my @rentals = model($c, 'Rental')->search({
                      sdate => { between => [ $start_d8, $end_d8 ] },
                  });
    for my $r (@rentals) {
        my $sd = $r->sdate();
        #
        # on the start date of this rental how
        # many beds/sites will need to be tidied up?
        # assume that all bookings are full - worst case scenario.
        #
        for my $rb (model($c, 'RentalBooking')->search({
                       rental_id => $r->id(),
                    })
        ) {
            my $h = $rb->house();
            if ($h->tent()) {
                ++$sites{$sd};
            }
            else {
                $beds{$sd} += $h->max();
            }
        }
    }
    my @blocks  = model($c, 'Block')->search({
                      sdate   => { between => [ $start_d8, $end_d8 ] },
                      npeople => { '>'  => 0 },
                  });
    for my $bl (@blocks) {
        my $sd = $bl->sdate();
        my $npeople = $bl->npeople();
        if ($bl->house->tent()) {
            $sites{$sd} += $npeople;
        }
        else {
            $beds{$sd} += $npeople;
        }
    }
    $d = $start;
    my $rows = "";
    while ($d <= $end) {
        my $key = $d->as_d8();
        $rows .= "<tr align=right>\n";
        $rows .= "<td align=center>$d</td>\n";
        $rows .= "<td>$beds{$key}</td>\n";
        $rows .= "<td>$sites{$key}</td>\n";
        $rows .= "</tr>\n";
        ++$d;
    }
    stash($c,
        time     => scalar(localtime()),
        rows     => $rows,
        template => "listing/field_plan.tt2",
    );
}

#
# gather the given section of
# rental and program summaries.
#
# ??? we get start and end dates in several places.
# can we unify this?  DRY? or not horribly refactored?
#
# do not include PR or MMI DCM programs
#
sub summary : Local {
    my ($self, $c, $section) = @_;

    my ($sdate, $edate);
    $sdate = trim($c->request->params->{sdate});
    if ($sdate eq "t30") {
        # couldn't put sdate=t&edate=+30 or
        #              sdate=t&edate=%2B30
        # in listing/index.tt2 or listing/field.tt2
        # for some reason.
        $sdate = "t";
        $edate = "+29";
    }
    else {
        $edate = trim($c->request->params->{edate});
    }

    # validation
    my $start = $sdate? date($sdate): tt_today($c);
    if (! $start) {
        $c->stash->{mess} = "Illegal start date: $sdate";
        $c->stash->{template} = "gen_error.tt2";
        return;
    }
    my $start_d8 = $start->as_d8();

    Date::Simple->relative_date($start);
    my $end = $edate? date($edate): $start + 13;
    Date::Simple->relative_date();

    if (! $end) {
        $c->stash->{mess} = "Illegal end date: $edate";
        $c->stash->{template} = "gen_error.tt2";
        return;
    }
    my $end_d8 = $end->as_d8();

    if ($end < $start) {
        $c->stash->{mess} = "End date must be after Start date.";
        $c->stash->{template} = "gen_error.tt2";
        return;
    }
    my @rentals = model($c, 'Rental')->search(
        {
            sdate => { '<=' => $end_d8   },
            edate => { '>=' => $start_d8 },
            "summary.$section" => { '!=' => '' },
        },
        {
            join     => [qw/ summary /],
            prefetch => [qw/ summary /],   
        }
    );
    my @opt = ();
    if ($section !~ m{workshop}xms) {
        @opt = ("summary.$section" => { '!=' => '' });
    }
    my @programs = model($c, 'Program')->search(
        {
            sdate => { '<=' => $end_d8   },
            edate => { '>=' => $start_d8 },
            rental_id => 0,             # ignore the summary of hybrid programs
                                        # the rental side is the one we use.
            @opt,
        },
        {
            join     => [qw/ summary /],
            prefetch => [qw/ summary /],   
        }
    );
    # a further limiting of the programs not so easily
    # done above...   no biggie - don't worry about it.
    #
    @programs = grep {
                    !($_->PR() || $_->level() =~ m{[DCM]})
                }
                @programs;
    stash($c,
        start  => $start,
        end    => $end,
        events => [
            sort {
                $a->sdate <=> $b->sdate ||
                $a->name  cmp $b->name 
            }
            @rentals, @programs
        ],
        section  =>
            $section eq 'flowers'              ? 'Flower'
           :$section eq 'field_staff_setup'    ? 'Field Staff Setup'
           :$section eq 'sound_setup'          ? 'Sound Set Up'
           :$section eq 'workshop_description' ? 'Workshop Description'
           :$section eq 'workshop_schedule'    ? 'Workshop Schedule'
           :                                     'Set Up',
        template => "listing/summary.tt2",
    );
}

sub financial : Local {
    my ($self, $c) = @_;
    my $today = today();
    my $y = $today->year();
    my $m = $today->month();
    stash($c,
        since    => date($y-1, $m, 1)->format("%D"),
        since_2months => ($today-60)->format("%D"),
        start    => date($y, $m, 1)->format("%D"),
        end      => date($y, $m, days_in_month($y, $m))->format("%D"),
        template => "listing/financial.tt2",
    );
}
sub people : Local {
    my ($self, $c) = @_;
    $c->stash->{template} = "listing/people.tt2";
}
sub field_staff : Local {
    my ($self, $c) = @_;
    $c->stash->{template} = "listing/field_staff.tt2";
}
sub kitchen : Local {
    my ($self, $c) = @_;
    $c->stash->{template} = "listing/kitchen.tt2";
}

sub orient_windup : Local {
    my ($self, $c, $sortkey) = @_;

    $sortkey ||= "sdate";
    my $from = $c->request->params->{ow_from};
    my $ow_from = date($from);
    if (! $ow_from) {
        error($c,
            "Invalid From date for Orientation/Wind Up: $from",
            'gen_error.tt2',
        );
        return;
    }
    my $to = $c->request->params->{ow_to};
    my $ow_to = date($to);
    if (! $ow_to) {
        error($c,
            "Invalid To date for Orientation/Wind Up: $from",
            'gen_error.tt2',
        );
        return;
    }
    my $ow_from8 = $ow_from->as_d8();
    my $ow_to8 = $ow_to->as_d8();
    my @events;
    EVENT:
    for my $ev (model($c, 'Program')->search({
                    sdate => { '<=' => $ow_to8   },
                    edate => { '>=' => $ow_from8 },
                    name  => { -not_like => 'XL%'},
                    name  => { -not_like => 'Personal Retreats%'},
                    -or => [
                        school => 0,
                        level  => 'S',
                    ],
                }),
                model($c, 'Rental')->search({
                    sdate => { '<=' => $ow_to8   },
                    edate => { '>=' => $ow_from8 },
                    name  => { -not_like => 'XL%'},
                })
    ) {
        my $sum = $ev->summary();
        push @events, {
            name   => $ev->name(),
            sdate  => $ev->sdate_obj(),
            sdate8 => $ev->sdate(),
            edate  => $ev->edate_obj(),
            edate8 => $ev->edate(),
            orientation => $sum->orientation(),
            wind_up => $sum->wind_up(),
            sum_id => $sum->id(),
        };
    }
    my (%dup_start, %dup_end);
    for my $e (@events) {
        ++$dup_start{$e->{sdate8}};
        ++$dup_end  {$e->{edate8}};
    }
    for my $e (@events) {
        if ($dup_start{$e->{sdate8}} > 1) {
            $e->{or_class} = "red";
        }
        if ($dup_end{$e->{edate8}} > 1) {
            $e->{wu_class} = "red";
        }
    }
    @events = sort {
                 $a->{$sortkey} <=> $b->{$sortkey}
             }
             @events;
    my $params = "ow_from="
               . $ow_from8
               . "&"
               . "ow_to="
               . $ow_to8
               ;
    stash($c,
        from     => $ow_from,
        to       => $ow_to,
        events   => \@events,
        params   => $params,
        template => 'listing/orient_windup.tt2',
    );
}

sub gate_codes : Local {
    my ($self, $c) = @_;

    my $from = $c->request->params->{gc_from};
    my $gc_from = date($from);
    if (! $gc_from) {
        error($c,
            "Invalid From date for Gate Codes: $from",
            'gen_error.tt2',
        );
        return;
    }
    my $to = $c->request->params->{gc_to};
    my $gc_to = date($to);
    if (! $gc_to) {
        error($c,
            "Invalid To date for Gate Codes: $from",
            'gen_error.tt2',
        );
        return;
    }
    my $gc_from8 = $gc_from->as_d8();
    my $gc_to8 = $gc_to->as_d8();
    my $missing_only = $c->request->params->{missing_only};
    my @codes;
    EVENT:
    for my $ev (model($c, 'Program')->search({
                    sdate => { '<=' => $gc_to8   },
                    edate => { '>=' => $gc_from8 },
                    name  => { -not_like => 'XL%'},
                    rental_id => 0,     # not a hybrid
                    -or => [
                        school => 0,
                        level  => 'S',
                    ],
                }),
                model($c, 'Rental')->search({
                    sdate => { '<=' => $gc_to8   },
                    edate => { '>=' => $gc_from8 },
                    name  => { -not_like => 'XL%'},
                })
    ) {
        if ($ev->event_type() eq 'program'
            && $ev->category->name() ne 'Normal')
        {
            next EVENT;
        }
        my $sum = $ev->summary();
        my $code  = $sum->gate_code();
        if ($missing_only && $code) {
            next EVENT;
        }
        push @codes, {
            name   => $ev->name(),
            sdate  => $ev->sdate_obj(),
            edate  => $ev->edate_obj(),
            type   => $ev->event_type(),
            code   => $code,
            sum_id => $sum->id(),
        };
    }
    @codes = sort {
                 $a->{sdate} <=> $b->{sdate}
             }
             @codes;
    stash($c,
        from     => $gc_from,
        to       => $gc_to,
        codes    => \@codes,
        template => 'listing/' . ($missing_only? 'miss_gate_code.tt2'
                                  :              'gate_code.tt2'),
    );
}

sub gate_codes_do : Local {
    my ($self, $c) = @_;
    my %codes = %{$c->request->params()};

    # first check for valid codes
    my @errs = ();
    for my $id (keys %codes) {
        if ($codes{$id} && $codes{$id} !~ m{^\d\d\d\d$}) {
            push @errs, $codes{$id};
        }
    }
    if (@errs) {
        error($c,
            "Invalid codes: " . join(", ", @errs),
            'gen_error.tt2',
        );
        return;
    }

    CODE:
    for my $id (keys %codes) {
        if (!$codes{$id}) {
            next CODE;
        }
        my ($sum_id) = $id =~ m{(\d+)};
        my $sum = model($c, 'Summary')->find($sum_id);
        if ($sum) {
            $sum->update({
                gate_code => $codes{$id},
            });
        }
    }
    $c->response->redirect($c->uri_for("/listing/index"));
}

use Spreadsheet::ParseExcel;

sub upload_yj_sheet : Local {
    my ($self, $c) = @_;

    stash($c,
        affil_table => affil_table($c),
        template    => 'listing/yj_upload.tt2',
    );
}

my @chosen;

# look in the passed header fields for the indices of ones you need.
# these are needed in this precise order:
#
# first, last, company,
# address, address2, city, state, country, zip,
# phone, email
#
# company and address2 are optional
# if they're not found put 100 for the index.
#
sub init_chosen {
    my (@headers) = @_;
    
    @chosen = ();
    NEEDED:
    for my $w (qw/
        first last company
        address address2 city state country zip
        phone email
    /) {
        for my $i (0 .. $#headers) {
            if (defined $headers[$i]
                && $headers[$i] =~ m{$w}xmsi)
            {
                push @chosen, $i;
                next NEEDED;
            }
        }
        if ($w eq 'address2' || $w eq 'company') {
            push @chosen, 100;
            next NEEDED;
        }
        return "could not find column for $w";
    }
    return;
}
sub upload_yj_sheet_do : Local {
    my ($self, $c) = @_;

    my @cur_affils = grep { s/^aff(\d+)/$1/ }
                     $c->request->param;
    my $sname = $c->request->upload('spreadsheet');
    my $content = $sname->slurp();
    my $parser   = Spreadsheet::ParseExcel->new();
    my $workbook = $parser->parse(\$content);
    if ( !defined $workbook ) {
        error($c,
            "Could not parse spreadsheet: " . $parser->error(),
            'gen_error.tt2',
        );
        return;
    }
    my $today_d8 = tt_today($c)->as_d8();
    my $n = 0;
    my $got_people = "";
    for my $worksheet ($workbook->worksheets()) {
        my ($row_min, $row_max) = $worksheet->row_range();
        my ($col_min, $col_max) = $worksheet->col_range();
        for my $row ($row_min .. $row_max) {

            my @fields;
            for my $col ($col_min .. $col_max) {
 
                my $cell = $worksheet->get_cell($row, $col);
                next unless $cell;
 
                $fields[$col] = $cell->value();
            }
            $fields[100] = '';      # for missing address2 or company

            if ($row == $row_min) {
                # first row is the header - naming the columns.
                # it must be correct or else we abandon this import.
                #
                my $status = init_chosen(@fields);
                if ($status) {
                    error($c,
                        $status,
                        'gen_error.tt2',
                    );
                    return;
                }
            }
            else {
                my ($first, $last, $company,
                    $addr1, $addr2, $city, $state, $country, $zip,
                    $phone, $email) = @fields[ @chosen ];

                if (empty($first) && empty($last) && !empty($company)) {
                    $first = $company;
                }
                if ($country eq 'USA' || $country eq 'UNITED STATES') {
                    $country = q{};
                }
                $zip =~ s{-.*}{}xms;
                for my $f ($first, $last, $company,
                           $addr1, $addr2, $city, $country)
                {
                    $f = normalize($f);
                }
                my @people = model($c, 'Person')->search({
                    first => { like => "$first%" },
                    last  => $last,
                });
                if (@people) {
                    my @firsts = map { $_->first() } @people;
                    my $n = 2;
                    NUM:
                    while (1) {
                        for my $f (@firsts) {
                            if ($f eq "$first $n") {
                                ++$n;
                                next NUM;
                            }
                        }
                        last NUM;
                    }
                    # a better way to do the above with List::Utils???
                    $first .= " $n";
                }
                my $p = model($c, 'Person')->create({
                    first    => $first,
                    last     => $last,
                    addr1    => $addr1,
                    addr2    => $addr2,
                    city     => $city,
                    st_prov  => $state,
                    country  => $country,
                    tel_home => $phone,
                    zip_post => $zip,
                    email    => $email,
                    akey     => nsquish($addr1, $addr2, $zip),

                    date_updat => $today_d8,
                    date_entrd => $today_d8,
                    e_mailings         => 'yes',
                    snail_mailings     => 'yes',
                    mmi_e_mailings     => 'yes',
                    mmi_snail_mailings => 'yes',
                    share_mailings     => 'yes',
                    safety_form        => q{},
                    inactive           => q{},
                    deceased           => q{},
                });
                my $id = $p->id();
                for my $ca (@cur_affils) {
                    model($c, 'AffilPerson')->create({
                        a_id => $ca,
                        p_id => $id,
                    });
                }
                ++$n;
                $got_people .= "$first $last<br>";
            }
        }
    }
    stash($c,
        mess       => <<"EOH",
Fields: @chosen
<p class=p2>
Got these $n people from the spreadsheet:
<p class=p2>
<ul>
$got_people
</ul>
EOH
        template   => 'gen_message.tt2',
    );
}

1;
