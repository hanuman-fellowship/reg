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
/;
use Date::Simple qw/date today/;
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
    my ($prev_last, $prev_first, $prev_id) = ("", "", 0);
    my ($last, $first, $id);
    my $p;
    print {$out} "Same Last, First Names\n";
    print {$out} "======================\n";
    while ($p = Person->search_next($sth)) {
        $last  = $p->{last};
        $first = $p->{first};
        $id    = $p->{id};
        if ($last eq $prev_last && $first eq $prev_first) {
            print {$out} "<a target=other href='/person/undup/$id-$prev_id'>$last, $first</a>\n";    
        }
        $prev_last  = $last;
        $prev_first = $first;
        $prev_id    = $id;
    }
    $sth->finish();
    #
    # address dup
    #
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
        }
        $prev = $p;
    }
    #
    # unreported gender
    #
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
    }
    print {$out} "</pre>\n";
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

sub meal_list : Local {
    my ($self, $c) = @_;

    my $sdate = trim($c->request->params->{sdate});
    my $edate = trim($c->request->params->{edate});
    $details = $c->request->params->{details};

    Date::Simple->default_format("%D");

    my $fmt = "%b %e"; # easier for the kitchen to read

    # validation
    my $start = $sdate? date($sdate, $fmt): today($fmt);
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
    $c->stash->{template} = "gen_error.tt2";
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

sub help_upload : Local {
    my ($self, $c) = @_;

    if (my $upload = $c->request->upload('helpfile')) {
        my $name = $upload->filename;
        $name =~ s{.*/}{};
        $upload->copy_to("root/static/help/$name");
    }
    $c->response->redirect($c->uri_for("/static/help/index.html"));
}

1;
