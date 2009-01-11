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
/;
use Date::Simple qw/
    date
    today
/;
use DateRange;

sub index : Local {
    my ($self, $c) = @_;

    $c->stash->{template} = "listing/index.tt2";
}

#
# better way to do this the DBIx::Class way???
#
sub _phone_list {
    my @people = @{ Person->search(<<"EOS") };
select p.*
  from people p, affil_people ap, affils a
 where a.descrip like '%phone list%'
       and ap.a_id = a.id
       and ap.p_id = p.id
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
            print {$out} "<a target=other href='/person/undup/$id-$prev_id'>$last, $first</a>\n";    
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
            print {$out} "<a target=other href='/person/search_do?field=akey&pattern=$prev->{akey}'>$prev->{last}, $prev->{first}</a>\n";    
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
my ($event_start, $lunches);
sub lunch {
    my ($d) = @_;

    my $i = $d-$event_start;
    return $i >= 0 && substr($lunches, $i, 1);
}

# the details are mostly for testing purposes - maybe
# i'm not afraid of using global variables... it's simpler!
# we have a complex structure here!
#
my (@meals, @detls);
my ($d8, $info, $npeople, $details);
sub add {
    my ($meal) = @_;
    $meals[$d8]{$meal}++;
    push @{$detls[$d8]{$meal}}, $info if $details;
}
sub sum {
    my ($meal) = @_;
    $meals[$d8]{$meal} += $npeople;
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
# program lunches do not happen on the first day of the program
# even if that day is selected.
# rental lunches CAN happen on the first day - depending on the start time.
# dinner does not happen on the departure date - programs and rentals.
#
sub meal_list : Local {
    my ($self, $c) = @_;

    my $sdate = trim($c->request->params->{sdate});
    my $edate = trim($c->request->params->{edate});
    $details = $c->request->params->{details};

    Date::Simple->default_format("%D");

    my $fmt = "%b %e"; # easier for the kitchen to read

    # validation
    my $start = $sdate? date($sdate): tt_today($c);
    $start->set_format($fmt);
    if (! $start) {
        $c->stash->{mess} = "Illegal start date: $sdate";
        $c->stash->{template} = "gen_error.tt2";
        return;
    }

    Date::Simple->relative_date($start);
    my $end = $edate? date($edate, $fmt): $start + 13;
    Date::Simple->relative_date();

    if (! $end) {
        $c->stash->{mess} = "Illegal end date: $end";
        $c->stash->{template} = "gen_error.tt2";
        return;
    }
    if ($end < $start) {
        $c->stash->{mess} = "End date must be after Start date.";
        $c->stash->{template} = "gen_error.tt2";
        return;
    }

    my $dr    = DateRange->new($start, $end);

    my $start_d8 = $start->as_d8();
    my $end_d8   = $end->as_d8();

    my @regs = model($c, 'Registration')->search({
                   date_start => { '<=' => $end_d8   },
                   date_end   => { '>=' => $start_d8 },
                   cancelled  => '',
               });
    my @rentals = model($c, 'Rental')->search({
                      sdate => { '<=' => $end_d8   },
                      edate => { '>=' => $start_d8 },
                  });

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
        ($event_start, $lunches)  = get_lunch($c, $r->program_id);
        my $ol = $dr->overlap(DateRange->new($r->date_start_obj,
                                             $r->date_end_obj));
        my $sd = $ol->sdate;
        my $ed = $ol->edate;

        my $r_start = $r->date_start_obj;
        my $r_end   = $r->date_end_obj;

        # optimizations???
        # have a $n = day number?  so $d++; $n++; and then 'if lunch($n)'

        for ($d = $sd; $d <= $ed; ++$d) {
            $d8 = $d->as_d8();
            add('breakfast') if $d != $r_start;
            add('lunch')     if $d != $r_start && lunch($d);
            add('dinner')    if $d != $r_end;
        }
    }
    RENTAL:
    for my $r (@rentals) {
        # set globals

        $event_start = $r->sdate_obj;
        $lunches = $r->lunches;
        $npeople = $r->count;
        next RENTAL unless $npeople;

        if ($details) {
            $info = [ "$npeople People" , $r->name ];
        }
        my $ol = $dr->overlap(DateRange->new($event_start,
                                             $r->edate_obj));
        my $sd = $ol->sdate;
        my $ed = $ol->edate;

        my $r_start = $r->sdate_obj;
        my $r_end   = $r->edate_obj;

        # we assume all people in the rental
        # arrive and leave at the same time.

        for ($d = $sd; $d <= $ed; ++$d) {
            $d8 = $d->as_d8();
            sum('breakfast') if $d != $r_start;
            sum('lunch')     if $d != $r_start && lunch($d);
            sum('dinner')    if $d != $r_end;
        }
    }
    my $css = $c->uri_for("/static/meal_list.css");
    my $list .= <<"EOL";
<html>
<head>
<link rel="stylesheet" type="text/css" href="$css" />
</head>
<body>
<table cellpadding=3>
<caption>Meal List</caption>
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
                      . "</td>\n";
        }
        $list .= "</tr>\n";
        ++$d;
    }
    $list .= "</table>\n";
    if ($details) {
        $list .= "<p>\n";
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
    $list .= <<"EOL";
</body>
</html>
EOL
    $c->res->output($list);
}

