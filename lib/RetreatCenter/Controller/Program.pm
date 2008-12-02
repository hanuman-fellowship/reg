use strict;
use warnings;
package RetreatCenter::Controller::Program;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.
use Util qw/
    leader_table
    affil_table
    meetingplace_table
    slurp 
    monthyear
    expand
    expand2
    resize
    housing_types
    sys_template
    compute_glnum
    model
    trim
    empty
    lunch_table
    add_config
    valid_email
    tt_today
    ceu_license
/;
use Date::Simple qw/
    date
/;
use Net::FTP;
use Global qw/
    %string
    @clusters
/;
use File::Copy;

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('list');
}

sub create : Local {
    my ($self, $c) = @_;

    # set defaults
    $c->stash->{check_kayakalpa}     = "checked";
    $c->stash->{check_retreat}       = "";
    $c->stash->{check_sbath}         = "checked";
    $c->stash->{check_quad}          = "";
    $c->stash->{check_collect_total} = "";
    $c->stash->{check_economy}       = "";
    $c->stash->{check_webready}      = "checked";
    $c->stash->{check_linked}        = "checked";
    $c->stash->{program_leaders}     = [];
    $c->stash->{program_affils}      = [];
    $c->stash->{section}             = 1;   # Web (a required field)
    Global->init($c);
    $c->stash->{program}             = {
        tuition      => 0,
        extradays    => 0,
        full_tuition => 0,
        deposit      => 100,
        canpol       => { name => "Default" },  # a clever way to set default!
        housecost    => { name => "Default" },  # fake an object!
        ptemplate    => 'default',
        cl_template  => 'default',
        reg_start    => $string{reg_start},
        reg_end      => $string{reg_end},
        prog_start   => $string{prog_start},
        prog_end     => $string{prog_end},
    };
    $c->stash->{canpol_opts} = [ model($c, 'CanPol')->search(
        undef,
        { order_by => 'name' },
    ) ];
    $c->stash->{housecost_opts} =
        [ model($c, 'HouseCost')->search(
            undef,
            { order_by => 'name' },
        ) ];
    $c->stash->{template_opts} = [
        grep { $_ eq "default" || ! sys_template($_) }
        map { s{^.*templates/web/(.*)[.]html$}{$1}; $_ }
        <root/static/templates/web/*.html>
    ];
    $c->stash->{cl_template_opts} = [
        map { s{^.*templates/letter/(.*)[.]tt2$}{$1}; $_ }
        <root/static/templates/letter/*.tt2>
    ];
    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "program/create_edit.tt2";
}

my %readable = (
    sdate   => 'Start Date',
    edate   => 'End Date',
    tuition => 'Tuition',
    deposit => 'Deposit',
    name    => 'Name',
    title   => 'Title',
    full_tuition => 'Full Tuition',
    extradays    => 'Extra Days',
);
my %hash;
my @mess;
sub _get_data {
    my ($c) = @_;

    %hash = %{ $c->request->params() };
    # since unchecked boxes are not sent...
    for my $f (qw/
        collect_total
        kayakalpa
        sbath
        retreat
        economy
        webready
        quad
        linked
    /) {
        $hash{$f} = "" unless exists $hash{$f};
    }
    $hash{url} =~ s{^\s*http://}{};

    @mess = ();
    if (! $hash{linked}) {
        if ($hash{ptemplate} eq 'default') {
            push @mess, "Unlinked programs cannot use the standard template.";
        }
        if (empty($hash{unlinked_dir})) {
            push @mess, "Missing unlinked directory name";
        }
        elsif ($hash{unlinked_dir} =~ m{[^\w_.-]}) {
            push @mess, "Illegal unlinked directory name";
        }
    }
    for my $f (qw/ name title /) {
        if ($hash{$f} !~ m{\S}) {
            push @mess, "$readable{$f} cannot be blank";
        }
    }
    # dates are converted to d8 format
    my ($sdate, $edate);
    if (empty($hash{sdate})) {
        push @mess, "Missing Start Date";
    }
    else {
        $sdate = date($hash{sdate});
        if (! $sdate) {
            push @mess, "Invalid Start Date: $hash{sdate}";
        }
        else {
            $hash{sdate} = $sdate->as_d8();
            Date::Simple->relative_date($sdate);
            if (empty($hash{edate})) {
                push @mess, "Missing End Date";
            }
            else {
                $edate = date($hash{edate});
                if (! $edate) {
                    push @mess, "Invalid End Date: $hash{edate}";
                }
                else {
                    $hash{edate} = $edate->as_d8();
                }
            }
            Date::Simple->relative_date();
        }
    }

    if (!@mess && $sdate && $sdate > $edate) {
        push @mess, "End Date must be after the Start Date";
    }
    # check for numbers
    for my $f (qw/
        extradays tuition full_tuition deposit
    /) {
        if ($hash{$f} !~ m{^\s*\d+\s*$}) {
            push @mess, "$readable{$f} must be a number";
        }
    }
    if ($hash{extradays}) {
        if ($hash{full_tuition} <= $hash{tuition}) {
            push @mess, "Full Tuition must be more than normal Tuition.";
        }
    }
    else {
        $hash{full_tuition} = 0;    # it has no meaning if > 0.
    }
    if ($hash{footnotes} =~ m{[^\*%+]}) {
        push @mess, "Footnotes can only contain *, % and +";
    }
    for my $t (qw/
        reg_start
        reg_end
        prog_start
        prog_end
    /) {
        my $time = $hash{$t};
        my ($hour, $min) = (-1, -1);
        if ($time =~ m{^\s*(\d+\s*[ap][.]?m[.]?)$}) {
            $hour = $1;
            $min = 0;
        }
        elsif ($time =~ m{^\s*(\d+):(\d+)\s*[ap][.]?m[.]?$}) {
            $hour = $1;
            $min = $2;
        }
        if (! (   1 <= $hour && $hour <= 12
               && 0 <= $min  && $min  <= 59)
        ) {
            push @mess, "Illegal time: $time";
        }
    }
    my @email = split m{[, ]+}, $hash{notify_on_reg};
    for my $em (@email) {
        if (! valid_email($em)) {
            push @mess, "Illegal email address: $em";
        }
    }
    $hash{notify_on_reg} = "@email";

    if (! empty($hash{max}) && $hash{max} !~ m{^\s*\d+\s*$}) {
        push @mess, "Max must be an integer";
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "program/error.tt2";
    }
}

sub create_do : Local {
    my ($self, $c) = @_;

    _get_data($c);
    return if @mess;

    delete $hash{section};      # irrelevant

    # gl num is computed not gotten
    $hash{glnum} = ($hash{name} =~ m{personal\s+retreat}i)?
                        '99999': compute_glnum($c, $hash{sdate});

    $hash{reg_count} = 0;       # otherwise it will not increment

    my $upload = $c->request->upload('image');
    my $sum = model($c, 'Summary')->create({
        date_updated => tt_today($c)->as_d8(),
        who_updated  => $c->user->obj->id,
        time_updated => sprintf "%02d:%02d", (localtime())[2, 1],
    });
    my $p = model($c, 'Program')->create({
        summary_id => $sum->id,
        image      => $upload? "yes": "",
        %hash,
    });
    my $id = $p->id();
    if ($upload) {
        $upload->copy_to("root/static/images/po-$id.jpg");
        Global->init($c);
        resize('p', $id);
    }
    #
    # we must ensure that we have config records
    # out to the end of this program + 30 days.
    # we add 30 days because registrations for Personal Retreats
    # may extend beyond the last day of the season.
    #
    add_config($c, date($hash{edate}) + $hash{extradays} + 30);
    $c->response->redirect($c->uri_for("/program/view/$id"));
}

my @day_name = qw/
    Sun
    Mon
    Tue
    Wed
    Thu
    Fri
    Sat
/;
sub view : Local {
    my ($self, $c, $id, $section) = @_;

    $section ||= 1;
    $c->stash->{section} = $section;

    Global->init($c);       # for web_addr if nothing else.
    my $p = $c->stash->{program} = model($c, 'Program')->find($id);
    my $extra = $p->extradays();
    if ($extra) {
        my $edate2 = $p->edate_obj() + $extra;
        $c->stash->{plus} = "<b>Plus</b> $extra day"
                          . ($extra > 1? "s": "")
                          . " <b>To</b> " . $edate2
                          . " <span class=dow>"
                          . $edate2->format("%a")
                          . "</span>"
                          ;
    }

    if ($p->name !~ m{personal retreats}i) {
        $c->stash->{lunch_table}
            = lunch_table(1,
                          $p->lunches,
                          $p->sdate_obj,
                          $p->edate_obj + $p->extradays
                         );
    }
    $c->stash->{daily_pic_date} = $p->sdate();
    $c->stash->{leaders_house} = $p->leaders_house($c);
    my $s = _get_cluster_groups($c, $id);
    my ($UN, $sel) = split /XX/, $s;
    $c->stash->{UNselected_clusters} = $UN;
    $c->stash->{selected_clusters}   = $sel;
    $c->stash->{template} = "program/view.tt2";
}

sub _get_cluster_groups {
    my ($c, $program_id) = @_;

    my @selected = model($c, 'ProgramCluster')->search(
        { program_id => $program_id },
        {
            order_by => 'seq',
            join     => 'cluster',
            prefetch => 'cluster',
        },
    );
    my $selected = "<tr><th align=center>Selected</th></tr>\n";
    my %select_lookup;
    my ($first_id, $last_id) = (-1, -1);
    if (@selected) {
        $first_id = $selected[ 0]->cluster_id();
        $last_id  = $selected[-1]->cluster_id();
    }
    for my $pc (@selected) {
        my $cid = $pc->cluster_id();
        $selected .=
           "<tr><td>"
           . $pc->seq()
           . ".&nbsp;"
           . "<a href='#' onclick='UNselect_cluster($cid); return false;'>"
           . $pc->cluster->name()
           . "</a>"
           . "</td><td>"
           . (
                ($cid != $first_id)?
                    "<a href='#' onclick='cluster_up($cid); return false'"
                    . ">&nbsp;<img src=/static/images/green_up_arrow.gif border=0></a>"
                :   "&nbsp;"
             )
           . "</td><td>"
           . (
                ($cid != $last_id )?
                    "<a href='#' onclick='cluster_down($cid); return false'"
                    . ">&nbsp;<img src=/static/images/red_down_arrow.gif border=0></a>"
                :   "&nbsp;"
             )
           . "</td></tr>\n"
           ;
        $select_lookup{$cid} = 1;
    }
    my $UNselected = "<tr><th align=center>Not Selected</th></tr>\n";
    for my $cl (@clusters) {
        next if exists $select_lookup{$cl->id()};
        $UNselected .=
                    "<tr><td>"
                    . "<a href='#' onclick='select_cluster("
                    . $cl->id()
                    . "); return false;'"
                    . ">"
                    . $cl->name()
                    . "</a>"
                    . "</td></tr>\n"
                    ;
    }
    return "<table>\n$UNselected</table>XX<table>\n$selected</table>";
}

#
# ??? order of display?   also end date???
#
sub list : Local {
    my ($self, $c) = @_;

    my $today = tt_today($c)->as_d8();
    $c->stash->{programs} = [
        model($c, 'Program')->search(
            { edate => { '>=', $today } },
            { order_by => 'sdate' },
        )
    ];
    my @files = <root/static/online/*>;
    $c->stash->{online} = scalar(@files);
    $c->stash->{pr_pat} = "";
    $c->stash->{template} = "program/list.tt2";
}

# ??? order of display?   also end date???
sub listpat : Local {
    my ($self, $c) = @_;

    my $today = tt_today($c)->as_d8();
    my $pr_pat = trim($c->request->params->{pr_pat});
    if (empty($pr_pat)) {
        $c->forward('list');
        return;
    }
    my $cond;
    if ($pr_pat =~ m{(^[fs])(\d\d)}i) {
        my $seas = $1;
        my $year = $2;
        $seas = lc $seas;
        if ($year > 70) {
            $year += 1900;
        }
        else {
            $year += 2000;
        }
        my ($d1, $d2);
        if ($seas eq 'f') {
            $d1 = $year . '1001';
            $d2 = ($year+1) . '0331';
        }
        else {
            $d1 = $year . '0401';
            $d2 = $year . '0930';
        }
        $cond = {
            sdate => { 'between' => [ $d1, $d2 ] },
        };
    }
    elsif ($pr_pat =~ m{((\d\d)?\d\d)}) {
        my $year = $1;
        if ($year > 70 && $year <= 99) {
            $year += 1900;
        }
        elsif ($year < 70) {
            $year += 2000;
        }
        $cond = {
            sdate => { 'between' => [ "${year}0101", "${year}1231" ] },
        };
    }
    else {
        my $pat = $pr_pat;
        $pat =~ s{\*}{%}g;
        $cond = {
            name => { 'like' => "${pat}%" },
        };
    }
    $c->stash->{programs} = [
        model($c, 'Program')->search(
            $cond,
            { order_by => 'sdate' },
        )
    ];
    $c->stash->{pr_pat} = $pr_pat;
    my @files = <root/static/online/*>;
    $c->stash->{online} = scalar(@files);
    $c->stash->{template} = "program/list.tt2";
}

sub update : Local {
    my ($self, $c, $id, $section) = @_;

    $section ||= 1;
    $c->stash->{section} = $section;

    my $p = model($c, 'Program')->find($id);
    $c->stash->{program} = $p;
    for my $w (qw/
        sbath collect_total kayakalpa retreat
        economy webready quad linked
    /) {
        $c->stash->{"check_$w"}  = ($p->$w)? "checked": "";
    }
    for my $w (qw/ sdate edate /) {
        $c->stash->{$w} = date($p->$w) || "";
    }

    # get all cancellation policies
    $c->stash->{canpol_opts} = [ model($c, 'CanPol')->search(
        undef,
        { order_by => 'name' },
    ) ];
    # and housing costs
    $c->stash->{housecost_opts} =
        [ model($c, 'HouseCost')->search(
            undef,
            { order_by => 'name' },
        ) ];
    # templates
    $c->stash->{template_opts} = [
        grep { $_ eq "default" || ! sys_template($_) }
        map { s{^.*templates/web/(.*)[.]html$}{$1}; $_ }
        <root/static/templates/web/*.html>
    ];
    # confirmation letter templates
    $c->stash->{cl_template_opts} = [
        map { s{^.*templates/letter/(.*)[.]tt2$}{$1}; $_ }
        <root/static/templates/letter/*.tt2>
    ];

    $c->stash->{edit_gl}     = $c->check_user_roles('super_admin');
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "program/create_edit.tt2";
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    _get_data($c);
    return if @mess;

    my $section = $hash{section};
    delete $hash{section};

    if (! $c->check_user_roles('super_admin')) {
        delete $hash{glnum};
    }
    if (my $upload = $c->request->upload('image')) {
        $upload->copy_to("root/static/images/po-$id.jpg");
        Global->init($c);
        resize('p', $id);
        $hash{image} = "yes";
    }
    my $p = model($c, 'Program')->find($id);
    my $names = "";
    my $lunches = 0;
    if (   $p->sdate ne $hash{sdate}
        || $p->edate ne $hash{edate}
        || $p->max   < $hash{max}
    ) {
        # invalidate the bookings as the dates/max have changed
        my @bookings = model($c, 'Booking')->search({
            program_id => $id,
        });
        #
        # if only the max changed then we can keep the bookings
        # of meeting places that are still able to accomodate
        # the new max.
        #
        if (   $p->sdate eq $hash{sdate}
            && $p->edate eq $hash{edate}
        ) {
            @bookings = grep {
                            $_->meeting_place->max < $hash{max}
                        }
                        @bookings;
        }
        $names = join '<br>', map { $_->meeting_place->name } @bookings;
        for my $b (@bookings) {
            $b->delete();
        }
        if ($p->max >= $hash{max}) {
            # must have been a date
            $hash{lunches} = "";
        }
    }
    $p->update(\%hash);
    add_config($c, date($hash{edate}) + 30);
    if ($names) {
        $c->stash->{program} = $p;
        $c->stash->{names} = $names;
        $c->stash->{lunches} = $lunches; 
        $c->stash->{template} = "program/mp_warn.tt2";
    }
    else {
        $c->response->redirect($c->uri_for("/program/view/"
                               . $p->id . "/$section"));
    }
}

sub leader_update : Local {
    my ($self, $c, $id) = @_;

    my $p = $c->stash->{program}
        = model($c, 'Program')->find($id);
    $c->stash->{leader_table} = leader_table($c, $p->leaders());
    $c->stash->{template} = "program/leader_update.tt2";
}

sub leader_update_do : Local {
    my ($self, $c, $prog_id) = @_;

    my $program = model($c, 'Program')->find($prog_id);
    my @cur_leaders = grep {  s{^lead(\d+)}{$1}  }
                      keys %{$c->request->params};
    # delete all old leaders and create the new ones.
    model($c, 'LeaderProgram')->search(
        { p_id => $prog_id },
    )->delete();
    for my $cl (@cur_leaders) {
        model($c, 'LeaderProgram')->create({
            l_id => $cl,
            p_id => $prog_id,
        });
    }
    #
    # ensure that the leaders are registered for the program.
    #
    my $new_regs = 0;
    for my $cl (@cur_leaders) {
        my $leader = model($c, 'Leader')->find($cl);
        my $assist = $leader->assistant();
        my $person_id = $leader->person->id();
        my ($reg) = model($c, 'Registration')->search({
            person_id  => $person_id,
            program_id => $prog_id,
        });
        if (! $reg) {
            # need to register them
            # we will house them later...
            #
            my $edate = date($program->edate()) + $program->extradays();
            model($c, 'Registration')->create({
                person_id  => $person_id,
                program_id => $prog_id,
                comment    => $assist? "1-dbl assistant"
                              :        "1-sgl/ba leader",
                house_id   => 0,
                h_type     => $assist? "dble": "single_bath",
                cancelled  => '',    # to be sure
                arrived    => '',    # ditto
                date_start => $program->sdate(),
                date_end   => $edate->as_d8(),
                balance    => 0,
                leader_assistant => 'yes',      # only way to set this
            });
            ++$new_regs;
        }
    }
    if ($new_regs) {
        $program->update({
            reg_count => $program->reg_count() + $new_regs,
        });
    }
    $c->response->redirect($c->uri_for("/program/view/$prog_id/4"));
}

sub affil_update : Local {
    my ($self, $c, $id) = @_;

    my $p = $c->stash->{program} = model($c, 'Program')->find($id);
    $c->stash->{affil_table} = affil_table($c, $p->affils());
    $c->stash->{template} = "program/affil_update.tt2";
}

sub affil_update_do : Local {
    my ($self, $c, $id) = @_;

    my @cur_affils = grep {  s{^aff(\d+)}{$1}  }
                     keys %{$c->request->params};
    # delete all old affils and create the new ones.
    model($c, 'AffilProgram')->search(
        { p_id => $id },
    )->delete();
    for my $ca (@cur_affils) {
        model($c, 'AffilProgram')->create({
            a_id => $ca,
            p_id => $id,
        });
    }
    my $p = model($c, 'Program')->find($id);
    if ($p->extradays) {
        # and ditto for the full program
        model($c, 'AffilProgram')->search(
            { p_id => $id + 1 },
        )->delete();
        for my $ca (@cur_affils) {
            model($c, 'AffilProgram')->create({
                a_id => $ca,
                p_id => $id + 1,
            });
        }
    }
    $c->response->redirect($c->uri_for("/program/view/$id/4"));
}

#
# how about a max for a program???
#
sub meetingplace_update : Local {
    my ($self, $c, $id) = @_;

    my $p = $c->stash->{program} = model($c, 'Program')->find($id);
    my $edate = $p->edate;
    if ($p->extradays) {
        $edate += $p->extradays;
    }
    $c->stash->{meetingplace_table}
        = meetingplace_table($c, $p->max, $p->sdate, $edate, $p->bookings());
    $c->stash->{template} = "program/meetingplace_update.tt2";
}

sub meetingplace_update_do : Local {
    my ($self, $c, $id) = @_;

    my $p = model($c, 'Program')->find($id);
    my $edate = $p->edate;
    if ($p->extradays) {
        $edate += $p->extradays;
    }
    my @cur_mps;
    my %seen = ();
    for my $k (sort keys %{$c->request->params}) {
        #
        # keys are like this:
        #     mp45
        # or
        #     mpbr23
        # all mp come before any mpbr
        #
        my ($d) = $k =~ m{(\d+)};
        my $br = ($k =~ m{br})? 'yes': '';
        push @cur_mps, [ $d, $br ] unless $seen{$d}++;
    }
    # delete all old bookings and create the new ones.
    model($c, 'Booking')->search(
        { program_id => $id },
    )->delete();
    for my $mp (@cur_mps) {
        model($c, 'Booking')->create({
            meet_id    => $mp->[0],
            program_id => $id,
            rental_id  => 0,
            event_id   => 0,
            sdate      => $p->sdate,
            edate      => $edate,
            breakout   => $mp->[1],
        });
    }
    $c->response->redirect($c->uri_for("/program/view/$id/4"));
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    my $p = model($c, 'Program')->find($id);

    # affiliation/programs
    model($c, 'AffilProgram')->search({
        p_id => $id,
    })->delete();

    # leader/programs
    model($c, 'LeaderProgram')->search({
        p_id => $id,
    })->delete();

    # exceptions
    $p->exceptions()->delete();

    # any bookings
    model($c, 'Booking')->search({
        program_id => $id,
    })->delete();

    # any image
    unlink <root/static/images/p*-$id.jpg>;

    # and finally, the program itself
    $p->delete();

    $c->response->redirect($c->uri_for('/program/list'));
}

sub del_image : Local {
    my ($self, $c, $id) = @_;

    my $p = $c->stash->{program}
        = model($c, 'Program')->find($id);
    $p->update({
        image => "",
    });
    unlink <root/static/images/p*-$id.jpg>;
    $c->response->redirect($c->uri_for("/program/view/$id/1"));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

my @programs;
my %except;

#
# shall we provide some entertainment while
# the ftp'ing is happening???  how to do that?
# some Javascript and some way of not using
# a template at the end with the results
# but to show the incremental progress.
#
sub publish : Local {
    my ($self, $c) = @_;

    # clear the arena
    system("rm -rf gen_files; mkdir gen_files; mkdir gen_files/pics");

    # and make sure we have initialized %string.
    Global->init($c);

    #
    # get all the programs into an array
    # sorted by start date and then end date.
    # ???this seems to work but I suspect there is
    # a better way to do this???  
    # Can I do model($c, 'Program')->future_programs()???
    # No.
    #
    @programs = RetreatCenterDB::Program->future_programs($c);

    gen_month_calendars($c);
    gen_regtable();

    #
    # get ALL the exceptions
    #
    for my $e (model($c, 'Exception')->all()) {
        $except{$e->prog_id}{$e->tag} = expand($e->value);
    }

    # 
    # generate each of the program pages
    #
    # a side effect will be to copy the pictures of
    # the leaders or the program picture
    # to the holding area.
    #
    my @unlinked;
    my $tag_regexp = '<!--\s*T\s+(\w+)\s*-->';
    for my $p (@programs) {
        my $fname = $p->fname();
        open my $out, ">", "gen_files/$fname"
            or die "cannot create $fname: $!\n";
        my $copy = $p->template_src();
        $copy =~ s{$tag_regexp}{
            $except{$p->id}{$1} || $p->$1()
        }xge;
        print {$out} $copy;
        close $out;
        if (! $p->linked) {
            push @unlinked, $p;
        }
    }

    #
    # generate the program and event calendars
    #
    my $events = "";
    my $programs = "";

    my $progRow     = slurp "progRow";
    my $e_progRow   = slurp "e_progRow";
    my $e_rentalRow = slurp "e_rentalRow";

    my $cur_event_month = 0;
    my $cur_prog_month = 0;
    my ($rental);
    my @rentals  = RetreatCenterDB::Rental->future_rentals($c);
    for my $e (sort {
                   $a->sdate <=> $b->sdate
                   or
                   $a->edate <=> $b->edate
               }
               grep {
                   $_->linked
               }
               @programs,
               @rentals
    ) {
        $rental = (ref($e) =~ m{Rental$});
        my $sdate = $e->sdate_obj;
        my $smonth = $sdate->month;
        my $my = monthyear($sdate);
        if ($cur_event_month != $smonth) {
            $events .= "<tr><td class='event_my_row' colspan=2>$my</td></tr>\n";
            $cur_event_month = $smonth;
        }
        if (not $rental and $cur_prog_month != $smonth) {
            $programs .= "<tr><td class='prog_my_row' colspan=2>$my</td></tr>\n";
            $cur_prog_month = $smonth;
        }
        if ($rental) {
            my $copy = $e_rentalRow;
            $copy =~ s/$tag_regexp/
                $e->$1()        # no exception for rentals here - okay???
            /xge;
            $events .= $copy;
        }
        else {
            my $copy = $e_progRow;
            $copy =~ s/$tag_regexp/
                $except{$e->id}{$1} || $e->$1()
            /xge;
            $events .= $copy;

            $copy = $progRow;
            $copy =~ s/$tag_regexp/
                $except{$e->id}{$1} || $e->$1()
            /xge;
            $programs .= $copy;
        }
    }
    #
    # we have gathered all the info.
    # now to insert it in the templates and output
    # the .html files for the program and event lists.
    #
    my $s;

    open my $out, ">", "gen_files/events.html"
        or die "cannot create events.html: $!\n";
    $s = slurp "events";
    $s =~ s/<!--\s*T\s+eventlist.*-->/$events/;
    $s =~ s/$tag_regexp/ RetreatCenterDB::Program->$1() /xge;
    print {$out} $s;
    close $out;

    undef $out;
    open $out, ">", "gen_files/programs.html"
        or die "cannot create programs.html: $!\n";
    $s = slurp "programs";
    $s =~ s/<!--\s*T\s+programlist.*-->/$programs/;
    $s =~ s/$tag_regexp/ RetreatCenterDB::Program->$1() /xge;
    print {$out} $s;
    close $out;

    #
    # schmush around the unlinked programs
    #
    for my $ulp (@unlinked) {
        my $dir = $ulp->unlinked_dir;
        mkdir "gen_files/$dir";
        mkdir "gen_files/$dir/pics";
        rename "gen_files/" . $ulp->fname,
               "gen_files/$dir/index.html";
        copy "gen_files/regtable",
             "gen_files/$dir/regtable";
        # now for the pictures and the associated html files...
        my $src = slurp("gen_files/$dir/index.html");
        my @img = $src =~ m{pics/(.*?(?:jpg|gif))}g;
        for my $im (@img) {
            copy "gen_files/pics/$im",   # not move.
                 "gen_files/$dir/pics/$im";
                                        # it is POSSIBLE for a leader
                                        # to lead both a linked and an
                                        # unlinked program.
            my $pic = $im;
            $pic =~ s{gen_files/pics/}{};
            $pic =~ s{th}{b};
            copy "gen_files/pics/$pic",   # not move.
                 "gen_files/$dir/pics/$pic";
            copy "gen_files/$pic.html",
                 "gen_files/$dir/$pic.html";
        }
    }
    #
    # remove the temporary calX.html files
    #
    unlink <root/static/templates/web/cal?.html>;

    #
    # finally, ftp all generated pages to www.mountmadonna.org
    # or whereever Global says, that is...
    #
    my $ftp = Net::FTP->new($string{ftp_site}, Passive => $string{ftp_passive})
        or die "cannot connect to ...";    # not die???
    $ftp->login($string{ftp_login}, $string{ftp_password})
        or die "cannot login ", $ftp->message; # not die???
    $ftp->cwd($string{ftp_dir})
        or die "cannot cwd ", $ftp->message; # not die???
    $ftp->cwd($string{ftp_dir2});
    for my $f ($ftp->ls()) {
        $ftp->delete($f) if $f ne 'pics';
    }
    $ftp->ascii();
    # dangerous to chdir - in case we die...
    # need to restore current directory.
    # die does not really die.  the server keeps running somehow.
    chdir "gen_files";
    FILE:
    for my $f (<*>) {
        if (-d $f) {
            next FILE if $f eq 'pics';
            # an unlinked program directory
            $ftp->mkdir("../$f");
            for my $hf (<$f/*.html>) {
                $ftp->put($hf, "../$hf")
                    or die "cannot put $hf to ../$hf";
            }
            $ftp->mkdir("../$f/pics");
            for my $p (<$f/pics/*>) {
                $ftp->put($p, "../$p")
                    or die "cannot put $p to ../$p";
            }
            $ftp->put("$f/regtable", "../$f/regtable")
                    or die "cannot put $f/regtable to ../$f/regtable";
        }
        else {
            $ftp->put($f)
                or die "cannot put $f: " . $ftp->message; # not die???
        }
    }
    $ftp->quit();
    chdir "..";
    $c->stash->{ftp_dir2} = $string{ftp_dir2};
    $c->stash->{unlinked} = \@unlinked;
    $c->stash->{template} = "program/published.tt2";
}

sub publish_pics : Local {
    my ($self, $c) = @_;

    Global->init($c);
    my $ftp = Net::FTP->new($string{ftp_site}, Passive => $string{ftp_passive})
        or die "cannot connect to ...";    # not die???
    $ftp->login($string{ftp_login}, $string{ftp_password})
        or die "cannot login ", $ftp->message; # not die???
    #
    # this assumes pics/ is there...
    #
    $ftp->cwd("$string{ftp_dir}/$string{ftp_dir2}/pics")
        or die "cannot cwd ", $ftp->message; # not die???
    for my $f ($ftp->ls()) {
        $ftp->delete($f);
    }
    $ftp->binary();
    chdir "gen_files/pics";
    for my $f (<*.jpg>) {
        $ftp->put($f)
            or die "cannot put $f"; # not die???
    }
    $ftp->quit();
    chdir "../..";
    $c->stash->{pics} = 1;
    my @unlinked = grep { ! $_->linked }
                   RetreatCenterDB::Program->future_programs($c);
    $c->stash->{unlinked} = \@unlinked;
    $c->stash->{ftp_dir2} = $string{ftp_dir2};
    $c->stash->{template} = "program/published.tt2";
}

sub brochure : Local {
    my ($self, $c) = @_;

    # make a guess at the season we are generating.
    my $d = tt_today($c);
    my $m = $d->month();
    my $y = $d->year() % 100;
    my $seas;
    if (4 <= $m && $m <= 9) {
        $seas = 'f';
    }
    else {
        $seas = 's';
        ++$y if 10 <= $m && $m <= 12;
    }
    $c->stash->{season} = sprintf "$seas%02d", $y;
    $c->stash->{fee_page} = 11;
    $c->stash->{template} = "program/brochure.tt2";
}

sub brochure_do : Local {
    my ($self, $c) = @_;

    my $season   = $c->request->params->{season};
    my ($bdate, $edate);
    if (my ($s, $y) = $season =~ m{(^[fs])(\d\d)$}i) {
        $s = lc $s;
        $y += 2000;
        $bdate = ($s eq 'f')? $y."1001": $y."0401";
        $edate = ($s eq 'f')? ($y+1)."0331": $y."0930";
    }
    else {
        $c->stash->{mess} = "Invalid season.";
        $c->stash->{template} = "program/error.tt2";
        return;
    }
    my $fee_page = $c->request->params->{fee_page};
    if ($fee_page !~ m{^\d+$}) {
        $c->stash->{mess} = "Invalid fee page number.";
        $c->stash->{template} = "program/error.tt2";
        return;
    }
    my $fname = "root/static/brochure.txt";
    open my $br, ">", $fname
        or die "cannot create $fname";
    my $n = 0;
    for my $p (model($c, 'Program')->search(
                   {
                       sdate => { 'between' => [ $bdate, $edate ] },
                       linked => 'yes',
                       webready => 'yes',
                   },
                   { order_by => 'sdate' },
               ))
    {
        ++$n;
        print {$br} "\@date:<\$>", $p->dates3, "\n";
        print {$br} "\@wkshop intro<\$>", $p->title, "\n";
        print {$br} "\@wkshop<\$>", $p->subtitle, "\n";
        my $s = $p->leader_names;
        if ($s) {
            print {$br} "\@presenter<\$>$s\n";
        }
        print {$br} "\@initial paragraph<\$>",
            expand2(($p->brdesc)? $p->brdesc: $p->webdesc);
        $s = expand2($p->leader_bio);
        if ($s) {
            print {$br} "\@text<\$>$s";
        }
	    print {$br} "<B>Tuition \$" . $p->tuition
                  . "</B>, plus fees (see page $fee_page)\n";
        print {$br} "<\\c>";
    }
    if ($n == 0) {
        print {$br} "No programs in season \U$season.\n";
    }
    close $br;
    $fname =~ s{root}{};
    $c->response->redirect($c->uri_for($fname));
}

#
# go through the programs in ascending date order
# and create the monthly calendar files calX.html
# where X is the month number.
#
# skip the unlinked ones
#
# clear them first? or after using them???
#
sub gen_month_calendars {
    my ($c) = @_;
    my $cur_month = 0;
    my $cal;
    for my $p (grep { $_->linked } @programs) {
        my $m = $p->sdate_obj->month;
        if ($m != $cur_month) {
            # finish the prior calendar file, if any
            if ($cur_month) {
                print {$cal} "</table>\n";
                close $cal;
                undef $cal;
            }
            # start a new calendar file
            $cur_month = $m;
            undef $cal;
            open $cal, ">", "root/static/templates/web/cal$m.html"
                or die "cannot create cal$m.html: $!\n";
            my $my = monthyear($p->sdate_obj);
            print {$cal} <<EOH;
<table class='caltable'>
<tr><td class="monthyear" colSpan=2>$my</td></tr>
EOH
        }
        # the program info itself
        print {$cal} "<tr>\n<td class='dates_tr'>",
                  $p->dates_tr, "</td>",
                  "<td class='title'><a href='",
                  $p->fname, "'>",
                  $p->title1, 
                  "</a><br><span class='subtitle'>",
                  $except{$p->id}{title2} || $p->title2,
                  "</span></td></tr>";
    }
    # finish the prior calendar file, if any
    if ($cur_month) {
        print {$cal} "</table>\n";
        close $cal;
    }
}

#
# generate the regtable for online registration
#
sub gen_regtable {
    open my $regt, ">", "gen_files/regtable"
        or die "cannot create regtable: $!\n";
    for my $p (@programs) {
        my $ndays = ($p->edate_obj - $p->sdate_obj) || 1;	# personal retreats
        my $fulldays = $ndays + $p->extradays;

        #
        # pid should be first for looking up purposes.
        #
        print {$regt} "pid\t",     $p->id, "\n";
        print {$regt} "pname\t",   $p->name, "\n";
        print {$regt} "desc\t",    $p->title, "\n";
        print {$regt} "dates\t",   $p->dates, "\n";
        print {$regt} "edate\t",   $p->edate, "\n";
        print {$regt} "leaders\t", $p->leader_names, "\n";
        print {$regt} "footnotes\t", $p->footnotes, "\n";
        print {$regt} "ndays\t$ndays\n";
        print {$regt} "fulldays\t$fulldays\n";
        print {$regt} "deposit\t", $p->deposit, "\n";
        print {$regt} "colltot\t", $p->collect_total, "\n";
        my $pol = $p->cancellation_policy();
        $pol =~ s/\n/NEWLINE/g;
        print {$regt} "canpol\t$pol\n";

        my $tuition      = $p->tuition;
        my $full_tuition = $p->full_tuition;
        my $month        = $p->sdate_obj->month;

        my $housecost = $p->housecost;
        for my $t (housing_types()) {
            next if $t =~ /unknown/;
            next if $t =~ /quad/        && !$p->quad;
            next if $t =~ /economy/     && !$p->economy;
            next if $t =~ /single_bath/ && !$p->sbath;
            next if $t =~ /center_tent/
                && !($p->name =~ m{personal\s+retreat}i
                     || $p->name =~ m{tnt}i
                     || (5 <= $month && $month <= 10));
            next if $t =~ m{triple|dormitory}
                    && $p->name =~ m{personal\s+retreat}i;
            (my $tt = $t) =~ s{_}{ }g;
            my $fees = $p->fees(0, $t);
            next if $fees == 0;    # another way to eliminate a housing option 
            print {$regt} "basic $tt\t$fees\n";
            if ($p->extradays) {
                print {$regt} "full $tt\t", $p->fees(1, $t), "\n";
            }
        }
    }
    close $regt;
}

sub update_lunch : Local {
    my ($self, $c, $id) = @_;

    my $p = model($c, 'Program')->find($id);
    $c->stash->{program} = $p;
    $c->stash->{lunch_table} = lunch_table(0,
                                           $p->lunches,
                                          $p->sdate_obj,
                                          $p->edate_obj + $p->extradays);
    $c->stash->{template} = "program/update_lunch.tt2";
}

sub update_lunch_do : Local {
    my ($self, $c, $id) = @_;

    %hash = %{ $c->request->params() };
    my $p = model($c, 'Program')->find($id);
    my $ndays = $p->edate_obj - $p->sdate_obj + 1 + $p->extradays;
    my $l = "";
    for my $n (0 .. $ndays-1) {
        $l .= (exists $hash{"d$n"})? "1": "0";
    }
    $p->update({
        lunches => $l,
    });
    $c->response->redirect($c->uri_for("/program/view/$id/2"));
}

# should duplicate ONLY ask for new dates?
# no.   this is the time to change things from the old one.
sub duplicate : Local {
    my ($self, $c, $id) = @_;
    my $orig_p = model($c, 'Program')->find($id);

    # the image takes some special handling
    # in the initial duplication dialog we want to indicate
    # what the image _will_ be if we would take the image
    # from the original program - but that image (the dup'ed one)
    # does not yet exist.   We may abort the duplication process,
    # we may upload a different image for the dup'ed program.
    # if we want to not have an image at all in the dup'ed program
    # we'll need to accept the old when creating the dup
    # and THEN delete it.
    if ($orig_p->image()) {
        $c->stash->{dup_image} = $orig_p->image_file();
    }

    # things that are different from the original:
    $orig_p->set_columns({
        id      => undef,
        sdate   => "",
        edate   => "",
        lunches => "",
        glnum   => "",
        image   => "",      # not yet
    });
    for my $w (qw/
        sbath collect_total kayakalpa retreat
        economy webready quad linked
    /) {
        $c->stash->{"check_$w"}  = ($orig_p->$w)? "checked": "";
    }
    # get all cancellation policies
    $c->stash->{canpol_opts} = [ model($c, 'CanPol')->search(
        undef,
        { order_by => 'name' },
    ) ];
    # and housing costs
    $c->stash->{housecost_opts} =
        [ model($c, 'HouseCost')->search(
            undef,
            { order_by => 'name' },
        ) ];
    # templates
    $c->stash->{template_opts} = [
        grep { $_ eq "default" || ! sys_template($_) }
        map { s{^.*templates/web/(.*)[.]html$}{$1}; $_ }
        <root/static/templates/web/*.html>
    ];
    # confirmation letter templates
    $c->stash->{cl_template_opts} = [
        map { s{^.*templates/letter/(.*)[.]tt2$}{$1}; $_ }
        <root/static/templates/letter/*.tt2>
    ];
    $c->stash->{section}             = 2;   # Web (a required field)
    $c->stash->{edit_gl} = 0;

    $c->stash->{program} = $orig_p;      # with modifed columns
    $c->stash->{form_action} = "duplicate_do/$id";
    $c->stash->{dup_message} = " - <span style='color: red'>Duplication</span>";
        # forgive me for putting html/css here!
        # i didn't want the dash '-' to be red
        # and the dash shouldn't be there if there's no message...
        # I could have done a conditional in the template
        # but that would be more complex, yes?
    $c->stash->{template}    = "program/create_edit.tt2";
}

#
# duplicated code here from create_do - can we not repeat ourself - DRY???
# should we?   let's not worry about that for now.
# there are several extra things that a duplication requires.
#
sub duplicate_do : Local {
    my ($self, $c, $old_id) = @_;
    _get_data($c);
    return if @mess;
    delete $hash{section};      # irrelevant

    # gl num is computed not gotten
    $hash{glnum} = ($hash{name} =~ m{personal\s+retreat}i)?
                        '99999': compute_glnum($c, $hash{sdate});

    $hash{reg_count} = 0;       # otherwise it will not increment

    # get the old program and the old summary
    my ($old_prog)    = model($c, 'Program')->find($old_id);
    my ($old_summary) = $old_prog->summary();

    my $sum = model($c, 'Summary')->create({
        $old_summary->get_columns(),        # to dup the old ...
        id => undef,                        # with a new id
        date_updated => tt_today($c)->as_d8(),   # and new update status info
        who_updated  => $c->user->obj->id,
        time_updated => sprintf "%02d:%02d", (localtime())[2, 1],
    });

    # the image takes special handling
    # if a new one is provided, take that.
    # otherwise use the old one, if any.
    #
    my $upload = $c->request->upload('image');

    # now we can create the new dup'ed program
    my $new_p = model($c, 'Program')->create({
        summary_id => $sum->id,
        image      => ($upload || $old_prog->image())? "yes": "",
        %hash,
    });

    my $new_id = $new_p->id();

    # mess with the new image, if any.
    if ($upload) {
        $upload->copy_to("root/static/images/po-$new_id.jpg");
        Global->init($c);
        resize('p', $new_id);
    }
    elsif ($new_p->image()) {
        # complicated! wake up.
        my $path = "root/static/images";
        my $suf = (-f "$path/po-$old_id.jpg")? "jpg": "gif";
        for my $let (qw/ b o th /) {
            copy "$path/p$let-$old_id.$suf",
                 "$path/p$let-$new_id.$suf";
        }
    }

    #
    # we must ensure that we have config records
    # out to the end of this program + 30 days.
    # we add 30 days because registrations for Personal Retreats
    # may extend beyond the last day of the season.
    #
    add_config($c, date($hash{edate}) + $hash{extradays} + 30);

    # copy the leaders and affils
    my @leader_programs = model($c, 'LeaderProgram')->search({
        p_id => $old_id,
    });
    for my $lp (@leader_programs) {
        model($c, 'LeaderProgram')->create({
            l_id => $lp->l_id(),
            p_id => $new_id,
        });
    }
    my @affil_programs = model($c, 'AffilProgram')->search({
        p_id => $old_id,
    });
    for my $ap (@affil_programs) {
        model($c, 'AffilProgram')->create({
            a_id => $ap->a_id(),
            p_id => $new_id,
        });
    }
    $c->response->redirect($c->uri_for("/program/view/$new_id"));
}

# AJAX call to select a cluster for this program
sub select_cluster : Local {
    my ($self, $c, $program_id, $cluster_id) = @_;

    # how many selected ones do we have now?
    # how to do a simple count?
    # scalar context?  _rs suffix?
    my (@pc) = model($c, 'ProgramCluster')->search({
        program_id => $program_id
    });
    model($c, 'ProgramCluster')->create({
        program_id => $program_id,
        cluster_id => $cluster_id,
        seq        => @pc + 1,
    });
    $c->res->output(_get_cluster_groups($c, $program_id));
}

# AJAX call to UNselect a cluster
sub UNselect_cluster : Local {
    my ($self, $c, $program_id, $cluster_id) = @_;

    my ($p_cl) = model($c, 'ProgramCluster')->search({
        program_id => $program_id,
        cluster_id => $cluster_id,
    });
    my $seq = $p_cl->seq();
    $p_cl->delete();
    model($c, 'ProgramCluster')->search({
        program_id => $program_id,
        seq        => { '>', $seq },
    })->update({
        seq => \'seq-1',
    });
    $c->res->output(_get_cluster_groups($c, $program_id));
}

# AJAX call to move a cluster UP
# e.g. if seq == 3 => swap 2 and 3.
sub cluster_up : Local {
    my ($self, $c, $program_id, $cluster_id) = @_;

    my ($p_cl3) = model($c, 'ProgramCluster')->search({
        program_id => $program_id,
        cluster_id => $cluster_id,
    });
    my $seq3 = $p_cl3->seq();
    my $seq2 = $seq3 - 1;
    my ($p_cl2) = model($c, 'ProgramCluster')->search({
        program_id => $program_id,
        seq        => $seq2,
    });
    $p_cl3->update({ seq => $seq2 });
    $p_cl2->update({ seq => $seq3 });
    $c->res->output(_get_cluster_groups($c, $program_id));
}

# AJAX call to move a cluster DOWN
# e.g. if seq == 3 => swap 3 and 4.
sub cluster_down : Local {
    my ($self, $c, $program_id, $cluster_id) = @_;

    my ($p_cl3) = model($c, 'ProgramCluster')->search({
        program_id => $program_id,
        cluster_id => $cluster_id,
    });
    my $seq3 = $p_cl3->seq();
    my $seq4 = $seq3 + 1;
    my ($p_cl4) = model($c, 'ProgramCluster')->search({
        program_id => $program_id,
        seq        => $seq4,
    });
    $p_cl3->update({ seq => $seq4 });
    $p_cl4->update({ seq => $seq3 });
    $c->res->output(_get_cluster_groups($c, $program_id));
}

# find the 'current' program - not a Personal Retreat
# and show the alphabetically first registrant.
sub cur_prog : Local {
    my ($self, $c) = @_;
    
    my $today_d8 = tt_today($c)->as_d8();
    my @progs = model($c, 'Program')->search(
        {
            edate => { '>=', $today_d8 },
            name  => { -not_like => "%personal%retreat%" },
        },
        {
            rows     => 1,
            order_by => 'sdate',
        },
    );
    if (@progs) {
        $c->response->redirect($c->uri_for("/registration/first_reg/"
                                           . $progs[0]->id()));
    }
    else {
        $c->response->redirect($c->uri_for("/program/list"));
    }
}

sub ceu : Local {
    my ($self, $c, $prog_id, $override_hours) = @_;    

    my $html = "";
    for my $r (model($c, 'Registration')->search({
                   program_id  => $prog_id,
                   ceu_license => { "!=", "" },
               }) 
    ) {
        $html .= ceu_license($r, $override_hours)
              .  "<div style='page-break-after:always'></div>\n"
              ;
    }
    if (! $html) {
        $html = "No one requested a CEU.";
    }
    $c->res->output($html);
}

1;