sub stale : Local {
    my ($self, $c) = @_;

    my $upload = $c->request->upload('stale_emails');
    my $n = 0;
    if ($upload) {
        my @emails = $upload->slurp =~ m{\S+\@\S+}g;
        $n = @emails;
        model($c, 'Person')->search({
            email => { -in => \@emails },
        })->update({
            email => '',
        });
    }
    $c->stash->{mess} = "$n emails purged.";
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

    my $cur_year = today()->year();
    my $html = <<"EOH";
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
    my $n = model($c, 'Person')->search({
        inactive => '',
        date_updat => { "<=", $dt8 },
    })->count();
    $c->stash->{date_last} = $dt;
    $c->stash->{count} = $n;
    $c->stash->{template} = "listing/inactive.tt2";
}

sub mark_inactive_do : Local {
    my ($self, $c, $date_last) = @_;
}

sub comings_goings : Local {
    my ($self, $c, $date) = @_;

    my $cg_date = trim($c->request->params->{cg_date});
    my $d8;
    if ($cg_date) {
        my $d = date($cg_date);
        if (! $d) {
            $c->stash->{mess} = "Illegal date: $cg_date";
            $c->stash->{template} = "gen_error.tt2";
            return;
        }
        $d8 = $d->as_d8();
    }
    elsif ($date) {
        $d8 = $date;
    }
    else {
        $d8 = tt_today($c)->as_d8();
    }
    $c->stash->{prev_date} = (date($d8)-1)->as_d8();
    $c->stash->{next_date} = (date($d8)+1)->as_d8();

    my @coming = model($c, 'Registration')->search({
                     date_start => $d8,
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
        push @prg_coming, {
            id    => $p_id,
            name  => model($c, 'Program')->find($p_id)->name,
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
                           sdate => $d8,
                       });

    my (@going) = model($c, 'Registration')->search({
                      date_end => $d8,
                      cancelled  => '',
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
                          edate => $d8,
                      });

    $c->stash->{date} = date($d8);
    $c->stash->{ind_coming} = \@ind_coming;
    $c->stash->{ind_going}  = \@ind_going;
    $c->stash->{prg_coming} = \@prg_coming;
    $c->stash->{prg_going}  = \@prg_going;
    $c->stash->{rnt_coming} = \@rnt_coming;
    $c->stash->{rnt_going}  = \@rnt_going;

    $c->stash->{template} = "listing/comings_goings.tt2";
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
        @date_bool = (
                         -or => [
                             date_start => $d8,
                             date_start => (date($d8)+1)->as_d8(),
                         ]
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
                       },
                       {
                           join     => [qw/ house program person /],
                           prefetch => [qw/ house program person /],   
                           order_by => [qw/ person.last person.first /],
                       }
                   );
    my $tt = Template->new({
        INCLUDE_PATH => "root/src/listing",
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
        my ($config) = model($c, 'Config')->search({
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
    $c->stash->{tent}           = $tent;
    $c->stash->{the_date}       = date($d8);
    $c->stash->{daily_pic_date} = $d8;
    $c->stash->{next_date}      = (date($d8)+1)->as_d8();
    $c->stash->{prev_date}      = (date($d8)-1)->as_d8();
    $c->stash->{arriving_houses}  = \@arriving_houses;
    $c->stash->{departing_houses} = \@departing_houses;
    $c->stash->{next_needed}    = \%next_needed;
    $c->stash->{template}       = "listing/housekeeping.tt2";
}

#
# display all of the records in the make_up table.
#
sub make_up : Local {
    my ($self, $c, $tent) = @_;
    
    $tent ||= 0;
    my $today = tt_today($c);
    my $prev_clust = '';
    my $type = ($tent)? "Campsite"
               :        "Room"
               ;
    my $heading = "<span class=heading>$type Make-Up List</span>\n"
                . "<span class=timestamp>As of " . localtime() . "</span>\n"
                ;
    my $html = "";
    MAKE_UP_HOUSE:
    for my $mu (model($c, 'MakeUp')->search(
                    { },
                    {
                        join     => {
                            house => 'cluster',
                        },
                        prefetch => {
                            house => 'cluster',
                        },
                        order_by => [qw/
                            house.cluster.name
                            house.cluster_order
                        /],
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
            $html .= "<h2>$clust</h2>\n<ul><table>\n";
            $prev_clust = $clust;
        }
        my $needed;
        if ($mu->date_needed()) {
            $needed = $mu->date_needed_obj() - $today;
            if ($needed < 5) {
                my $pl = ($needed == 1)? "": "s";
                $needed = "<span style='color: red'>$needed day$pl</span>";
            }
            else {
                $needed .= " days";
            }
        }
        else {
            $needed = "never";
        }
        $html .= "<tr><td><input type=checkbox name=h"
              .  $mu->house_id()
              .  "> "
              .  $mu->house->name()
              .  "</td><td>&nbsp;&nbsp;&nbsp;$needed"
              .  "</td></tr>\n"
              ;
    }
    $html .= "</table></ul>\n";
    $c->res->output(<<"EOH");
<html>
<head>
<style type="text/css">
.heading {
    font-weight: bold;
    font-size: 20pt;
}
.timestamp {
    font-size: 13pt;
    text-align: right;
    margin-left: 1in;
}
</style>
</head>
<body>
<form action=/listing/make_up_do/$tent>
$heading
<p>
<input type=submit value="Submit">
<a style='margin-left: 2in' href="/listing">To Listings</a>
$html
<p>
<input type=submit value="Submit">
</form>
</html>
EOH
}

sub make_up_do : Local {
    my ($self, $c, $tent) = @_;

    my @ids = ();
    for my $hid (keys %{ $c->request->params() }) {
        $hid =~ s{^h}{};
        push @ids, $hid;
    }
    model($c, 'MakeUp')->search({
        house_id => { -in => \@ids },
    })->delete();
    $c->response->redirect($c->uri_for("/listing/make_up/$tent"));
}

1;
