use strict;
use warnings;
package RetreatCenter::Controller::Registration;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.
use Badge;
use Date::Simple qw/
    date
    today
/;
use Time::Simple qw/
    get_time
/;
use Util qw/
    nsquish
    digits
    model
    trim
    etrim
    empty
    email_letter
    type_max
    lines
    normalize
    tt_today
    ceu_license
    ceu_license_stash
    show_ceu_license
    commify
    wintertime
    long_term_registration
    stash
    error
    payment_warning
    housing_types
    ptrim
    other_reserved_cids
    PR_other_reserved_cids
    invalid_amount
    penny
    check_makeup_new
    check_makeup_vacate
    get_now
    rand6
    x_file_to_href
    add_or_update_deduping
    outstanding_balance
    charges_and_payments_options
    @charge_type
    cf_expand
    months_calc
    slurp
    time_travel_class
/;
use POSIX qw/
    ceil
/;
use HLog;

    # damn awkward to keep this Global thing initialized... :(
    # is there no way to do this better???
use Global qw/
    %string
    %house_name_of
    %houses_in
    %houses_in_cluster
    %system_affil_id_for
    @clusters
/;
use Template;
my $rst = "root/static";

my $TYPE_TUITION           = 1;
my $TYPE_MEALS_AND_LODGING = 2;
my $TYPE_OTHER             = 5;
my $TYPE_CEU_LICENSE_FEE   = 8;

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('/program/list');
}

#
# %dates may have date_start and date_end.
# set early and late accordingly.
# if no date_start or date_end insert them 
# as the program start/end dates.
#
sub transform_dates {
    my ($pr, %dates) = @_;

    my $PR = $pr->PR();
    
    if ($PR || ($dates{date_start} && $dates{date_start} ne $pr->sdate())) {
        $dates{early} = 'yes';
    }
    else {
        $dates{early}      = '';
        $dates{date_start} = $pr->sdate;
    }
    my $edate = $pr->edate();
    my $edate2 = (date($pr->edate()) + $pr->extradays())->as_d8();
        # edate2 may be different in case this is an 'extended' program.

    if ($dates{date_end}) {
        if ($PR ||
            ($dates{date_end} ne $edate
             && $dates{date_end} ne $edate2)
        ) {
            $dates{late} = 'yes';
        }
    }
    else {
        $dates{late}     = '';
        $dates{date_end} = $pr->edate;
    }
    %dates;
}

sub list_online : Local {
    my ($self, $c) = @_;

    my @online;
    for my $f (<$rst/online/*>) {
        open my $in, "<", $f
            or die "cannot open $f: $!\n";
        my ($date, $time, $first, $last, $pid, $synthesized,
            $sdate, $edate, $comment);
        $synthesized = 0;
        while (<$in>) {
            if (m{x_date => (.*)}) {
                $date = date($1);
            }
            elsif (m{x_sdate => (.*)}) {
                $sdate = date($1);
            }
            elsif (m{x_edate => (.*)}) {
                $edate = date($1);
            }
            elsif (m{x_time => (.*)}) {
                my $t = $1;
                # we know the time is 24 hour time
                $t =~ s/://;
                $time = get_time($t);
            }
            elsif (m{x_fname => (.*)}) {
                $first = normalize($1);
            }
            elsif (m{x_lname => (.*)}) {
                $last = normalize($1);
            }
            elsif (m{x_pid => (.*)}) {
                $pid = $1;
            }
            elsif (m{x_synthesized => 1}) {
                $synthesized = 1;
            }
            elsif (m{x_request\d+ => (.*)}) {
                my $req = $1;
                $req =~ s{'}{\\'}g;
                $comment .= "$req<br>";
            }
        }
        close $in;

        # space out any stray non-ASCII chars - source unknown
        $comment =~ s{\xa0}{ }xmsg if $comment;

        my $pname;
        if ($pid == 0) {
            $pname = "Personal Retreat";
        }
        else {
            my $pr = model($c, 'Program')->find($pid);
            if ($pr) {
                $pname = $pr->name();
            }
            else {
                $pname = "Unknown Program";
            }
        }
        my $arr_lv = "";
        if ($sdate && $edate) {
            # don't worry about the year, okay?
            if ($sdate->month == $edate->month) {
                # Jul 4-8
                $arr_lv = $sdate->format("%b %e") . "-" . $edate->day;
            }
            else {
                # Jul 30 - Aug 2
                $arr_lv = $sdate->format("%b %e") . " - " . $edate->format("%b %e");
            }
            $arr_lv = ("&nbsp;" x 4) . $arr_lv;     # space on left
                                                    # rather than hacking CSS
        }
        (my $fname = $f) =~ s{$rst/online/}{};
        push @online, {
            first   => $first,
            last    => $last,
            pname   => $pname,
            pid     => $pid,
            date    => $date,
            arr_lv  => $arr_lv,
            time    => $time,
            fname   => $fname,
            synth   => $synthesized,
            comment => $comment,
        };
    }
    @online = sort {
                  $a->{pname} cmp $b->{pname} or
                  $a->{date}  <=> $b->{date}  or
                  $a->{time}  <=> $b->{time}
              }
              @online;
    stash($c,
        online   => \@online,
        template => "registration/list_online.tt2",
    );
}

sub list_reg_name : Local {
    my ($self, $c, $prog_id) = @_;

    my $pat = $c->request->params->{pat} || "";
    $pat = trim($pat);
    $pat =~ s{\*}{%}g;
    my ($pref_last, $pref_first);
    if ($pat =~ m{(\S+)\s+(\S+)}) {
        ($pref_last, $pref_first) = ($1, $2);
    }
    else {
        $pref_last = $pat;
        $pref_first = "";
    }
    $pat =~ s{%}{*}g;       # put it back for display purposes

    my $pr = model($c, 'Program')->find($prog_id);

    # ??? dup'ed code in matchreg and list_reg_name
    # DRY??? don't repeat yourself!
    my @name_match = ();
    if ($pref_last) {
        push @name_match, 'person.last' => { like => "$pref_last%"  };
    }
    if ($pref_first) {
        push @name_match, 'person.first' => { like => "$pref_first%" };
    }
    my @regs = model($c, 'Registration')->search(
        {
            program_id     => $prog_id,
            @name_match,
        },
        {
            join     => [qw/ person /],
            order_by => [qw/ person.last person.first me.date_start /],
            prefetch => [qw/ person /],   
        }
    );
    if (@regs == 1) {
        my $r = $regs[0];
        my $pr = $r->program;
        if ($r->date_start <= tt_today($c)->as_d8()
            && $r->balance > 0
            && ! $r->cancelled
        ) {
            $c->response->redirect($c->uri_for("/registration/pay_balance/" .
                                   $r->id . "/list_reg_name"));
        }
        else {
            $c->response->redirect($c->uri_for("/registration/view/" .
                                   $r->id));
        }
        return;
    }
    Global->init($c);
    my @files = <$rst/online/*>;
    my $sdate = $pr->sdate();
    my $nmonths = int((date($pr->edate()) - date($sdate))/30) + 1;
    stash($c,
        time_travel_class($c),
        program         => $pr,
        pat             => $pat,
        daily_pic_date  => ($pr->category->name() eq "Normal"? "indoors"
                            :                                  "resident")
                            . "/$sdate",
        cluster_date    =>  $sdate,
        cal_param       => "$sdate/$nmonths",
        regs            => _reg_table($c, \@regs),
        other_sort      => "list_reg_post",
        other_sort_name => "By Postmark",
        online          => scalar(@files),
        badges          => ! $pr->PR(),
        template        => "registration/list_reg.tt2",
    );
}

sub list_reg_post : Local {
    my ($self, $c, $prog_id) = @_;

    my $pr = model($c, 'Program')->find($prog_id);
    my @regs = model($c, 'Registration')->search(
        {
            program_id     => $prog_id,
        },
        {
            join     => [qw/ person /],
            order_by => [qw/ date_postmark time_postmark /],
            prefetch => [qw/ person /],   
        }
    );
    for my $r (@regs) {
        $r->{date_mark} = date($r->date_postmark);
    }
    Global->init($c);
    my @files = <$rst/online/*>;
    stash($c,
        online          => scalar(@files),
        program         => $pr,
        regs            => _reg_table($c, \@regs, postmark => 1),
        other_sort      => "list_reg_name",
        other_sort_name => "By Name",
        template        => "registration/list_reg.tt2",
    );
}

#
# cancelled is not missing
#
sub list_reg_missing : Local {
    my ($self, $c, $prog_id) = @_;

    my $pr = model($c, 'Program')->find($prog_id);
    my @regs = model($c, 'Registration')->search(
        {
            program_id => $prog_id,
            arrived    => { '!=' => 'yes' },
            cancelled  => { '!=' => 'yes' },
        },
        {
            join     => [qw/ person /],
            order_by => [qw/ person.last person.first /],
            prefetch => [qw/ person /],   
        }
    );
    Global->init($c);
    my @files = <$rst/online/*>;
    stash($c,
        missing_count   => scalar(@regs) . " of ",
        online          => scalar(@files),
        program         => $pr,
        regs            => _reg_table($c, \@regs, postmark => 0),
        other_sort      => "list_reg_post",
        other_sort_name => "By Postmark",
        template        => "registration/list_reg.tt2",
    );
}

#
# an online registration via a file
#
sub get_online : Local {
    my ($self, $c, $fname) = @_;
    
    #
    # first extract all information from the file.
    #
    my $href = x_file_to_href("$rst/online/$fname");
    if (! exists $href->{pid}) {
        $c->response->redirect($c->uri_for("/registration/list_online"));
        return;
    }
    # save the filename so we can delete it when the registration is complete
    stash($c, fname => $fname);

    #
    # first, find the program
    # without it we can do nothing!
    #
    my $pr;
    if ($href->{pid} == 0) {
        # find the appropriate Personal Retreat given the start date
        #
        my $sdate = date($href->{sdate})->as_d8();
        ($pr) = model($c, 'Program')->search({
            name  => { -like => '%personal%retreat%' },
            sdate => { '<=' => $sdate },
            edate => { '>=' => $sdate },
        });
        if ($pr) {
            $href->{pid} = $pr->id();
        }
        else {
            error($c,
                <<"EOH",
There is no Personal Retreat Program for $href->{sdate}.
<p class=p2>
Please add one by finding any other Personal Retreat Program,<br>
choosing Duplicate, and changing the dates.
EOH
                "registration/error.tt2",
            );
            return;
        }
    }
    else {
        ($pr) = model($c, 'Program')->find($href->{pid});
    }
    if (! $pr) {
        error($c,
            "Unknown Program - cannot proceed",
            "registration/error.tt2",
        );
        return;
    }
    open my $log, '>>', 'online_log';
    print {$log} scalar(localtime), " $fname $href->{first} $href->{last}, ",
                 $pr->name, ", ", $c->user->username(), "\n";
    close $log;

    #
    # find or create a person object.
    #
    my ($person_id, $person, $status) = add_or_update_deduping($c, $href);

    #
    # various fields from the online file make their way
    # into the stash...
    if ($href->{progchoice} eq 'full') {
        stash($c, date_end => $pr->edate_obj() + $pr->extradays);
    }
    for my $how (qw/ ad web brochure flyer word_of_mouth /) {
        stash($c, "$how\_checked" => "");
    }
    # sdate/edate (in the hashref from the online file)
    # are normally empty - except for personal retreats
    # OR for programs with extra days.
    #
    if ($href->{sdate}) {
        stash($c, date_start => date($href->{sdate}));
    }
    if ($href->{edate}) {
        stash($c, date_end => date($href->{edate}));
    }

    # the postmark timestamp
    my $date = date($href->{date});
    $href->{time} =~ s{:}{}xms;      # so it is interpreted as 24 hour time

    #
    # date_start and date_end are always present in the table record.
    # they are the program start/end dates unless overridden.
    # in the stash and on the screen they are blank if they
    # are the same as the program start/end dates.
    #
    # early and late are set accordingly when writing to
    # the database.
    #

    my $fw = $href->{from_where};
    stash($c,
        comment         => $href->{request},
        share_first     => normalize($href->{withwhom_first}),
        share_last      => normalize($href->{withwhom_last}),
        cabin_checked   => $href->{cabin_room} eq 'cabin'? "checked": "",
        room_checked    => $href->{cabin_room} eq 'room' ? "checked": "",
        adsource        => $href->{advertiserName},
        carpool_checked => $href->{carpool}? 'checked': '',
        hascar_checked  => $href->{hascar}? 'checked': '',
        home_checked    => $fw eq 'Home'? 'checked': '',
        sjc_checked     => $fw eq 'SJC'? 'checked': '',
        sfo_checked     => $fw eq 'SFO'? 'checked': '',
        from_where_display => ($href->{hascar} || $href->{carpool})? 'block'
                             :                                       'none',
        date_postmark   => $date->as_d8(),
        time_postmark   => $href->{time},
        green_amount    => $href->{green_amount},
        deposit         => int($href->{amount} - $href->{green_amount}),
        deposit_type    => 'O',
        ceu_license     => $href->{ceu_license},
        "$href->{howHeard}_checked" => "selected",
    );

    my $today = tt_today($c);
    _rest_of_reg($pr, $person, $c, $today, $href->{house1}, $href->{house2});
}

#
# the stash is partially filled in (from an online, manual, or duplicate reg).
# fill in the rest of it by looking at the program and person
# and render the view.  the program must have a GL number or we give an error.
#
sub _rest_of_reg {
    my ($program, $person, $c, $today, $house1, $house2, $cabin_room) = @_;

    if (empty($program->glnum())) {
        error($c,
            $program->name() . " does not have a GL Number.  Please fix.",
            "registration/error.tt2",
        );
        return;
    }
    my $cabin_checked = "";
    my $room_checked = "";
    if ($cabin_room) {
        # passed in when duplicating a reg
        #
        if ($cabin_room eq 'room') {
            stash($c, 'room_checked' => "checked");
        }
        elsif ($cabin_room eq 'cabin') {
            stash($c, 'cabin_checked' => "checked");
        }
    }
    # else leave the stash alone in this regard.
    # it might have been initialized from an online file.

    #
    # is this a dup reg?
    # we have the person and the program.
    # check if it is there already.
    # we CAN register twice for some programs.
    #
    my @reg = model($c, 'Registration')->search({
                  person_id  => $person->id(),
                  program_id => $program->id(),
              });
    if (! $program->allow_dup_regs() && @reg) {
        stash($c,
            template => "registration/dup.tt2",
            person   => $person,
            program  => $program,
            registration => $reg[0],
        );
        return;
    }
    if (@reg) {
        # duplicate registrations are okay but not overlapping ones
        # TODO???
    }

    #
    # the person's affils get _added to_ according
    # to the program affiliations.
    # make a quick string table of the person's affil ids.
    #
    # is this being done too early?
    # should we wait until create_do()?
    #
    my %cur_affils = map { $_->id => 1 }
                     $person->affils;
    my @program_affil_ids = map  { $_->id }
                       grep { $_->descrip() ne 'None' }
                       $program->affils
                       ;
    for my $program_affil_id (@program_affil_ids) {
        if (! exists $cur_affils{$program_affil_id}) {
            model($c, 'AffilPerson')->create({
                a_id => $program_affil_id,
                p_id => $person->id,
            });
        }
    }

    #
    # pop up comment?
    #
    # is there a better way of searching the affil ids???
    #
    my @alerts;
    AFFIL:
    for my $a ($person->affils) {
        if ($a->id() == $system_affil_id_for{'Alert When Registering'}) {
            my $s = $person->comment;
            $s = trim($s);
            if ($s) {
                $s =~ s{\r?\n}{\\n}g;
                $s =~ s{"}{\\"}g;
            }
            push @alerts, $s;
            last AFFIL;
        }
    }
    # if this is for a Personal Retreat
    # are there any PR Alerts for the popup comment?
    #
    if ($program->PR()) {
        # in the stash we have Date::Simple objects
        # for start_date and end_date - put there in
        # sub manual and get_online.
        #
        my $program_sd = $c->stash->{date_start}->as_d8();
        my $program_ed = $c->stash->{date_end}->as_d8();
        push @alerts, get_PR_alerts($c, $program_sd, $program_ed);
    }
    my ($outstand_str, $ob_alert) = outstanding_balance($c, $person);
    if ($ob_alert) {
        stash($c, outstanding => 1);
        push @alerts, $ob_alert;
    }
    if ($program->waiver_needed() && ! $person->waiver_signed()) {
        push @alerts, $c->stash->{fname}? "Waiver Was Signed"
                     :                    "Waiver Needs To Be Signed!";
    }
    if (@alerts) {
        stash($c, alerts => join "\\n\\n", @alerts);
    }

    #
    # life member or current sponsor?  with nights left?
    # they must be in good standing if sponsor
    # and can't take free nights if the housing cost is not a Per Day type.
    # and not if MMI program.
    #
    my $mem = $person->member();
    if (! $program->school->mmi()
        && $mem
        && ($program->PR() 
            || $program->retreat()    # only PR and MMC Retreats for non Life members
            || ($mem->category =~ m{Life}xms && ! $program->rental_id()))
                                 # Life members can take any non-hybrid program
    ) {
        my $status = $mem->category();
        if ($status eq 'Life'
            || $status eq 'Founding Life'
            || ($status eq 'Sponsor' && $mem->date_sponsor_obj >= $today)
                                    # member in good standing
        ) {
            stash($c, status => $status);    # they always get a 30%
                                             # tuition discount.
            my $nights = $mem->sponsor_nights();
            if ($program->housecost->type eq 'Per Day' && $nights > 0) {
                stash($c, nights => $nights);
            }
            if (!$program->PR() && $status =~ m{Life} && ! $mem->free_prog_taken) {
                stash($c, free_prog => 1);
            }
        }
    }

    # any credits?
    if ($person->credits()) {
        CREDIT:
        for my $cr ($person->credits()) {
            if (! $cr->date_used && $cr->date_expires_obj > $today) {
                stash($c, credit => $cr);
                last CREDIT;
            }
        }
    }

    if ($program->footnotes =~ m{[*]}) {
        stash($c, ceu => 1);
    }

    # the housing select list.
    # default is the first housing choice.
    # order is important:
    #
    my $h_type_opts = "";
    my $h_type_opts2 = "";

    Global->init($c);     # get %string ready.
    HTYPE:
    for my $ht (housing_types(2)) {
        next HTYPE if $ht eq "single_bath" && ! $program->sbath;
        next HTYPE if $ht eq "single"      && ! $program->single;
        next HTYPE if $ht eq "economy"     && ! $program->economy;
        next HTYPE if $ht eq "commuting"   && ! $program->commuting;
        if ($ht !~ m{unknown|not_needed|commuting} && $program->housecost->$ht == 0) {
            next HTYPE;
        }
        next HTYPE if $ht eq "center_tent" && wintertime($program->sdate());

        my $selected = ($ht eq $house1 )? " selected": "";
        my $selected2 = ($ht eq $house2)? " selected": "";
        $h_type_opts .= "<option value=$ht$selected>$string{$ht}\n";
        $h_type_opts2 .= "<option value=$ht$selected2>$string{$ht}\n";
    }
    stash($c,
        program       => $program,
        person        => $person,
        h_type_opts   => $h_type_opts,
        h_type_opts1  => $h_type_opts,
        h_type_opts2  => $h_type_opts2,
        confnotes     => [
            model($c, 'ConfNote')->search(undef, { order_by => 'abbr' })
        ],
        outstand      => $outstand_str,
        template      => "registration/create.tt2",
    );
}

sub get_PR_alerts {
    my ($c, $PR_start, $PR_end) = @_;

    my @alerts;
    for my $type (qw/ Program Rental Event /) {
        my @cancelled = $type ne 'Event'? (cancelled => { '!=' => 'yes' })
                       :                  ();
        for my $ev (model($c, $type)->search({
                       @cancelled,
                       pr_alert  => { '!=' => '' },
                       sdate     => { '<=' => $PR_end   },
                       edate     => { '>'  => $PR_start },
                   })
        ) {
            my $name = $ev->name();
            
            # trim off the mm/yy appendage on Programs and Rentals
            $name =~ s{ [ \d/]*\z}{}xms if $type ne 'Event';

            my $alert = $ev->pr_alert();
            # indent the alert a little - including line breaks (<br>)
            $alert =~ s{(<br>)}{\n  }xmsg;
            my $s = "PR Alert from '$name':\n  $alert";
            $s =~ s{\r?\n}{\\n}g;   # for javascript
            $s =~ s{"}{\\"}g;
            push @alerts, $s;
        }
    }
    return @alerts;
}

my @mess;
my %P;
my %dates;
my $taken;
my $tot_prog_days;
my $prog_days;
my $extra_days;

sub _get_data {
    my ($c) = @_;

    %P = %{ $c->request->params() };
    my $prog = model($c, 'Program')->find($P{program_id});

    # BIG TIME messing with dates.
    # I'm reminded of a saying:
    #
    #    "If you have a date in your program
    #     you have a bug in your program."
    #
    # many variations and testings to do here.
    # make a series of test cases to verify.
    #
    %dates = ();
    @mess = ();

    # first make sure that personal retreats have reasonable dates.
    my $PR = $prog->PR();
    if ($PR) {
        if (empty($P{date_start})) {
            push @mess, "Missing Start Date for the Personal Retreat.";
        }
        if (empty($P{date_end})) {
            push @mess, "Missing End Date for the Personal Retreat.";
        }
        if ($P{date_start} =~ m{^\s[+-]}) {
            push @mess, "Start Date for Personal Retreats cannot be relative.";
        }
        return if @mess;
    }
    $extra_days = 0;
    my $sdate = date($prog->sdate);       # personal retreats???
    my $edate = date($prog->edate);       # defaults to today???
    $tot_prog_days = $prog_days = $edate - $sdate;

    my $date_start;
    if ($P{date_start}) {
        # what about personal retreats???   - can't say +2 or -1?
        Date::Simple->relative_date(date($prog->sdate));
        $date_start = date($P{date_start});
        Date::Simple->relative_date();
        if ($date_start) {
            $dates{date_start} = $date_start->as_d8();
            if ($date_start < $sdate) {
                # they came before the program - so extra days
                $extra_days += $sdate - $date_start;
            }
            else {
                # they came after the program started
                # so fewer program days.
                $prog_days -= $date_start - $sdate;     # jeeez
            }
        }
        else {
            push @mess, "Illegal date: $P{date_start}";
        }
    }
    else {
        $dates{date_start} = '';
    }
    my $date_end;
    if ($P{date_end}) {
        # when scheduling a personal retreat
        # the "To Date" is relative to the start date
        # not the end of the program!
        Date::Simple->relative_date($PR? $date_start
                                    :    date($prog->edate));
        $date_end = date($P{date_end});
        Date::Simple->relative_date();
        if ($date_end) {
            # be careful...
            # the end date may be within 
            # the extended part of normal-full program.
            #
            $dates{date_end} = $date_end->as_d8();
            if ($date_end > $edate) {
                my $ndays = $date_end - $edate;
                my $extra = $prog->extradays();
                if ($ndays > $extra) {
                    $prog_days += $extra;
                    $extra_days += $ndays - $extra;
                }
                else {
                    $prog_days += $ndays;
                }
            }
            else {
                # they left before the program finished
                # so fewer prog_days.
                $prog_days -= $edate - $date_end;
            }
        }
        else {
            push @mess, "Illegal date: $P{date_end}";
        }
    }
    else {
        $dates{date_end} = '';
    }
    $P{kids} = trim($P{kids});
# ??? only digits and spaces or commas.   no kids over 12.
#
# have requested payments be optional (checkbox in Finances)
# requested payments have new attribute (MMC or MMI).
# when sending you send one link for all MMI requests
# and another for MMC requests.
# grab_new will understand which is which.
#
    return if @mess;

    if ($PR) {
        #
        # is there an event named "No PR" with some overlap with
        # this registration?
        #
        my $edate1 = (date($dates{date_end})-1)->as_d8();
        my @prog = model($c, 'Event')->search({
            name  => 'No PR',
            sdate => { '<=', $edate1 },
            edate => { '>', $dates{date_start} },
        });
        if (@prog) {
            push @mess, "Sorry, no Personal Retreats at this time.";
        }
        return if @mess;
    }
    $taken = 0;
    if ($P{nights_taken} && ! empty($P{nights_taken})) {
        $taken = trim($P{nights_taken});
        if ($taken !~ m{^\d+$}) {
            push @mess, "Illegal free nights taken: $taken.";
        }
        elsif ($taken > $P{max_nights}) {
            push @mess, "Cannot take more than $P{max_nights} free nights.";
        }
        elsif ($taken && $P{free_prog}) {
            push @mess, "Cannot take a free program AND free nights.";
        }
        elsif ($taken > ($prog_days + $extra_days)) {
            my $plural = ($prog_days + $extra_days == 1)? "": "s";
            push @mess,
                "Only staying " . ($prog_days + $extra_days)
               ." night$plural so can't take $taken of them free!";
        }
    }
    if ($P{hascar} && ! $P{carpool}) {
        $P{carpool} = 'yes';
    }
    if ($P{rental_before} && $P{rental_after}) {
        $P{rental_after} = '';
    }
    if (! $P{cabin_room}) {
        $P{cabin_room} = 'room';
    }
}

#
# reset the globals $tot_prog_days, $prog_days, and $extra_days.
# can't just do this in _get_data() because we may be calling
# _compute() from relodge() without going through _get_data().
# this is only called from _compute().
#
sub _re_get_days {
    my ($reg) = @_;

    my $pr = $reg->program();
    my $sdate = $pr->sdate_obj();
    my $edate = $pr->edate_obj();
    my $date_start = $reg->date_start_obj();    # maybe undef
    my $date_end   = $reg->date_end_obj();      # maybe undef

    if ($pr->PR()) {
        $tot_prog_days = $prog_days = 0;
        $extra_days = $date_end - $date_start;
        $extra_days ||= 1;      # since end may be = start
        return;
    }
    $tot_prog_days = $prog_days = $edate - $sdate;
    $extra_days = 0;
    if ($date_start) {
        if ($date_start < $sdate) {
            # they came before the program - so extra days
            $extra_days += $sdate - $date_start;
        }
        else {
            # they came after the program started
            # so fewer program days.
            $prog_days -= $date_start - $sdate;     # jeeez
        }
    }
    if ($date_end) {
        # be careful...
        # the end date may be within 
        # the extended part of normal-full program.
        #
        if ($date_end > $edate) {
            my $ndays = $date_end - $edate;
            my $extra = $pr->extradays();
            if ($ndays > $extra) {
                $prog_days += $extra;
                $extra_days += $ndays - $extra;
            }
            else {
                $prog_days += $ndays;
            }
        }
        else {
            # they left before the program finished
            # so fewer prog_days.
            $prog_days -= $edate - $date_end;
        }
    }
}

# now we actually create the registration
# if from an online source there will be a filename
# in the %P which needs deleting.
#
sub create_do : Local {
    my ($self, $c) = @_;

    my $today = tt_today($c)->as_d8();
    _get_data($c);
    if (@mess) {
        error($c,
            join("<br>", @mess),
            "registration/error.tt2",
        );
        return;
    }
    my $pr = model($c, 'Program')->find($P{program_id});
    if ($pr->glnum() =~ m{XX}xms) {
        error($c,
            "The GL Number has not yet been assigned.",
            "registration/error.tt2",
        );
        return;
    }
    #
    # we CAN register twice for some programs.
    # is this be a dup reg?
    # we have the person and the program.
    # check if it is there already.
    #
    my @reg;
    if ((! $pr->allow_dup_regs())
        && (@reg = model($c, 'Registration')->search({
                           person_id  => $P{person_id},
                           program_id => $pr->id(),
                  })
           )
    ) {
        my $p = model($c, 'Person')->find($P{person_id});
        stash($c,
            template => "registration/dup.tt2",
            person   => $p,
            program  => $pr,
            registration => $reg[0],
        );
        return;
    }
    %dates = transform_dates($pr, %dates);
    if ($dates{date_start} == $dates{date_end}
        && $P{h_type} ne 'commuting')
    {
        error($c,
            "Housing type must be Commuting when"
                . " start date = end date.",
            "registration/error.tt2",
        );
        return;
    }
    if ($dates{date_start} > $dates{date_end}) {
        error($c,
            "Start date is after the end date.",
            "registration/error.tt2",
        );
        return;
    }
    #
    # if this registration does not overlap with
    # the program itself something is wrong, yes?
    #
    if ($dates{date_end} < $pr->sdate()
        ||
        $pr->edate()     < $dates{date_start}
    ) {
        error($c,
            "The arrival/departure dates you have given\ndo not overlap with the Program at all!",
            "registration/error.tt2",
        );
        return;
    }
    my $newnote = cf_expand($c, $c->request->params->{confnote});
    _check_spelling($c, $newnote);
    my $reg = model($c, 'Registration')->create({
        person_id     => $P{person_id},
        program_id    => $P{program_id},
        deposit       => $P{deposit},
        date_postmark => $P{date_postmark},
        time_postmark => $P{time_postmark},
        ceu_license   => $P{ceu_license},
        referral      => $P{referral},
        adsource      => $P{adsource},
        carpool       => $P{carpool},
        hascar        => $P{hascar},
        from_where    => $P{from_where},
        comment       => $P{comment},
        h_type        => $P{h_type},
        h_name        => $P{h_name},
        kids          => $P{kids},
        confnote      => $newnote,
        status        => $P{status},
        nights_taken  => $taken,
        cancelled     => '',    # to be sure
        arrived       => '',    # ditto
        pref1         => $P{pref1},
        pref2         => $P{pref2},
        share_first   => normalize($P{share_first}),
        share_last    => normalize($P{share_last}),
        manual        => ($P{dup}? 'yes': ''),
        cabin_room    => $P{cabin_room} || '',
        leader_assistant => '',
        free_prog_taken  => $P{free_prog},
        transaction_id => $P{fname} || '',
        rental_before => $P{rental_before},
        rental_after  => $P{rental_after},

        %dates,         # optionally
    });
    # bump the reg_count in the program record
    # 
    if ($pr->PR() || ! $P{dup}) {
        $pr->update({
            reg_count => $pr->reg_count + 1,
        });
    }

    my $reg_id = $reg->id();

    # prepare for history records
    my @who_now = get_now($c);
    push @who_now, reg_id => $reg_id;

    # first, we have some PAST history
    model($c, 'RegHistory')->create({
        reg_id   => $reg_id,
        user_id  => $c->user->obj->id,
        the_date => $P{date_postmark},
        time     => $P{time_postmark},
        what     => ($P{fname}? 'Online Registration'
                    :           'Manual Registration'),
    });

    # now current history
    model($c, 'RegHistory')->create({
        what    => 'Registration Created',
        @who_now,
    });

    # credit, if any
    if ($P{credit_id}) {
        my $cr = model($c, 'Credit')->find($P{credit_id});
        my $amount = $cr->amount();
        my $pr_g = $cr->reg_given->program;
        model($c, 'RegCharge')->create({
            @who_now,
            automatic => '',        # NOT automatic
            amount  => -1*$amount,
            type    => $TYPE_OTHER,
            what    => 'Credit from the '
                       . $pr_g->name . ' program in '
                       . $pr_g->sdate_obj->format("%B %Y"),
        });
        # and mark the credit as taken
        $cr->update({
            date_used   => $today,
            used_reg_id => $reg_id,
        });
    }
    # the payment (deposit)
    if (! $pr->school->mmi() && $P{deposit}) {
        # MMC program deposit
        #
        model($c, 'RegPayment')->create({
            @who_now,
            the_date => $P{date_postmark},      # override 'now'
            time     => $P{time_postmark},
                    # the Deposit (via credit card for online regs
                    # WAS made at the postmark date/time
            amount  => $P{deposit},
            type    => $P{deposit_type},
            what    => 'Deposit',
        });
    }
    else {
        # MMI deposit
        #
        model($c, 'MMIPayment')->create({
            reg_id    => $reg_id,
            deleted   => '',
            the_date  => $today,
            person_id => $P{person_id},
            type      => $P{deposit_type},
            amount    => $P{deposit},
            glnum     => '1' . $pr->glnum(),    # 1 is 'Tuition'
            note      => 'Deposit',
        });
    }

    # add the automatic charges
    _compute($c, $reg, $P{dup}, @who_now);

    # notify those who want to know of each registration as it happens
    if (!$P{dup} && $pr->notify_on_reg()) {
        my $html = "";
        my $tt = Template->new({
            INCLUDE_PATH => "$rst/templates/letter",
            EVAL_PERL    => 0,
        });
        my $stash = {
            reg => $reg,
            per => $reg->person,
        };
        $tt->process(
            "onreg_notify.tt2",   # template
            $stash,               # variables
            \$html,               # output
        ) or die "error in processing template: "
                 . $tt->error();
        email_letter($c,
               to         => $pr->notify_on_reg,
               from       => "$string{from_title} <$string{from}>",
               subject    => "Notification of Registration for " . $pr->title,
               html       => $html, 
        );
        model($c, 'RegHistory')->create({
            @who_now,
            what    => 'On Register Notification Sent',
        });
    }

    # if this registration was from an online file
    # move it aside.  we have finished processing it at this point.
    # manual registrations will come in with fname empty.
    #
    if (exists $P{fname} && $P{fname} ne '') {
        if ($P{fname} eq '0') {
            # from a staging online registration
            unlink "$rst/online/$P{fname}";
        }
        else {
            # first append the reg_id
            open my $out, '>>', "$rst/online/$P{fname}";
            print {$out} "reg_id => $reg_id\n";
            close $out;
            my $dir = "$rst/online_done/"
                    . substr($P{date_postmark}, 0, 4)
                    . '-'
                    . substr($P{date_postmark}, 4, 2)
                    ;
            mkdir $dir unless -d $dir;
            rename "$rst/online/$P{fname}",
                   "$dir/$P{fname}";
            open my $log, '>>', 'online_log';
            my $person = $reg->person;
            print {$log} scalar(localtime), " $P{fname} ",
                         $person->first, " ", $person->last, ", ",
                         $pr->name, ", ",
                         $c->user->username, " moved\n";
            close $log;
        }
    }

    # was there an online donation to the green fund?
    #
    if ($P{green_amount}) {
        # which XAccount id?
        my $key = 'green_glnum';
        if ($pr->school->mmi()) {
            $key .= "_mmi";
        }
        my ($xa) = model($c, 'XAccount')->search({
            glnum => $string{$key},
        });
        if ($xa) {
            model($c, 'XAccountPayment')->create({
                xaccount_id => $xa->id(),
                person_id   => $P{person_id},
                amount      => $P{green_amount},
                type        => 'O',     # online credit
                what        => '',
                @who_now[0..5],     # not reg_id => $reg_id

                the_date => $P{date_postmark},      # override 'now'
                time     => $P{time_postmark},
                        # the Deposit (via credit card for online regs
                        # WAS made at the postmark date/time
                        # and the green scene amount was part of that.
            });
            #
            # send email thank you
            #
            my $per = $reg->person();
            my $stash = {
                amount     => $P{green_amount},
                first      => $per->first(),
                last       => $per->last(),
                green_name => $string{green_name},
            };
            my $html = "";
            my $tt = Template->new({
                INCLUDE_PATH => "$rst/templates/letter",
                EVAL_PERL    => 0,
            });
            $tt->process(
                "green.tt2",      # template
                $stash,           # variables
                \$html,           # output
            ) or die "error in processing template: "
                     . $tt->error();
            email_letter($c,
                to      => $reg->person->name_email(),
                from    => "$string{green_name} <$string{green_from}>",
                subject => $string{green_subj},
                html    => $html,
            );
        }
        else {
            error($c,
                  "Sorry, cannot find Green Scene extra account!",
                  'gen_error.tt2');
            return;
        }
    }
    # if the program needs a waiver signed
    if ($pr->waiver_needed() && ! $reg->person->waiver_signed()) {
        $reg->person->update({
            waiver_signed => 'yes',
        });
        model($c, 'RegHistory')->create({
            what    => 'Liability Waiver Signed',
            @who_now,
        });
    }
    
    # go on to lodging, if needed
    $c->response->redirect($c->uri_for("/registration/"
        . (($reg->h_type =~ m{own_van|commuting|unknown|not_needed})? "view"
           :                                                          "lodge")
        . "/$reg_id")
    );
}

#
# automatic charges - computed from the contents
# of the registration record.
# ??? we need to compute prog_days and extra_days and tot_prog_days
# WITHIN this routine.  this is the only place they are used.
#
# worst case:
# someone is a sponsor member who wants to take x # of free nights
# they register for a program with extra days and
# they come early and leave after the short program ends
# but before the extended program ends.  wow.
# AND the housing costs for the Personal Retreat and the program
# are different.
#
sub _compute {
    my ($c, $reg, $dup, @who_now) = @_;

    Global->init($c);
    my $reg_id = $reg->id();
    my $auto = ! $reg->manual();
    my $pr  = $reg->program();
    my $mem = $reg->person->member();
    my $lead_assist = $reg->leader_assistant();   # no housing or tuition charge
                                                  # for these people
    # clear auto charges - they'll be re-added below
    model($c, 'RegCharge')->search({
        reg_id    => $reg_id,
        automatic => 'yes',
    })->delete();

    # clear member activity for this registration
    if ($mem) {
        model($c, 'NightHist')->search({
            member_id => $mem->id,
            reg_id    => $reg_id,
        })->delete();
    }

    _re_get_days($reg);

    # tuition
    #
    if (! $lead_assist && $auto) {
        my $tuition = $pr->tuition();
        my $what = "Tuition";
        if ($pr->extradays() && $reg->date_end() > $pr->edate()) {
            # they need to pay the full tuition amount
            $tuition = $pr->full_tuition();
        }
        if ($pr->retreat() && $prog_days != $tot_prog_days) {
            # pro-rated tuition for retreats only
            #
            $tuition = int($tuition * ($prog_days/$tot_prog_days));
            my $pl = ($prog_days == 1)? "": "s";
            $what .= " - pro-rated for $prog_days day$pl";
        }
        if ($tuition > 0) {
            model($c, 'RegCharge')->create({
                @who_now,
                automatic => 'yes',
                amount    => $tuition,
                type      => $TYPE_TUITION,
                what      => $what,
            });
        }

        # sponsor/life members get a discount on tuition
        # up to a max.  and only for MMC events, not MMI.
        #
        if (! $pr->school->mmi() && $reg->status() && $tuition > 0) {
            # Life members can take a free program ... so:
            if ($reg->free_prog_taken) {
                model($c, 'RegCharge')->create({
                    @who_now,
                    automatic => 'yes',
                    amount    => -1*$tuition,
                    type      => $TYPE_TUITION,
                    what      => $reg->status
                                 . " member - free program - tuition waived.",
                });
            }

=comment

            # no more - as of 6/11/10
            else {
                my $amount = int(($string{spons_tuit_disc}/100)*$tuition);
                my $maxed = "";
                if ($amount > $string{max_tuit_disc}) {
                    $amount = $string{max_tuit_disc};
                    $maxed = " - to a max of \$$string{max_tuit_disc}";
                }
                model($c, 'RegCharge')->create({
                    @who_now,
                    automatic => 'yes',
                    amount    => -1*$amount,
                    type      => $TYPE_TUITION,
                    what      => "$string{spons_tuit_disc}% Tuition discount for "
                                . $reg->status . " member$maxed",
                });
            }

=cut

        }
    }

    # assuming we have decided on their housing at this point...
    # we do have an h_type but perhaps not a housing_id.
    #
    # figure housing cost
    my $housecost = $pr->housecost;

    my $h_type = $reg->h_type;           # what housing type was assigned?
    my $h_cost = ($h_type eq 'not_needed'
                  || $h_type eq 'unknown')? 0
                 :                          $housecost->$h_type();
                                            # column name is correct, yes?
    my ($tot_h_cost, $what);
    if ($housecost->type() eq "Per Day") {
        $tot_h_cost = $prog_days*$h_cost;
        my $plural = ($prog_days == 1)? "": "s";
        $what = "$prog_days day$plural Lodging at \$$h_cost per day";
    }
    else {
        # changed from pro-rating to not pro-rating
        #
        $tot_h_cost = $h_cost;
        $what = "Lodging - Total Cost";
    }
    if ($lead_assist && $pr->rental_id() == 0) {
        # leaders of non-hybrid programs pay no housing
        #
        $tot_h_cost = 0;
    }
    if ($auto && $tot_h_cost != 0) {
        model($c, 'RegCharge')->create({
            @who_now,
            automatic => 'yes',
            type      => $TYPE_MEALS_AND_LODGING,
            amount    => $tot_h_cost,
            what      => $what,
        });
    }

    # extra days - at the current personal retreat housecost rate.
    # but not for leaders/assistants???  right?  wrong - for now.
    # show leader/asst on reg screen???   show footnotes differently?
    #
    my $extra_h_cost = 0;
    #if ($auto && $extra_days && ! $lead_assist) {
    if ($auto && $extra_days) {
        #
        # look for the personal retreat program
        # that contains the start date of the registration.
        # that is the program whose housing cost we will use.
        #
        # don't worry about other exceptions - like the registration
        # straddles two personal retreat programs with differing
        # housing costs!  that would be too much to worry about.
        #
        my $date_start = $reg->date_start();
        my ($pers_ret) = model($c, 'Program')->search({
            name  => { 'like' => '%personal%retreat%' },
            sdate => { '<=' => $date_start },
            edate => { '>=' => $date_start },
        });
        if (! $pers_ret) {
            # what to do???
            # make it free!
            # error reporting and recovery is too tricky.
            #
            $extra_h_cost = 0;
        }
        else {
            my $housecost = $pers_ret->housecost();
            $extra_h_cost = ($h_type eq 'not_needed'
                             || $h_type eq 'unknown')? 0
                            :                          $housecost->$h_type;
                                            # column name above is correct, yes?
            $tot_h_cost += $extra_days*$extra_h_cost;
        }
        my $plural = ($extra_days == 1)? "": "s";
        model($c, 'RegCharge')->create({
            @who_now,
            automatic => 'yes',
            type      => $TYPE_MEALS_AND_LODGING,
            amount    => $extra_days*$extra_h_cost,
            what      => "$extra_days day$plural Lodging"
                        ." at \$$extra_h_cost per day",
        });
    }

    my $life_free = 0;
    if ($auto && $reg->free_prog_taken() && $tot_h_cost) {
        model($c, 'RegCharge')->create({
            @who_now,
            automatic => 'yes',
            amount    => -$tot_h_cost,
            type      => $TYPE_MEALS_AND_LODGING,
            what      => $reg->status
                         . " member - free program - lodging waived",
        });
        $life_free = 1;
        #
        # finally, update the member record and add a NightHist record
        #
        $mem->update({
            free_prog_taken => 'yes',
        });
        model($c, 'NightHist')->create({
            member_id  => $mem->id(),
            num_nights => 0,
            action     => 4,        # take free program
            @who_now,               # includes reg_id
        });
    }
    #
    # discounts - MMC and MMI
    #
    if ($auto
        && ! $pr->school->mmi()    # allow for MMI, too - per Kamala
        && ! $life_free
        && ! $lead_assist
        && $housecost->type eq "Per Day"
    ) {
        if ($prog_days + $extra_days >= $string{disc1days}) {
            model($c, 'RegCharge')->create({
                @who_now,
                automatic => 'yes',
                type      => $TYPE_MEALS_AND_LODGING,
                amount    => -1*(int(($string{disc1pct}/100)*$tot_h_cost + .5)),
                what      => "$string{disc1pct}% Lodging discount for"
                            ." programs >= $string{disc1days} days",
            });
        }
        # not any more - 30 day PRs must go through personnel
        #if ($prog_days + $extra_days >= $string{disc2days}) {
        #    model($c, 'RegCharge')->create({
        #        @who_now,
        #        automatic => 'yes',
        #        amount    => -1*(int(($string{disc2pct}/100)*$tot_h_cost+.5)),
        #        type      => $TYPE_MEALS_AND_LODGING,
        #        what      => "$string{disc2pct}% Lodging discount for"
        #                    ." programs >= $string{disc2days} days",
        #    });
        #}
    }
    #
    # Personal Retreat discounts during special period
    #
    if ($auto
        && $pr->PR()
        && $reg->date_start() <= $string{disc_pr_end}
        && $reg->date_end()   >= $string{disc_pr_start}
    ) {
        # there is SOME overlap.
        # so we need to figure
        # how many days in the registration's range
        # are Mon-Thu and in the discount period.
        #
        my $d          = date($reg->date_start());
        my $end        = date($reg->date_end());
        my $disc_start = date($string{disc_pr_start});
        my $disc_end   = date($string{disc_pr_end});
        my $ndays = 0;
        while ($d < $end) {     # not <= because they leave on $end
            my $dow = $d->day_of_week();
            if (   1 <= $dow         && $dow <= 4        # Mon-Thu
                && $disc_start <= $d && $d <= $disc_end  # in discount PR period
            ) {
                ++$ndays;
            }
            ++$d;
        }
        if ($ndays) {
            my $pl = $ndays == 1? ""
                     :            "s";
            model($c, 'RegCharge')->create({
                @who_now,
                automatic => 'yes',
                amount    => -1*(int(($string{disc_pr}/100)*$ndays*$h_cost+.5)),
                type      => $TYPE_MEALS_AND_LODGING,
                what      => "$string{disc_pr}% Lodging discount for"
                             . " $ndays day$pl Mon-Thu<br>"
                             . " in the PR discount period.",
            });
        }
    }

    #
    # sponsor/life members get free nights
    #
    # do people take free nights only when they can get a single?
    # Hanuman Fellowship membership benefit brochure
    # says something about not including meals...???
    #
    # if taken when the program is > 7 days the
    # sponsor member could actually get a credit.
    # not right somehow???
    #
    # what if the sponsor member comes early, stays after
    # and the housing cost per day for the program is not the same
    # as the default per day cost?   Which daily cost should be used
    # for the free nights?  First the most expensive, then
    # the least for the balance.  Are we being anally precise
    # or what??
    #
    if ($auto && (my $ntaken = $reg->nights_taken())) {

        my @boxes = (
            [ $prog_days,  $h_cost     ],
            [ $extra_days, $extra_h_cost ],
        );
        @boxes = sort { $b->[1] <=> $a->[1] } @boxes;
            # sorted most expensive nights(days) first

        my $left_to_take = $ntaken;
        BOX:
        for my $b (@boxes) {
            my ($n, $perday) = @$b;
            $n = $left_to_take if $left_to_take < $n;
            my $plural = ($n == 1)? "": "s";
            model($c, 'RegCharge')->create({
                @who_now,
                automatic => 'yes',
                amount    => -1*($n * $perday),
                type      => $TYPE_MEALS_AND_LODGING,
                what      => "$n free night$plural Lodging at"
                            ." \$$perday per day for "
                            . $reg->status . " member",
            });
            $left_to_take -= $n;
            last BOX unless $left_to_take;
        }
        #
        # members getting free nights still pay for meal costs
        #

=comment

# As of 6/11/10 they pay for meals with their meal ticket instead.
#
        my $meal_cost = $string{member_meal_cost};
        my $plural = ($ntaken == 1)? "": "s";
        model($c, 'RegCharge')->create({
            @who_now,
            automatic => 'yes',
            amount    => ($ntaken * $meal_cost),
            type      => $TYPE_MEALS_AND_LODGING,
            what      => "$ntaken day$plural of meals"
                       . " at \$$meal_cost per day for "
                       . $reg->status() . " member",
        });

=cut

        # and add a NightHist record to specify what happened
        #
        model($c, 'NightHist')->create({
            @who_now,       # includes reg_id
            member_id  => $mem->id,
            num_nights => $ntaken,
            action     => 2,    # take nights
        });
    }

    #
    # MMI lodging discount - if requested
    #
    my $requested = 0;
    AFFIL:
    for my $af ($reg->person->affils()) {
        if ($af->descrip() =~ m{mmi.*discount}i) {
            $requested = 1;
            last AFFIL;
        }
    }
    if ($auto && $requested) {
        model($c, 'RegCharge')->create({
            @who_now,
            automatic => 'yes',
            amount    => -1*(int(($string{mmi_discount}/100)*$tot_h_cost + .5)),
            type      => $TYPE_MEALS_AND_LODGING,
            what      => "$string{mmi_discount}% MMI lodging discount",
        });
    }
   
    #
    # is there a minimum of $15 per day for lodging???
    # figure the kids cost from the initial UNdiscounted rate.
    # bringing your kids during your free program - they still pay.
    #
    if ($auto && (my $kids = $reg->kids)) {
        my $min_age = $string{min_kid_age};
        my $max_age = $string{max_kid_age};
        my @ages = $kids =~ m{(\d+)}g;
        @ages = grep { $min_age <= $_ && $_ <= $max_age } @ages;
        my $nkids = @ages;
        my $plural = ($nkids == 1)? "": "s";
        if ($nkids && $tot_h_cost) {
            model($c, 'RegCharge')->create({
                @who_now,
                automatic => 'yes',
                amount    => int($nkids*(($string{kid_disc}/100)*$tot_h_cost)),
                type      => $TYPE_MEALS_AND_LODGING,
                what      => "$nkids kid$plural aged $min_age-$max_age"
                            ." - $string{kid_disc}% for lodging",
            });
        }
    }
    if ($auto && $reg->ceu_license) {
        model($c, 'RegCharge')->create({
            @who_now,
            automatic => 'yes',
            amount    => $string{ceu_lic_fee},
            type      => $TYPE_CEU_LICENSE_FEE,
            what      => "CEU License fee",
        });
    }

    $reg->calc_balance();

    if (! $mem) {
        return;
    }
    reset_mem($c, $mem);
    # phew!
}

#
# make sure the member information is correct
# given the possible activity that affected it.
#
sub reset_mem {
    my ($c, $mem) = @_;

    my $mem_id = $mem->id();

    # find number last set for the free nights
    #
    my @recs = model($c, 'NightHist')->search(
        {
            member_id => $mem_id,
            action    => 1,         # set nights
        },
        {
            order_by => 'the_date desc, time desc',
        }
    );
    my $nnights = 0;
    my $set_date = "";
    my $set_time = "";
    if (@recs) {
        $nnights = $recs[0]->num_nights();
        $set_date = $recs[0]->the_date();
        $set_time = $recs[0]->time();
    }
    my $ntaken = 0;
    if ($nnights != 0) {
        # find takings of nights since the setting
        # add em up.
        #
        @recs = model($c, 'NightHist')->search(
            {
                member_id => $mem_id,
                action    => 2,     # take nights
                -or => [
                    the_date  => { '>', $set_date },
                    -and => [
                        the_date => $set_date,
                        time     => { '>' => $set_time },
                    ],
                ],
            },
        );
        for my $r (@recs) {
            $ntaken += $r->num_nights();
        }

    }
    # how about the free program?
    # has a free program been taken since it was
    # last cleared?
    @recs = model($c, 'NightHist')->search(
        {
            member_id => $mem_id,
            action    => 3,
        },
        {
            order_by => 'the_date desc, time desc',
        }
    );
    my $taken = '';
    if (@recs) {
        my $clear_date = $recs[0]->the_date();
        my $clear_time = $recs[0]->time();
        my @hist = model($c, 'NightHist')->search({
            member_id => $mem_id,
            action    => 4,     # take free program
            -or => [
                the_date  => { '>' => $clear_date },
                -and => [
                    the_date => $clear_date,
                    time     => { '>=' => $clear_time },
                ],
            ]
        });
        if (@hist) {
            $taken = 'yes';
        }
    }
    $mem->update({
        sponsor_nights  => $nnights - $ntaken,
        free_prog_taken => $taken,
    });

}

#
# send a confirmation letter.
# fill in a template and send it off.
# use the template toolkit outside of the Catalyst mechanism.
# if there is a non-blank confnote
# create a ConfHistory record for this sending.
#
# several other things happen, too!
#
sub send_conf : Local {
    my ($self, $c, $reg_id, $preview) = @_;

    my $reg = model($c, 'Registration')->find($reg_id);
    my $today = tt_today($c);
    my $pr = $reg->program;
    my $fname = "$rst/templates/letter/" . $pr->cl_template() . ".tt2";
    if (! -r $fname) {
        error($c,
              "Sorry, cannot open confirmation letter template.",
              'gen_error.tt2');
        return;
    }
    if (empty($pr->summary->gate_code())) {
        error($c,
              "Sorry, cannot send confirmation letter because<br>"
              . $pr->name() . " needs a gate code!",
              'gen_error.tt2');
        return;
    }
    Global->init($c);
    my $htdesc = $string{$reg->h_type};
    $htdesc =~ s{\s*\(.*\)}{};           # don't need this
    $htdesc =~ s{Mount Madonna }{};      # ... Center Tent
    my $PR = $pr->PR();
    my $start = ($reg->date_start)? $reg->date_start_obj: $pr->sdate_obj;
    my $carpoolers = undef;
    if ($reg->carpool() && ! $PR) {
        $carpoolers = [ model($c, 'Registration')->search(
            {
                program_id => $pr->id,
                carpool    => 'yes',
                cancelled  => { '!=' => 'yes' },
            },
            {
                join     => [qw/ person /],
                prefetch => [qw/ person /],
                order_by => [qw/ person.zip_post /],
            }
        ) ];
    }
    my $prog_end = date($pr->edate());
    my $xdays = $pr->extradays();
    if ($xdays && $reg->date_end() >= $pr->edate() + $xdays) {
        $prog_end += $xdays;
    }
    # if we're not previewing
    # and there's a tag in the conf letter named 'pre_payment_link'
    # first clear any existing requested payment records and
    # then create a single pre-payment record for the total balance.
    #
    my $amount = $reg->balance();
    my $conf_template = slurp($fname);
    my $pre_pay_link = '#';     # so that the preview will have
                                # the pre-payment section
    my $need_pre_pay_link = $conf_template =~ m{pre_payment_link}xms;
    if (! $preview && $need_pre_pay_link && $amount > 0) {
        for my $rp ($reg->req_payments()) {
            $rp->delete();
        }
        my $org = $reg->program->school->mmi()? 'MMI': 'MMC';
        my $req_payment = model($c, 'RequestedPayment')->create({
            person_id => $reg->person_id(),
            org       => $org,
            amount    => $amount,
            for_what  => 2,     # meals & lodging
            the_date  => $today,
            reg_id    => $reg_id,
            note      => 'Payment of balance',
        });
        # Reg History record
        my @who_now = get_now($c);
        model($c, 'RegHistory')->create({
            reg_id   => $reg_id,
            what     => "Created pre-payment request for \$$amount.",
            @who_now,
        });

        # by 'send_requests' here we mean that the file
        # is sent to mountmadonna.org so it's ready for
        # the person when they click on the link in their
        # confirmation letter that we will soon send them.
        #
        my $code = RetreatCenter::Controller::Person->_send_requests(
            $c,
            $reg_id,
            0,      # don't "resend all". this is the only request.
            $org,
            1,      # no sending of email - we will include
                    # the prepayment link in the confirmation letter.
        );
        $pre_pay_link = $string{ $org eq 'MMI'? 'prepay_mmi_link'
                                :               'prepay_link'
                               }
                      . "?code=$code"
                      ;
    }
    my $cancel_policy = '';
    my $cp = $pr->canpol();
    if (lc $cp->name ne 'default') {
        $cancel_policy = $cp->policy();
    }
    my $stash = {
        user     => $c->user,
        person   => $reg->person,
        reg      => $reg,
        program  => $pr,
        prog_end => $prog_end,
        personal_retreat => $PR,
        sunday   => $PR
                    && ($reg->date_start_obj->day_of_week() == 0),
        friday   => $start->day_of_week() == 5,
        today    => $today,
        deposit  => $reg->deposit,
        htdesc   => $htdesc,
        article  => ($htdesc =~ m{^[aeiou]}i)? 'an': 'a',
        carpoolers => $carpoolers,
        penny    => \&penny,
        registrar_email => $string{registrar_email},
        pre_payment_link => $pre_pay_link,
        cancel_policy => $cancel_policy,
    };
    my $html = "";
    my $tt = Template->new({
        INTERPOLATE  => 1,
        EVAL_PERL    => 0,
    });
    $tt->process(
        \$conf_template,   # text reference
        $stash,            # variables
        \$html,            # output
    ) or die "error in processing template: "
             . $tt->error();
    #
    # assume the letter will be successfully
    # printed or sent - if you are not previewing, that is.
    #
    if (! $preview) {
        _reg_hist($c, $reg_id, "Confirmation Letter sent");
        $reg->update({
            letter_sent => 'yes',   # this duplicates the RegHistory record
                                    # above but is much easier accessed.
        });
    }
    #
    # if no email put letter to screen for printing and snail mailing.
    # ??? needs some help here...  what to do after printing?
    # just go back.  or have a bookmark to go somewhere???
    # can we print it automatically?  don't know. better to not to.
    #
    if (! $reg->person->email() || $preview) {
        $c->res->output($html);
        return;
    }

    my $user = $c->user->obj();
    my ($title, $from);
    if (! $pr->school->mmi()) {
        $title = $string{from_title};
        $from  = $string{from};
    }
    else {
        $title = "MOUNT MADONNA INSTITUTE Program Office";
        $from  = 'MMIreservations@mountmadonnainstitute.org';
    }
    my $pr_title = $pr->title();
    $pr_title =~ s{\A .* (Special \s+ Guest) .*}{$1}xms;
    $pr_title =~ s{\A .* (Personal \s+ Retreat) .*}{$1}xms;
    if (!email_letter($c,
           to      => $reg->person->name_email(),
           from    => $title . " <" . $user->email() . ">",
           replyto => "$title <$from>",
           subject => "Confirmation of Registration for "
                      . $reg->person->name
                      . " in "
                      . $pr_title,
           html    => $html, 
    )) {
        error($c,
              'Email did not send! :(',
              'gen_error.tt2');
        return;
    }
    my @who_now = get_now($c, $reg_id);
    push @who_now, reg_id => $reg_id;
    if ($reg->confnote) {
        model($c, 'ConfHistory')->create({
            note => $reg->confnote,
            @who_now,
        });
    }
    $c->response->redirect($c->uri_for("/registration/view/$reg_id"));
}

sub view : Local {
    my ($self, $c, $reg_id, $alert, $who) = @_;

    my $reg = model($c, 'Registration')->find($reg_id);
    stash($c, reg => $reg);
    _view($c, $reg, $alert, $who);
}

sub view_trans_id : Local {
    my ($self, $c, $trans_id) = @_;

    my ($reg) = model($c, 'Registration')->search({
        transaction_id => $trans_id,
    });
    stash($c, reg => $reg);
    _view($c, $reg);
}

sub _view {
    my ($c, $reg, $alert, $who) = @_;
    my $reg_id = $reg->id();
    my (@same_name_reg) = model($c, 'Registration')->search({
                              person_id  => $reg->person_id(),
                              program_id => $reg->program_id(),
                          });
    my $prog = $reg->program();
    my $extra = $prog->extradays();
    if ($extra) {
        my $edate2 = $prog->edate_obj + $extra;
        stash($c, plus => "<b>Plus</b> $extra day"
                          . ($extra > 1? "s": "")
                          . " <b>To</b> " . $edate2
                          . " <span class=dow>"
                          . $edate2->format("%a")
                          . "</span>"
        );
    }
    if ($prog->footnotes =~ m{[*]}) {
        stash($c, ceu => 1);
    }
    # to Long Term?
    my $lt_reg_id = 0;
    if (! $prog->level->long_term()) {
        my $lt = long_term_registration($c, $reg->person->id());
        if (ref($lt)) {
            $lt_reg_id = $lt->id();
        }
        # else if $lt > 1 !!!! ???? give error
        # prohibit it from happening in the first place!
        # my $person = model($c, 'Person')->find($person_id);
        # my $name = $person->name();
        # $c->stash->{mess}
        #   = (@lt)? "$name is enrolled in <i>more than one</i> long term program!"
        #    :       "$name is not enrolled in <i>any</i> long term program!";
    }
    my @files = <$rst/online/*>;
    my $share_first = $reg->share_first();
    my $share_last  = $reg->share_last();
    my $share = $share_first? "$share_first $share_last": '';
    if ($share_first) {
        # there may be more than one person who matches :(
        #
        my (@people) = model($c, 'Person')->search({
                               first => $share_first,
                               last  => $share_last,
                       });
        my $next_reg;
        PEOPLE:
        for my $person (@people) {
            if (($next_reg) = model($c, 'Registration')->search({
                                  person_id  => $person->id(),
                                  program_id => $reg->program_id(),
                              })
            ) {
                my $next_id = $next_reg->id();
                $share = "<a href=/registration/view/$next_id>$share</a>";
                last PEOPLE;
            }
        }
        if (! @people) {
            $share .= " - <span class=red>could not find</span>";
        }
        elsif (! $next_reg) {
            # not registered - but are they in the online list?
            my ($found_first, $found_last) = (0, 0);
            for my $f (<$rst/online/*>) {
                open my $in, "<", $f
                    or die "cannot open $f: $!\n";
                # x_fname, x_lname - could be anywhere in the file
                while (<$in>) {
                    if (m{x_fname => $share_first}i) {
                        $found_first = 1;
                    }
                    elsif (m{x_lname => $share_last}i) {
                        $found_last = 1;
                    }
                }
                close $in;
                if ($found_first && $found_last) {
                    last;
                }
            }
            if ($found_first && $found_last) {
                $share .= " - <span class=red><b>is</b> in the online list</span>";
            }
            else {
                $share .= " - <span class=red>not registered</span>";
            }
        }
    }
    my $PR = $prog->PR();
    my ($sdate, $nmonths);
    if ($PR) {
        $sdate = $reg->date_start();
        $nmonths = date($reg->date_end())->month()
                   - date($sdate)->month()
                   + 1;
    }
    else {
        $sdate = $prog->sdate();
        $nmonths = months_calc(date($sdate), date($prog->edate()));
    }
    #
    # is this person a leader or assistant of this program?
    #
    my $pers_label = "Person";
    if ($reg->leader_assistant()) {
        $pers_label = $reg->person->leader->assistant()? "Assistant"
                      :                                  "Leader"
                      ;
        $pers_label = "<span class=lead_asst>$pers_label</span>";
    }
    my $person = $reg->person();
    my $name = $person->last() . ", " . $person->first();
    #
    # are there any unsent payment requests?
    #
    my $send_requests = 0;
    my @req_payments = $reg->req_payments();
    my %group_totals;
    REQS:
    for my $req (@req_payments) {
        if (! $req->code()) {
            $send_requests = 1;
        }
        else {
            $group_totals{$req->code()} += $req->amount();
        }
    }
    for my $req (@req_payments) {
        if ($req->code()) {
            $req->{group_total} = commify($group_totals{$req->code()});
        }
    }
    my $misspellings = "";
    if (-f "/tmp/spellout") {
        open my $in, '<', '/tmp/spellout';
        my @words = <$in>;
        chomp @words;
        unlink '/tmp/spellout';
        $misspellings = "\\n\\n" . (join "\\n", @words) if @words;
    }
    stash($c,
        time_travel_class($c),
        req_payments   => \@req_payments,
        send_requests  => $send_requests,
        pers_label     => $pers_label,
        pg_title       => $name,
        online         => scalar(@files),
        share          => $share,
        non_pr         => ! $PR,
        daily_pic_date => ($prog->category->name() eq "Normal"? "indoors"
                           :                                    "resident")
                           . "/" . $reg->date_start,
        cluster_date   => $sdate,
        cur_cluster    => ($reg->house_id && $reg->house)? $reg->house->cluster_id: 1,
        cal_param      => "$sdate/$nmonths",
        lt_reg_id      => $lt_reg_id,
        program        => $prog,
        only_one       => (@same_name_reg == 1),
        send_preview   => ($PR || $same_name_reg[0]->id() == $reg->id()),
        alert          => $alert,
        who            => $who,
        misspellings   => $misspellings,
        template       => "registration/view.tt2",
    );
}

sub pay_balance : Local {
    my ($self, $c, $id, $from) = @_;

    if (tt_today($c)->as_d8() eq $string{last_deposit_date}) {
        error($c,
              'Since a deposit was just done'
                  . ' please make this payment tomorrow instead.',
              'gen_error.tt2');
        return;
    }
    my $reg = model($c, 'Registration')->find($id);
    if (empty($reg->program->glnum())) {
        error($c,
              $reg->program->name() . " does not have a GL Number.  Please fix.",
              'gen_error.tt2');
        return;
    }
    stash($c,
        message  => payment_warning('mmc'),
        balance  => penny($reg->balance()),
        from     => $from,
        reg      => $reg,
        template => "registration/pay_balance.tt2",
    );
}

sub pay_balance_do : Local {
    my ($self, $c, $reg_id) = @_;

    my $reg = model($c, 'Registration')->find($reg_id);
    my $arriving = !$reg->arrived()
                   && $reg->date_start <= tt_today($c)->as_d8();
    my $amount = trim($c->request->params->{amount});
    my $type   = $c->request->params->{type};
    if (invalid_amount($amount)) {
        error($c,
            "Illegal amount: $amount",
            "registration/error.tt2",
        );
        return;
    }
    my $balance = $reg->balance;
    if ($amount > $balance) {
        error($c,
            "Payment is more than the balance of $balance.",
            "registration/error.tt2",
        );
        return;
    }
    my @who_now = get_now($c);
    push @who_now, reg_id => $reg_id;
    if (tt_today($c)->as_d8() eq $string{last_deposit_date}) {
        push @who_now, the_date => (tt_today($c)+1)->as_d8(),
    }
    model($c, 'RegPayment')->create({
        @who_now,
        amount => $amount,
        type   => $type,
        what   => "Payment",
    });
    $balance -= $amount;
    $reg->update({
        balance => $balance,
        ($arriving? (arrived => 'yes'): ()),
    });
    my $arr = $arriving? "Arrival and ": "";
    my $bal = $balance == 0? " Balance": "";
    _reg_hist($c, $reg_id,
              $arr
              . $string{'payment_' . $type}
              . " payment of \$$amount"
              . $bal
              . "."
             );
    my $from = $c->request->params->{from};
    if ($from eq "list_reg_name") {
        $c->response->redirect(
            $c->uri_for("/registration/list_reg_name/". $reg->program->id())
        );
    }
    elsif ($from eq "edit_dollar") {
        $c->response->redirect(
            $c->uri_for("/registration/edit_dollar/$reg_id")
        );
    }
    else {
        # $from eq 'view'
        # view registration again
        $c->response->redirect(
            $c->uri_for("/registration/view/$reg_id")
        );
    }
}

sub cancel : Local {
    my ($self, $c, $id) = @_;

    my $reg = model($c, 'Registration')->find($id);

    if ($reg->program->school->mmi()) {
        # when MMI students cancel, there is no credit, no letter
        #
        cancel_do($self, $c, $id, 1);       # 1 => mmi
        return;
    }
    my $today = tt_today($c);
    my $person = $reg->person();
    my $name = $person->last() . ", " . $person->first();
    Global->init($c);
    stash($c,
        pg_title       => "Cancel $name",
        today          => $today,
        ndays          => $reg->program->sdate_obj - $today,
        reg            => $reg,
        credit_amount  => $string{credit_amount},
        template       => "registration/credit_confirm.tt2",
    );
}

sub cancel_do : Local {
    my ($self, $c, $id, $mmi) = @_;

    my $reg         = model($c, 'Registration')->find($id);
    my $send_letter = $c->request->params->{send_letter};
    my $credit_amount = $c->request->params->{credit_amount};
    my $refund_amount = $c->request->params->{refund_amount};
    my $via_authorize = $c->request->params->{via_authorize};

    if (!$mmi) {
        if (defined $credit_amount && invalid_amount($credit_amount)) {
            error($c,
                "Illegal credit amount: $credit_amount",
                'gen_error.tt2',
            );
            return;
        }
        if (defined $refund_amount && invalid_amount($refund_amount)) {
            error($c,
                "Illegal refund amount: $refund_amount",
                'gen_error.tt2',
            );
            return;
        }
        if ($credit_amount && $refund_amount) {
            $credit_amount = 0;
        }
    }
    my $date_expire;
    if ($reg->cancelled() ne 'yes') {
        $reg->update({
            cancelled => 'yes',
        });
        # decrement the reg_count in the program record
        #
        my $prog_id   = $reg->program_id;
        my $pr = model($c, 'Program')->find($prog_id);
        $pr->update({
            reg_count => \'reg_count - 1',
        });
        # give credit
        #
        if (! $mmi && $credit_amount) {
            my $sdate = $reg->program->sdate_obj();
            $date_expire = date(
                $sdate->year() + 1,
                $sdate->month(),
                $sdate->day(),
            );
            model($c, 'Credit')->create({
                reg_id       => $id,
                person_id    => $reg->person->id(),
                amount       => $credit_amount,
                date_given   => tt_today($c)->as_d8(),
                date_expires => $date_expire->as_d8(),
                date_used    => "",
                used_reg_id  => 0,
                # How about who did this??? and what time?
            });
        }

        # add reg history record
        #
        _reg_hist($c, $id,
            "Cancelled"
            . (           $mmi? ""
              :($credit_amount? " - Credit of \$$credit_amount given."
              :($refund_amount? " - Refund of \$$refund_amount given"
                    . ($via_authorize? ' via authorize.net '
                                       . $reg->transaction_id()
                                       . '.'
                      :                '.')
              :                 " - No credit given.")))
        );
    }


    # return any assigned housing to the pool
    #
    _vacate($c, $reg) if $reg->house_id();

    # clear any member activity for this registration
    #
    if ($reg->free_prog_taken() || $reg->nights_taken()) {
        my $mem = $reg->person->member();
        if ($mem) {
            model($c, 'NightHist')->search({
                member_id => $mem->id(),
                reg_id    => $id,
            })->delete();
            reset_mem($c, $mem);
        }
    }

    if (! $mmi && $send_letter) {
        #
        # send the cancellation confirmation letter for MMC programs
        #
        my $html = "";
        my $tt = Template->new({
            INTERPOLATE  => 1,
            INCLUDE_PATH => "$rst/templates/letter",
            EVAL_PERL    => 0,
        });
        my $template = $reg->program->cl_template . "_cancel.tt2";
        if (! -f "$rst/templates/letter/$template") {
            $template = "default_cancel.tt2";
        }
        my $stash = {
            person        => $reg->person,
            program       => $reg->program,
            credit_amount => $credit_amount,
            refund_amount => $refund_amount,
            date_expire   => $date_expire,
            user          => $c->user,
            today         => tt_today($c),
            via_authorize => $via_authorize,
        };
        $tt->process(
            $template,      # template
            $stash,         # variables
            \$html,         # output
        ) or die "error in processing template: "
                 . $tt->error();
        #
        # assume the letter will be successfully
        # printed or sent.
        #
        _reg_hist($c, $id, "Cancellation Letter sent");
        if ($reg->person->email) {
            email_letter($c,
                to      => $reg->person->name_email(),
                from    => "$string{from_title} <$string{from}>",
                subject => "Cancellation of Registration for "
                          . $reg->program->title,
                html    => $html, 
            );
            # and fall through to the view
        }
        else {
            $c->res->output($html);
            # because the user may refresh this screen
            # I was careful about any actions above
            # being conditional on $reg->cancelled() ne 'yes'...
            #
            return;
        }
    }
    $c->response->redirect($c->uri_for("/registration/view/$id"));
    return;
}

#
# utility sub for adding RegHistory records
# takes care of getting the current user, date and time.
#
sub _reg_hist {
    my ($c, $reg_id, $what) = @_;

    my $username = $c->user->username();
    my ($u) = model($c, 'User')->search({
        username => $username,
    });
    my $user_id = $u->id();
    my $now_date = tt_today($c)->as_d8();
    my $now_time = get_time()->t24();
    model($c, 'RegHistory')->create({
        reg_id   => $reg_id,
        what     => $what,
        user_id  => $user_id,
        the_date => $now_date,
        time     => $now_time,
    });
}

sub new_charge : Local {
    my ($self, $c, $id, $from) = @_;

    my $reg = model($c, 'Registration')->find($id);
    stash($c,
        from      => $from,
        reg       => $reg,
        type_opts => charges_and_payments_options(),
        template  => "registration/new_charge.tt2",
    );
}

sub new_charge_do : Local {
    my ($self, $c, $reg_id) = @_;

    my $amount = trim($c->request->params->{amount});
    my $type = $c->request->params->{type};
    my $what   = trim($c->request->params->{what} || "");
    
    my @mess = ();
    if (empty($amount)) {
        push @mess, "Missing Amount";
    }
    if (invalid_amount($amount)) {
        push @mess, "Illegal Amount: $amount";
    }
    if (@mess) {
        error($c,
            join("<br>", @mess),
            "registration/error.tt2",
        );
        return;
    }

    my @who_now = get_now($c);
    push @who_now, reg_id => $reg_id;
    model($c, 'RegCharge')->create({
        amount    => $amount,
        type      => $type,
        what      => $what,
        reg_id    => $reg_id,
        @who_now,
        automatic => '',        # this charge will not be cleared
                                # when editing a registration.
    });
    my $reg = model($c, 'Registration')->find($reg_id);
    $reg->update({
        balance => $reg->balance + $amount,
    });
    $what = " - $what" if $what;
    model($c, 'RegHistory')->create({
        reg_id    => $reg_id,
        @who_now,
        what    => "New charge of \$$amount - $charge_type[$type]$what",
    });
    if ($c->request->params->{from}
        && $c->request->params->{from} eq 'edit_dollar'
    ) {
        $c->response->redirect($c->uri_for("/registration/edit_dollar/$reg_id"));
    }
    else {
        $c->response->redirect($c->uri_for("/registration/view/$reg_id"));
    }
}

#
# Ajax call
#
sub matchreg : Local {
    my ($self, $c, $prog_id, $pat) = @_;

    if (! defined($pat)) {
        $pat = "";
    }
    $pat = trim($pat);
    $pat =~ s{\*}{%}g;
    my ($pref_last, $pref_first);
    if ($pat =~ m{(\S+)\s+(\S+)}) {
        ($pref_last, $pref_first) = ($1, $2);
    }
    else {
        $pref_last = $pat;
        $pref_first = "";
    }
    my $pr = model($c, 'Program')->find($prog_id);
    my @name_match = ();
    if ($pref_last) {
        push @name_match, 'person.last' => { like => "$pref_last%"  };
    }
    if ($pref_first) {
        push @name_match, 'person.first' => { like => "$pref_first%" };
    }
    my @regs = model($c, 'Registration')->search(
        {
            program_id     => $prog_id,
            @name_match,
        },
        {
            join     => [qw/ person /],
            order_by => [qw/ person.last person.first me.date_start /],
            prefetch => [qw/ person /],   
        }
    );
    Global->init($c);
    $c->res->output(_reg_table($c, \@regs));
}

sub print_list : Local {
    my ($self, $c, $prog_id) = @_;
    my $program = model($c, 'Program')->find($prog_id);
    my @regs = model($c, 'Registration')->search(
        {
            program_id     => $prog_id,
        },
        {
            join     => [qw/ person /],
            order_by => [qw/ person.last person.first me.date_start /],
            prefetch => [qw/ person /],   
        }
    );
    Global->init($c);
    my $tt = Template->new({
        INCLUDE_PATH => 'root/src',
        INTERPOLATE  => 1,
        EVAL_PERL    => 0,
    }) or die Template->error();
    my $stash = {
        program => $program,
        regs    => _reg_table($c, \@regs, sans_icons => 1),
        today   => tt_today($c),
    };
    my $html;
    $tt->process(
        "registration/print_list.tt2",   # template
        $stash,               # variables
        \$html,               # output
    ) or die $tt->error();
    $c->res->output($html);
}

sub csv_labels : Local {
    my ($self, $c, $prog_id) = @_;
    my $program = model($c, 'Program')->find($prog_id);
    my @regs = model($c, 'Registration')->search(
        {
            program_id     => $prog_id,
            cancelled      => '',
        },
        {
            join     => [qw/ person /],
            order_by => [qw/ person.last person.first me.date_start /],
            prefetch => [qw/ person /],   
        }
    );
    open my $labs, '>', 'root/static/labels.txt';
    for my $r (@regs) {
        my $h = $r->house;
        my $p = $r->person;
        my $h_type = $r->h_type;
        my $h_name;
        if ($h_type eq 'own_van') {
            $h_name = 'Own Van';
        }
        elsif ($h_type eq 'commuting') {
            $h_name = 'Commuting';
        }
        elsif ($h_type eq 'unknown' || $h_type eq 'not_needed') {
            $h_name = 'No Housing';
        }
        else {
            $h_name = $h->name;
            my $cluster_name = $h->cluster->name;
            if ($cluster_name =~ m{Conference}xms) {
                $h_name = 'CC ' . $h_name;
                $h_name =~ s{[BH]+ \z}{}xms;
            }
        }
        print {$labs} join(', ', $p->first, $p->last, $h_name) . "\n";
    }
    $c->response->redirect($c->uri_for("/static/labels.txt"));
}

sub badges : Local {
    my ($self, $c, $prog_id) = @_;
    my $program = model($c, 'Program')->find($prog_id);
    my ($mess, $title, $code, $data_aref) = 
        Badge->get_badge_data_from_program($c, $program);
    if ($mess) {
        $mess .= "<p class=p2>Close this window.";
        stash($c,
            mess     => $mess,
            template => "gen_message.tt2",
        );
        return;
    }
    Badge->initialize($c);
    Badge->add_group(
        $title,
        $code,
        $data_aref,
    );
    $c->res->output(Badge->finalize());
}

sub badge : Local {
    my ($self, $c, $reg_id) = @_;
    my $reg = model($c, 'Registration')->find($reg_id);
    my ($mess, $title, $code) = Badge->get_title_code($reg->program);
    if ($mess) {
        $mess .= "<p class=p2>Close this window.";
        stash($c,
            mess     => $mess,
            template => "gen_message.tt2",
        );
        return;
    }
    Badge->initialize($c);
    Badge->add_group(
        $title,
        $code,
        [{
            name  => $reg->person->badge_name,
            dates => $reg->dates,
            room  => $reg->house_name,
        }],
    );
    $c->res->output(Badge->finalize());
}

#
# if only one - make it larger - for fun.
# this is not used if we go there directly, yes???
#
sub _reg_table {
    my ($c, $reg_aref, %opt) = @_;

    my $mmi_admin = $c->check_user_roles('mmi_admin');
    my $proghead = "";
    my $show_arrived = 0;
    if ($opt{multiple}) {
        $proghead = "<th align=left>Program</th>\n";
    }
    else {
        # all in same program, shall we show the arrived ones?
        #
        if (@$reg_aref) {
            my $pr = $reg_aref->[0]->program();
            $show_arrived = 1;
        }
    }
    my $posthead = "";
    if ($opt{postmark}) {
        $posthead = "<th align=center>Postmark</th>\n";
    }
    my $heading = <<"EOH";
<tr>
$proghead
<td></td>       <!-- for the marks -->
<th align=left>Name</th>
<th align=right>Balance</th>
<th align=left>House Type</th>
<th align=left>House</th>
<th align=left>Dates</th>
<th align=left>Status</th>
$posthead
</tr>
EOH
    my $body = "";
    my %progs = ();
    my $class = "fl_row0";
    my $prev_name = "";
    for my $reg (@$reg_aref) {
        # look up the program record and remember it
        # in a cache for the next time.
        #
        my $pr;
        my $pid = $reg->program_id();
        if (exists $progs{$pid}) {
            $pr = $progs{$pid};
        }
        else {
            $pr = $progs{$pid} = $reg->program();
        }
        my $school = $pr->school();
        my $level = $pr->level();
        my $per = $reg->person;
        my $id = $reg->id;
        my $name = $per->last . ", " . $per->first;
        #
        # if there are duplicate names in the reg list
        # then we need to determine if all can have confirmation
        # letters.  PRs do.  Other allow_dup_regs programs do not.
        # is this the first reg for this person?
        #
        my $first = $pr->PR();
        if ($name ne $prev_name) {
            $class = ($class eq "fl_row0")? "fl_row1"
                     :                      "fl_row0"
                     ;
            $prev_name = $name;
            $first = 1;
        }
        my $balance = $reg->balance_disp();
        my $type = $reg->h_type_disp();

        my $h_type = $reg->h_type();
        my $pref1 = $reg->pref1();
        my $pref2 = $reg->pref2();

        my $need_house = (defined $type)? $type !~ m{commut|van|unk|needed}i
                         :                0;
        my $hid = $reg->house_id;
        my $house = ($reg->h_name)? "(" . $reg->h_name . ")"
                   :($hid        )? $house_name_of{$hid}
                   :                "";
        my $date = date($reg->date_postmark);
        my $time = $reg->time_postmark_obj();
        my $ht = 20;
        my $mark = ($reg->cancelled)?
                       "<img src=/static/images/redX.gif height=$ht>"
                  :($need_house && !$hid)?
                       "<img src=/static/images/house.gif height=$ht>"
                  :($first
                    && $level->name =~ /course/i
                    && !$reg->letter_sent)?
                       "<img src=/static/images/envelope.jpg height=$ht>"
                  :    "";
        if ($reg->leader_assistant) {
            my $pref = ($reg->person->sex eq 'F'? "fe": "");
            $mark = "$mark <img src=/static/images/${pref}male_leader.png>";
        }
        if ($need_house && $hid) {
            # no height= since it pixelizes it :(
            my $unhappy = "";
            if ($pref1 || $pref2) {
                if ($h_type ne $pref1 && $h_type ne $pref2) {
                    $unhappy = "<img src=/static/images/unhappy2.gif>";
                }
                elsif ($h_type ne $pref1) {
                    $unhappy = "<img src=/static/images/unhappy1.gif>";
                }
            }
            # pretty funky.   a better way to avoid unneeded spaces???
            # could put icons in an array and at the end
            # do a join with ' '.
            if ($unhappy) {
                if ($mark) {
                    $mark = "$unhappy $mark";
                }
                else {
                    $mark = $unhappy;
                }
            }
        }
        if ($school->mmi() && $pr->level->name() eq 'Course') {
            my $lt = long_term_registration($c, $reg->person->id());
            my $type = 'A';
            if (ref($lt)) {
                $type = 'C';    # for 'Credentialed'
            }
            if ($mark =~ /envelope/ && $type eq 'C') {
                # no confirmation letter for MMI credentialed people
                # auditors, yes.
                $mark =~ s{<img src=/static/images/envelope.jpg height=\d+>}{};
            }
            $mark = "$type $mark";
        }
        my $comment = $reg->comment;
        if ($comment && $comment =~ m{outstanding\s+balance}xmsi) {
            $mark = "<span class=outbal>O</span> $mark";
        }
        if ($show_arrived
            && $reg->arrived() eq 'yes'
            && $reg->cancelled() ne 'yes'
        ) {
            $mark = "<span class=arrived_star>*</span> $mark";
        }
        # we don't want the marks if we're printing
        # the list for the program presenter...
        if ($opt{sans_icons}) {
            $mark = $reg->cancelled()? 'X': '';
        }
        my $program_td = "";
        if ($opt{multiple}) {
            $program_td = "<td>" . $pr->name() . "</td>\n";
        }
        my $early_late = "";
        if ($reg->early() || $reg->late()) {
            $early_late = $reg->date_start_obj->format("%e")
                        . "-"
                        . $reg->date_end_obj->format("%e")
                        ;
        }
        my $status = "";
        if ($pr->extradays() && $reg->date_end() > $pr->edate()) {
            # they stayed beyond the normal program end date so...
            #
            $status = "Full";
        }
        if (! empty($reg->ceu_license())) {
            if ($status) {
                $status .= ", ";
            }
            $status .= "CEU";
        }
        my $postmark_td = "";
        if ($opt{postmark}) {
            $postmark_td = <<"EOH";
<td>
<span class=rname2>$date&nbsp;&nbsp;$time</span>
</td>
EOH
        }
        my $pay_balance = $balance;
        if (! $reg->cancelled && $balance > 0
            && (! $school->mmi() || $mmi_admin)
        ) {
            $pay_balance =
                "<a href='/registration/pay_balance/$id/list_reg_name'>"
               ."$pay_balance</a>";
        }
        if (! $school->mmi() || $mmi_admin) {
            $name = <<"EOH"
<a href='/registration/view/$id'
   onmouseover="overlib('$string{$pref1} | $string{$pref2}',
                        RIGHT, MOUSEOFF, TEXTSIZE, '13pt',
                        FGCOLOR, '#FFFFFF', DELAY, '600',
                        CELLPAD, 10, WRAP);"
   onmouseout="return nd();"
>$name</a>
EOH
        }
        $body .= <<"EOH";
<tr class=$class>

$program_td
<td align=right class=fl_row0>$mark</td>

<td>    <!-- width??? -->
$name
</td>

<td align=right>$pay_balance</td>
<td>$type</td>
<td>$house</td>
<td>$early_late</td>
<td>$status</td>
$postmark_td

</tr>
EOH
    }
    if ($opt{sans_icons}) {
        # remove any <a> tags
        $body =~ s{<a[^>]*>}{}xmsg;
        $body =~ s{</a>}{}xmsg;
    }
    $body ||= "";
    return <<"EOH";        # returning a bare string heredoc constant?  sure.
<table cellpadding=4>
$heading
$body
</table>
EOH
}

sub update_confnote : Local {
    my ($self, $c, $id) = @_;

    my $reg = model($c, 'Registration')->find($id);
    my $cn = $reg->confnote();

    stash($c,
        reg        => $reg,
        note       => $cn,
        note_lines => lines($cn) + 3,
        template   => "registration/confnote.tt2",
    );
}
sub update_confnote_do : Local {
    my ($self, $c, $id) = @_;

    my $reg = model($c, 'Registration')->find($id);
    my $newnote = cf_expand($c, $c->request->params->{confnote});
    if ($reg->confnote() ne $newnote) {
        $reg->update({
            confnote    => $newnote,
            letter_sent => '',
        });
        _reg_hist($c, $id, "Confirmation Note updated");
    }
    _check_spelling($c, $newnote);
    $c->response->redirect($c->uri_for("/registration/view/$id"));
}
sub _check_spelling {
    my ($c, $newnote) = @_;
    open my $spell, "| aspell -H list |sort -fu | "
                  . "comm -23 - $rst/okaywords.txt >/tmp/spellout"
        or $c->log->info("cannot open spell");
    print {$spell} $newnote;
    close $spell;
    system("sort -u /tmp/spellout $rst/maybewords.txt > $rst/newmaybewords.txt;"
         . "mv $rst/newmaybewords.txt $rst/maybewords.txt");
}
sub update_comment : Local {
    my ($self, $c, $id) = @_;

    my $reg = model($c, 'Registration')->find($id);
    my $comment = $reg->comment();
    stash($c,
        reg           => $reg,
        comment       => $comment,
        comment_lines => lines($comment) + 3,
        template      => "registration/comment.tt2",
    );
}
sub update_comment_do : Local{
    my ($self, $c, $id) = @_;

    my $reg = model($c, 'Registration')->find($id);
    $reg->update({
        comment => etrim($c->request->params->{comment}),
    });
    _reg_hist($c, $id, "Comment updated");
    $c->response->redirect($c->uri_for("/registration/view/$id"));
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $reg = model($c, 'Registration')->find($id);
    my $pr  = $reg->program();
    my $this_ref = $reg->referral || '';
    for my $ref (qw/ad web brochure flyer word_of_mouth/) {
        stash($c, "$ref\_selected" => ($this_ref eq $ref)? "selected": "");
    }
    if ($pr->footnotes =~ m{[*]}) {
        stash($c, ceu => 1);
    }
    my $h_type_opts = "";
    my $h_type_opts1 = "";
    my $h_type_opts2 = "";
    Global->init($c);     # get %string ready.
    my $cur_htype = $reg->h_type();
    HTYPE:
    for my $htname (housing_types(2)) {
        next HTYPE if $htname eq "single_bath" && ! $pr->sbath;
        next HTYPE if $htname eq "single"      && ! $pr->single;
        next HTYPE if $htname eq "economy"     && ! $pr->economy;
        next HTYPE if $htname eq "commuting"   && ! $pr->commuting;
        next HTYPE if    $htname ne "unknown"
                      && $htname ne "not_needed"
                      && $htname ne "commuting"
                      && $pr->housecost->$htname() == 0;     # wow!
        next HTYPE if $htname eq 'center_tent'
                      && wintertime($reg->date_start());

        my $selected = ($htname eq $cur_htype)? " selected": "";
        my $selected1 = ($htname eq $reg->pref1())? " selected": "";
        my $selected2 = ($htname eq $reg->pref2())? " selected": "";
        my $htdesc = $string{$htname};
        $htdesc =~ s{\(.*\)}{};              # registrar doesn't need this
        $htdesc =~ s{Mount Madonna }{};      # ... Center Tent
        $h_type_opts .= "<option value=$htname$selected>$htdesc\n";
        $h_type_opts1 .= "<option value=$htname$selected1>$htdesc\n";
        $h_type_opts2 .= "<option value=$htname$selected2>$htdesc\n";
    }
    my $status = $reg->status();      # status at time of first registration
    if ($status && 
        ($pr->PR() || $pr->retreat())
    ) {
        my $mem = $reg->person->member();
        my $nights = $mem->sponsor_nights() + $reg->nights_taken();
        if ($pr->housecost->type() eq 'Per Day' && $nights > 0) {
            stash($c, nights => $nights);
        }
        if (($status eq 'Life' || $status eq 'Founding Life')
            && ! $pr->PR()
            && (! $mem->free_prog_taken || $reg->free_prog_taken())
        ) {
            stash($c, free_prog => 1);
        }
    }
    my $c_r = $reg->cabin_room() || '';
    my $fw = $reg->from_where() || '';
    stash($c,
        person          => $reg->person,
        reg             => $reg,
        program         => $pr,
        h_type_opts     => $h_type_opts,
        h_type_opts1    => $h_type_opts1,
        h_type_opts2    => $h_type_opts2,

        carpool_checked => $reg->carpool()   ? "checked": "",
        hascar_checked  => $reg->hascar()    ? "checked": "",
        home_checked    => $fw eq 'Home'? 'checked': '',
        sjc_checked     => $fw eq 'SJC'? 'checked': '',
        sfo_checked     => $fw eq 'SFO'? 'checked': '',
        from_where_display => $reg->carpool()? "block"  : "none",

        cabin_checked   => $c_r eq 'cabin'   ? "checked": "",
        room_checked    => $c_r eq 'room'    ? "checked": "",
        work_study_checked        => $reg->work_study()       ? "checked": "",
        work_study_safety_checked => $reg->work_study_safety() 
                                     || $reg->person->safety_form()? "checked"
                                                                     : "",
        rental_before_checked => $reg->rental_before()? "checked": "",
        rental_after_checked  => $reg->rental_after()? "checked": "",
        note_lines      => lines($reg->confnote()) + 3,
        comment_lines   => lines($reg->comment ()) + 3,
        template        => "registration/edit.tt2",
    );
}

sub conf_history : Local {
    my ($self, $c, $id) = @_;

    my $reg = model($c, 'Registration')->find($id);
    stash($c,
        reg      => $reg,
        template => "registration/conf_hist.tt2",
    );
}

#
# there's a lot to do.
#
# check the validity of the fields
# update the reg record
# recompute charges
#
sub update_do : Local {
    my ($self, $c, $id) = @_;

    _get_data($c);
    if (@mess) {
        error($c,
            join("<br>", @mess),
            "registration/error.tt2",
        );
        return;
    }

    my $reg = model($c, 'Registration')->find($id);
    my $pr  = model($c, 'Program'     )->find($reg->program_id);

    my @who_now = get_now($c);
    push @who_now, reg_id => $id;

    %dates = transform_dates($pr, %dates);
    if ($dates{date_start} == $dates{date_end}
        && $P{h_type} ne 'commuting')
    {
        error($c,
            "Housing type must be Commuting when"
                . " start date = end date.",
            "registration/error.tt2",
        );
        return;
    }
    if ($dates{date_start} > $dates{date_end}) {
        error($c,
            "Start date is after the end date.",
            "registration/error.tt2",
        );
        return;
    }
    my $dates_changed = ($dates{date_start} != $reg->date_start())
                        ||
                        ($dates{date_end}   != $reg->date_end())
                        ;
    if ($dates_changed && $pr->PR) {
        # a personal retreat - the new dates might have a PR alert...
        my @alerts = get_PR_alerts($c, $dates{date_start}, $dates{date_end});
        if (@alerts) {
            stash($c, alerts => join "\\n\\n", @alerts);
        }
    }
    if ($reg->house_id()
        && (($P{h_type} ne $reg->h_type())
            ||
            $dates_changed
           )
        ) {
        # housing type has changed!  and we have a prior house.
        # before we do the update of the reg record
        # we must first vacate the house and adjust the config records.
        #
        # OR the dates have changed... this, too, invalidates
        # the housing and we need to vacate and relodge.
        #
        stash($c, message1 => "Vacated " . $reg->house->name . ".");
                                    # see lodge.tt2 
        _vacate($c, $reg);
    }
    my $newnote = cf_expand($c, $c->request->params->{confnote});
    # avoid uninitialized warnings...
    my $r_confnote = $reg->confnote() || '';
    my $r_kids = $reg->kids() || '';
    _check_spelling($c, $newnote);
    my @note_opt = ();
    if ($r_confnote ne $newnote) {
        @note_opt = (
            confnote    => $newnote,
            letter_sent => '',
        );
    }
    if ($P{kids} ne $r_kids) {
        #
        # the kids field changed
        #
        my $h_id = $reg->house_id();
        if ($h_id) {
            #
            # housing HAD been assigned already
            # we will likely need to adjust it.
            #
            # a kid has been added (or removed) after the initial
            # registration and housing.  there are several use cases.
            #
            # if a kid was added and the current housing has just
            # one person for the length of the stay,
            # resize it to a single to make it unavailable to others.
            #
            # if all kids were removed and the house currently has one person
            # in a resized single for the length of the stay, 
            # undo the resize to free up the other beds.
            #
            # if there is more than one person in the room at some point
            # during the stay we must have just added a kid so
            # vacate the room and fall through to prompt for new lodging.
            # We can't put the kid in the same room that the parent had before.
            #
            my $sdate = $reg->date_start;
            my $edate1 = (date($reg->date_end) - 1)->as_d8();
            my @more_than_one = model($c, 'Config')->search({
                house_id => $h_id,
                the_date => { 'between' => [ $sdate, $edate1 ] },
                cur      => { '>' => 1 },
            });
            if (@more_than_one) {
                _vacate($c, $reg);
            }
            else {
                if ($P{kids}) {
                    #
                    # kids were added
                    # can resize the room
                    # we don't show the kids per se - even
                    # with more than one kid we still just resize
                    # the room as if the parent had a single.
                    #
                    model($c, 'Config')->search({
                        house_id => $h_id,
                        the_date => { 'between' => [ $sdate, $edate1 ] },
                    })->update({
                        curmax => 1,
                    });
                    #
                    # the kid change COULD have been to change the age
                    # of a kid that was already there - or to add a second
                    # kid to one that was already there.   In these cases
                    # the above operation will have a null effect.
                    #
                }
                else {
                    # kids were removed
                    # undo the resizing - put the curmax back to the 
                    # size of the house - or rather to the size of
                    # the parent's chosen housing type (which may have changed!).
                    # the parent may have chosen Double but was put
                    # into a Triple.  Is this right?  Not sure.
                    #
                    my $max    = type_max($P{h_type});
                    my $house_max = model($c, 'House')->find($h_id)->max;
                    my $cmax = $max;
                    if ($max > $house_max) {
                        $cmax = $house_max;
                    }
                    model($c, 'Config')->search({
                        house_id => $h_id,
                        the_date => { 'between' => [ $sdate, $edate1 ] },
                    })->update({
                        curmax => $cmax,
                    });
                }
            }
        }
        else {
            # housing has not yet been assigned so we fall through and
            # prompt for lodging as usual.
        }
        # I'm wondering how the registar knows the type
        # of house to put the parent and kids in...  And what
        # housing type is okay to use.  For example, if
        # a parent comes with 2 kids they'll need to be put
        # in at least a Triple.  Does that mean that the parent
        # pays at the triple rate?   Or the single rate?
        # the kids are half price of what the parent pays, yes?
    }
    $reg->update({
        ceu_license   => $P{ceu_license},
        referral      => $P{referral},
        adsource      => $P{adsource},
        carpool       => $P{carpool},
        hascar        => $P{hascar},
        from_where    => $P{from_where},
        comment       => etrim($P{comment}),
        h_type        => $P{h_type},
        h_name        => $P{h_name},
        kids          => $P{kids},
        nights_taken  => $taken,
        cabin_room    => $P{cabin_room},
        share_first   => normalize($P{share_first}),
        share_last    => normalize($P{share_last}),
        pref1         => $P{pref1},
        pref2         => $P{pref2},
        work_study         => $P{work_study},
        work_study_comment => $P{work_study_comment},
        work_study_safety  => $P{work_study_safety},
        rental_before => $P{rental_before},
        rental_after  => $P{rental_after},
        free_prog_taken    => $P{free_prog},

        %dates,         # optionally
        @note_opt,           # ditto
    });
    if ($P{work_study_safety}) {
        # ensure that the safety_form field on the 
        # person record is set.
        if (! $reg->person->safety_form()) {
            $reg->person->update({
                safety_form => 'yes',
            });
        }
        # ensure the person has the affil 'Work Study'
        my $person_id = $reg->person_id();
        my %has_affil = map { $_->a_id => 1 }
                        model($c, 'AffilPerson')->search({
                            p_id => $person_id,
                         });
        my $ws_affil_id = $system_affil_id_for{'Work Study'};
        if (! $has_affil{$ws_affil_id}) {
            model($c, 'AffilPerson')->create({
                p_id => $person_id,
                a_id => $ws_affil_id,
            });
        }
    }

    # might as well recompute the automatic charges.
    # several things could have changed that affected the cost.
    # it is too troublesome to check them all to see if one of them changed.
    _compute($c, $reg, 0, @who_now);

    _reg_hist($c, $id, "Registration Updated.");
    if ($reg->house_id() || $reg->h_type() =~ m{van|commut|unk|need}) {
        $c->response->redirect($c->uri_for("/registration/view/$id"));
    }
    else {
        lodge($self, $c, $id);
    }
}

#
# a manual registration.
# at this point we have chosen a person, a program
# and have specified a deposit, a deposit type and a postmark date.
# if the program is a PR we also have a date range.
# we now need to get the rest of the registration details.
#
sub manual : Local {
    my ($self, $c) = @_;

    %P = %{ $c->request->params() };
    my @mess = ();
    my $deposit      = $P{deposit};
    if (invalid_amount($deposit)) {
        push @mess, "Illegal deposit: $deposit";
    }
    my $deposit_type = $P{deposit_type};
    my $date_post    = $P{date_post};
    my $d = date($date_post);
    if (! $d) {
        push @mess, "Illegal postmark date: $date_post";
    }
    $date_post = $d;

    my $person_id    = $P{person_id};
    my $pers = model($c, 'Person')->find($person_id);

    my $program_id   = $P{program_id};
    if ($P{program_id} eq '0') {
        push @mess, "No program selected.";
    }
    my @date_range = ();
    if ($program_id =~ s{p\z}{}) {  # trim a 'p' which indicates a PR
                                    # pretty hacky, huh?
        # we have a Personal Retreat.
        # verify the date range
        #
        my $start = date($P{sdate});
        my $end   = date($P{edate});
        if (! $start || ! $end || $start > $end || $start < tt_today($c)) {
            push @mess, "Illegal date range for Personal Retreat";
        }
        else {
            @date_range = (
                date_start => $start,
                date_end   => $end,
            );
        }
    }
    if (@mess) {
        error($c,
            join("<br>", @mess),
            "registration/error.tt2",
        );
        return;
    }
    my $prog = model($c, 'Program')->find($program_id);
    stash($c,
        deposit       => $deposit,
        deposit_type  => $deposit_type,
        date_postmark => $date_post->as_d8(),
        time_postmark => "0000",        # good guess?
        cabin_checked => "",
        room_checked  => "",
        @date_range,
    );
    my @housing = ($prog->category->name() ne 'Normal')?
                        ('single', 'single', 'room')
                  :     ('dble',   'dble',   'room')
                  ;
    _rest_of_reg($prog, $pers, $c, tt_today($c), @housing);
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    my $reg = model($c, 'Registration')->find($id);
    my (@other_reg) = model($c, 'Registration')->search({
                          person_id  => $reg->person_id(),
                          program_id => $reg->program_id(),
                          id         => { '!=' => $id },
                      });
    my $prog_id   = $reg->program_id;

    # clear any member activity for this registration
    if ($reg->free_prog_taken() || $reg->nights_taken()) {
        my $mem = $reg->person->member();
        if ($mem) {
            model($c, 'NightHist')->search({
                member_id => $mem->id(),
                reg_id    => $id,
            })->delete();
            reset_mem($c, $mem);
        }
    }

    #
    # decrement the regcount
    # unless this registration was cancelled
    # or this is a duplicated registration (but not a PR).
    #
    if (!($reg->cancelled() || (@other_reg && ! $reg->program->PR()))) {
        model($c, 'Program')->find($prog_id)->update({
            reg_count => \'reg_count - 1',
        });
    }

    _vacate($c, $reg) if $reg->house_id;

    $reg->delete();     # does this cascade to charges, payments, history? etc.?
                        # yes.  Thank you to DBIC!
    $c->response->redirect($c->uri_for("/registration/list_reg_name/$prog_id"));
}

sub early_late : Local {
    my ($self, $c, $prog_id) = @_;

    my $pr   = model($c, 'Program')->find($prog_id);
    my $sdate = $pr->sdate;
    my $edate = $pr->edate;
    my $edate2 = ($pr->extradays)? ($pr->edate_obj + $pr->extradays)->as_d8()
                 :                 $edate;
    my @regs = sort {
                   $a->{name} cmp $b->{name}
               }
               map {
                   my $p = $_->person;
                   {
                       id     => $_->id,
                       name   => $p->last . ", " . $p->first,
                       arrive => ($_->date_start eq $sdate)? ""
                                 :               $_->date_start_obj->format,
                       leave  => ($_->date_end eq $edate)? ""
                                 :               $_->date_end_obj->format,
                   }
               }
               model($c, 'Registration')->search({
                   program_id => $prog_id,
                   -or => [
                       early => 'yes',
                       late  => 'yes',
                   ],
               });
    if ($pr->extradays) {
        stash($c, plus => $pr->edate_obj() + $pr->extradays);
    }
    stash($c,
        program       => $pr,
        registrations => \@regs,
        template      => "registration/early_late.tt2",
    );
}

sub arrived : Local {
    my ($self, $c, $id) = @_;

    my $r = model($c, 'Registration')->find($id);
    $r->update({
        arrived => 'yes',
    });
    $c->response->redirect($c->uri_for("/registration/view/$id"));
}

sub not_arrived : Local {
    my ($self, $c, $id) = @_;

    my $r = model($c, 'Registration')->find($id);
    $r->update({
        arrived => '',
    });
    $c->response->redirect($c->uri_for("/registration/view/$id"));
}

#
# Choosing a house (given a housing type)
# should not affect the costs - unless you change
# housing type on the lodging screen, that is.
#
sub lodge : Local {
    my ($self, $c, $id) = @_;

    my $reg        = model($c, 'Registration')->find($id);
    my $pr         = $reg->program();
    my $PR         = $pr->PR();
    my $program_id = $reg->program_id();

    my %reserved_cids = 
        map {
            $_->cluster_id() => 1
        }
        model($c, 'ProgramCluster')->search({
            program_id => $program_id,
        });

    my $cutoff = (tt_today($c)+$string{make_up_clean_days})->as_d8();
            # for makeup list checking

    #
    # housed with a friend who is also registered for this program?
    #
    my $share_house_id = 0;
    my $share_house_name = "";
    my $share_first = $reg->share_first();
    my $share_last  = $reg->share_last();
    my $share_name = $share_first? "$share_first $share_last": '';
    my $message2 = "";
    my $reg2 = undef;
    if ($share_first) {
        my (@people) = model($c, 'Person')->search({
            first => $share_first,
            last  => $share_last,
        });
        # there may be more than one person matching :(
        # find the one (hopefully not > 1!) that is registered
        # for this program.
        #
        PEOPLE:
        for my $person (@people) {
            ($reg2) = model($c, 'Registration')->search({
                             person_id  => $person->id(),
                             program_id => $program_id,
                      });
            if ($reg2) {
                last PEOPLE;
            }
        }
        if (! @people) {
            $message2 = "Could not find a person named $share_name.";
        }
        elsif (!$reg2) {
            $message2 = "$share_name has not yet registered for "
                      . $reg->program->name . ".";
        }
        elsif ($reg2->cancelled()) {
            $message2 = "$share_name has cancelled.";
        }
        elsif (! $reg2->house_id()) {
            $message2 = "$share_name has not yet been housed.";
        }
        elsif ($reg2->h_type() ne $reg->h_type()) {
            $message2 = "$share_name is housed in a '"
                      . $reg2->h_type_disp
                      . "' not a '"
                      . $reg->h_type_disp
                      . "'."
                      ;
        }
        elsif ($reg2->person->sex() ne $reg->person->sex()
               && $reg2->h_type() =~ m{triple|dormitory|economy}i
        ) { 
            # if they're of opposite genders there is a
            # further condition that they can't be in 
            # economy, dorm, or triple - because there may
            # very well be strangers in there.
            # If three (or more) people (not all of the same gender)
            # wish to share a triple/dormitory/economy it can be
            # FORCED for the unhoused person of a different gender
            # than the person already housed.
            #
            $message2 = "Since "
                      . $reg->person->first()
                      . " and "
                      . $reg2->person->first()
                      . " are not of the same gender they cannot share<br>"
                      . $reg2->h_type()
                      . " housing in " 
                      . $reg2->house->name()
                      . "."
                      . " This can be forced, if you wish."
                      ;
        }
        else {
            # okay!  we will permit them to share.
            #
            $share_house_name = $reg2->house->name;
            $share_house_id   = $reg2->house_id;
            $message2 = "Share $share_house_name"
                       ." with $share_name?";
        }
        #
        # if the person hasn't yet registered for this program
        # look for them in the online files.
        #
        if ($message2 =~ m{Could not find|has not yet reg}) {
            my $found = 0;
            ONLINE:
            for my $f (<$rst/online/*>) {
                open my $in, "<", $f
                    or die "cannot open $f: $!\n";
                # x_fname, x_lname - could be anywhere in the file
                my ($found_first, $found_last) = (0, 0);
                while (<$in>) {
                    if (m{x_fname => $share_first}i) {
                        $found_first = 1;
                    }
                    elsif (m{x_lname => $share_last}i) {
                        $found_last = 1;
                    }
                }
                close $in;
                if ($found_first && $found_last) {
                    $message2 = "$share_name <b>has</b> registered"
                              . " online but has not yet been imported.";
                    $found = 1;
                    last ONLINE;
                }
            }
            if (! $found) {
                #
                # make sure the confirmation note has a notice
                # about their friend who has not yet registered.
                #
                if ($reg->confnote() !~ m{$share_name}) {
                    my $cn = ptrim($reg->confnote());
                    if ($cn) {
                        $cn .= "<p></p>";
                    }
                    $reg->update({
                        confnote => $cn
                                  . "<p>$share_name still needs"
                                  . " to register for this program!</p>",
                    });
                }
            }
        }
    }
    my $sdate = $reg->date_start;
    my $edate1 = (date($reg->date_end) - 1)->as_d8();

    my $summer = ! wintertime($reg->date_start());

    my $h_type = $reg->h_type;
    my $bath   = ($h_type =~ m{bath}  )? "yes": "";
    my $tent   = ($h_type =~ m{tent}  )? "yes": "";
    my $center = ($h_type =~ m{center})? "yes": "";
    my $psex   = $reg->person->sex;
    my $max    = type_max($h_type);
    my $low_max =  $max ==  7? 4
                  :$max == 20? 8
                  :            $max;
    my $cabin  = $reg->cabin_room() && $reg->cabin_room() eq 'cabin';
    my @kids   = ($reg->kids() && $reg->kids() =~ m{\d})? (cur => { '>', 0 })
                 :                                        ();

    my @h_opts = ();
    my $n = 0;
    my $selected = 0;

    #
    # which clusters are NOT available?
    #
    my %or_cids;
    if ($PR) {
        %or_cids = PR_other_reserved_cids($c, $reg->date_start(),
                                              $reg->date_end()   );
    }
    else {
        %or_cids = other_reserved_cids($c, $pr);
    }

    #
    # which clusters (and in what order) have
    # been designated for this program?
    #
    CLUSTER:
    for my $cl (@clusters) {
        my $cl_id = $cl->id();
        next CLUSTER if exists $or_cids{$cl_id};

        #
        # Can we eliminate this entire cluster
        # due to the type of houses/sites in it?
        #
        # using the _name_ of the cluster
        # is not the best idea but hey ...
        # one _could_ put a tent and a room in the same cluster, right?
        #
        my $cl_name = $cl->name();
        my $cl_tent   = $cl_name =~ m{tent|terrace}i
                                    && $cl_name !~ m{structure}i;
        my $cl_center_tent = $cl_name =~ m{center \s+ tent}xmsi;
        if (($tent && !$cl_tent) ||
            (!$tent && $cl_tent) ||
            ($summer && (!$center && $cl_center_tent ||
                         $center && !$cl_center_tent   ))
        ) {
            next CLUSTER;
        }
        my $pr_resident = $pr->category->name() ne 'Normal';
        HOUSE:
        for my $h (@{$houses_in_cluster{$cl_id}}) {
            # is the max of the house inconsistent with $max?
            # or the bath status
            #
            # or the house resident status != program category status
            #
            # quads are okay when looking for a dorm
            # and this takes some fancy footwork.
            #
            my $h_id = $h->id;
            if (($h->max < $low_max)
                || ($h->bath && !$bath)
                || (!$h->bath && $bath)
                || (!$pr_resident && $h->resident())
                # 9/4 Brajesh requests that all houses offered
                # to Residential enrollees.
                # || ($pr_resident  && !$h->resident())
            ) {
                next HOUSE;
            }
            my ($codes, $code_sum) = ("", 0);

            #
            # now we get current data from the database store.
            #
            # just search Config once???
            # get all the records, then do the complex
            # boolean below...
            #
            # AND why not just get ALL the config
            # records for all the houses in the cluster?
            # you're going to get them all anyway
            # so why not get them all at once?
            #
            # well, the first search below eliminates
            # the already fully occupied or gender inappropriate ones.
            # and this is done within the database - reduces
            # the data transfer.
            # I _could_ have an 'in => []'
            # and specify all the houses in the cluster
            #
            # is this house truly available for this
            # request from sdate to edate1?
            # look for ways in which it is NOT:
            #     - space
            #     - gender
            #     - room size
            #     - kids and cur > 0
            #
            my @cf = model($c, 'Config')->search({
                house_id => $h_id,
                the_date => { 'between' => [ $sdate, $edate1 ] },
                -or => [
                    \'cur >= curmax',           # all full up
                    -and => [                   # can't mix genders
                        sex => { '!=', $psex }, #   or put someone unsuspecting
                        sex => { '!=', 'U'   }, #   in an X room
                        sex => { '!=', 'B'   }, #   in an X room
                    ],
                    curmax => { '<', $low_max },    # too small
                    -and => [                   # can't resize - someone there
                        curmax => { '>', $max },
                        cur    => { '>', 0    },
                    ],
                    @kids,                      # kids => cur > 0
                ],
            });
            if (@cf) {        # nope
                next HOUSE;
            }

            # we have a good house.
            # no problematic config records were found.
            #
            # what are the attributes of the configuration records?
            #
            # O - occupied (but there is space for more)
            # F - a foreign program is already occupying this house
            # R - resize is needed
            #
            # another attribute of the house may be that
            # it still needs to be cleaned.  only put this
            # when the room is needed in 2 days or less.
            #
            # N - needs cleaning
            #
            my ($O, $F, $P) = (0, 0, 1);
            for my $cf (model($c, 'Config')->search({
                            house_id => $h_id,
                            the_date => { 'between' => [ $sdate, $edate1 ] },
                        })
            ) {
                if (!$O && $cf->cur() > 0) {
                    $O = 1;
                    if (!$F && $cf->program_id() != $program_id) {
                        $F = 1;
                    }
                }
                if ($P && $cf->curmax() > $max) {
                    $P = 0;
                }
            }
            if ($O) {
                $codes .= 'O';
                $code_sum += $string{house_sum_occupied};
            }
            if ($F) {
                $codes .= 'F';
                $code_sum += $string{house_sum_foreign};     # discourage this!
                                                             # will be < 0.
            }
            if ($P) {
                $code_sum += $string{house_sum_perfect_fit};
            }
            else {
                $codes .= 'R';      # resize needed - not as good...
            }
            if ($reserved_cids{$cl_id}) {
                $codes .= 'r';
                $code_sum += $string{house_sum_reserved};
            }
            if ($h->cabin()) {
                $codes .= 'C';
                if ($cabin) {
                    $code_sum += $string{house_sum_cabin};
                }
            }
            if ($h->cat_abode()) {
                $codes .= 'c';
            }
            # check makeup list for $h_id on $sdate
            #
            if ($sdate <= $cutoff) {
                my ($makeup) = model($c, 'MakeUp')->search({
                    house_id => $h_id,
                });
                if ($makeup) {
                    $codes .= 'N';
                    $code_sum += $string{house_sum_clean};  # negative
                }
            }
            $codes = " - $codes" if $codes;

            # put this house in an option array to be sorted according
            # to priority.  put the kind of house (resized,
            # occupied, ...) in <option>
            #
            my $opt = "<option value=" 
                      . $h_id
                      . (($h_id == $share_house_id)? " selected"
                        :                            "")
                      . ">"
                      . $h->name()
                      . $codes
                      . "</option>\n"
                      ;
            push @h_opts, [ $opt, $code_sum, $h->priority(), $h->name() ];
            ++$n;
            if ($h_id == $share_house_id) {
                $selected = 1;
            }
        }   # end of houses in this cluster
    }   # end of CLUSTER
    #
    # and now the big sort:
    #
    if ($pr->category->name() ne 'Normal') {
        @h_opts = map {
                        $_->[0]
                  }
                  sort {
                      $a->[3] cmp $b->[3]   # by name
                  }
                  @h_opts;
    }
    else {
        @h_opts = map {
                        $_->[0]
                  }
                  sort {
                      $b->[1] <=> $a->[1] ||      # 1st by code_sum - descending
                      $a->[2] <=> $b->[2]         # 2nd by priority - ascending
                  }
                  @h_opts;
    }
    if ($cabin && $h_opts[0] !~ m{-.*C}) {
        # they want a cabin and the first choice is not a cabin
        # get any cabins to the top and preserve the order
        my @rooms = ();
        my @cabins = ();
        for my $o (@h_opts) {
            if ($o =~ m{-.*C}) {
                push @cabins, $o;
            }
            else {
                push @rooms, $o;
            }
        }
        @h_opts = (@cabins, @rooms);
    }
    #
    # enforce the max_lodge_opts (if non-zero)
    # just truncate those beyond the stipulated max.
    #
    my $maxopts = $string{max_lodge_opts};
    if ($maxopts && @h_opts > $maxopts) {
        $#h_opts = $maxopts;
    }
    if ($share_house_id && ! $selected) {
        # two people want to share a house.
        # one of them is already housed.
        # the room is not in the list because of the gender mismatch
        # or a tent with nominally only one space
        # or because the room is already full.
        # yikes!
        #
        my @cf = model($c, 'Config')->search({
            house_id => $share_house_id,
            the_date => { 'between' => [ $sdate, $edate1 ] },
            -or => [
                \'cur >= curmax'
                # could not put by itself!   a one item or clause is needed?
            ],
        });
        if ($reg->h_type() !~ m{tent} && @cf) {
            $message2 .= " - Yes, that would be nice but that room is already FULL!?";
        }
        else {
            unshift @h_opts,
                "<option value=" 
                . $share_house_id
                . " selected>"
                . $share_house_name
                . " - S"
                . "</option>\n"
                ;
            $selected = 1;
        }
    }
    if (@h_opts && ! $selected) {
        # no house is otherwise selected
        # insert a select into the first one.
        $h_opts[0] =~ s{>}{ selected>};
    }
    # include kids and housing prefs
    if ($reg->kids()) {
        if (my @ages = $reg->kids() =~ m{(\d+)}g) {
            stash($c, kids => " with child" . ((@ages > 1)? "ren":""));
        }
    }
    stash($c, house_prefs => "Housing choices: "
                           . _htrans($reg->pref1())
                           . ", "
                           . _htrans($reg->pref2())
                           );
    my $cn = $reg->confnote();

    # copied - can we consolidate???
    # probably???
    my $h_type_opts = "";
    Global->init($c);     # get %string ready.
    my $cur_htype = $reg->h_type;
    HTYPE:
    for my $htname (qw/
        single_bath
        single
        dble_bath
        dble
        triple
        economy
        dormitory
        center_tent
        own_tent
        own_van
        commuting
    /) {
        next HTYPE if $htname eq "single_bath" && ! $pr->sbath;
        next HTYPE if $htname eq "single"      && ! $pr->single;
        next HTYPE if $htname eq "economy"     && ! $pr->economy;
        next HTYPE if $htname eq "commuting"   && ! $pr->commuting;
        next HTYPE if $pr->housecost->$htname == 0;     # wow!
        next HTYPE if $htname eq 'center_tent' && !$summer;

        my $selected = ($htname eq $cur_htype)? " selected": "";
        my $htdesc = $string{$htname};
        $htdesc =~ s{\(.*\)}{};              # registrar doesn't need this
        $htdesc =~ s{Mount Madonna }{};      # ... Center Tent
        $h_type_opts .= "<option value=$htname$selected>$htdesc\n";
    }
    # hacky :(  how else please?
    # these two would never be selected (or else we would
    # not be lodging them...
    #
    $h_type_opts .= "<option value=unknown"
                 .  ($cur_htype eq "unknown"? " selected"
                     :                        ""         )
                 .  ">Unknown\n";
    $h_type_opts .= "<option value=not_needed"
                 .  ($cur_htype eq "not_needed"? " selected"
                     :                           ""         )
                 .  ">Not Needed\n";

    $h_type = _htrans($h_type);

    my $p_sdate = $pr->sdate();
    my $nmonths = date($pr->edate())->month()
                - date($sdate)->month()
                + 1;
    $sdate  = date($sdate);
    $edate1 = date($edate1);
    my $n_nights = $edate1 - $sdate + 1;
    my $pl = $n_nights == 1? "": "s";
    stash($c,
        reg           => $reg,
        n_nights      => $n_nights . " night$pl",
        sdate         => $sdate,
        edate         => $reg->date_end_obj,
        note          => $cn,
        note_lines    => lines($cn) + 3,
        message2      => $message2,
        h_type        => $h_type,
        cal_param     => "$p_sdate/$nmonths",
        h_type_opts   => $h_type_opts,
        house_opts    => join('', @h_opts),
        total_opts    => scalar(@h_opts), 
        seen_opts     => $string{seen_lodge_opts},
        disp_h_type   => (($h_type =~ m{^[aeiou]})? "an": "a") . " '\u$h_type'",
        daily_pic_date => ($pr->category->name() eq "Normal"? "indoors"
                           :                                  "resident")
                           . "/"
                           . $reg->date_start(),
        cluster_date  => $reg->date_start(),
        template      => "registration/lodge.tt2",
    );
}

sub _htrans {
    my ($type) = @_;
    $type =~ s{dble}{double};
    $type =~ s{_(.)}{ \u$1};
    ucfirst $type;
}

#
# we have identified a house for this registration.
# put this in the registration record itself
# and update the config records appropriately and carefully.
#
sub lodge_do : Local {
    my ($self, $c, $id) = @_;

    my $reg = model($c, 'Registration')->find($id);
    if ($reg->house_id()) {
        # they somehow double clicked :(
        #
        stash($c,
            reg_id   => $id,
            template => "registration/dblclick.tt2",
        );
        return;
    }
    my $new_htype = $c->request->params->{htype};
    my @who_now = get_now($c);
    push @who_now, reg_id => $id;

    if ($reg->h_type() ne $new_htype) {
        # the housing type was changed
        $reg->update({
            h_type => $new_htype,
        });
        # recompute the automatic charges since h_type changed
        _compute($c, $reg, 0, @who_now);

        if ($new_htype =~ m{^(own_van|commuting|unknown|not_needed)$}) {
                        # hash lookup instead?
            _reg_hist($c, $id, "Lodged as $string{$new_htype}.");
            $c->response->redirect($c->uri_for("/registration/view/$id"));
            return;
        }
        # we need to search again with the new type
        lodge($self, $c, $id);
        # ??? another way of calling? with same params???
        return;
    }

    my $newnote = cf_expand($c, $c->request->params->{confnote});
    #
    # settle on exactly which house we're using.
    #
    my ($house_id) = $c->request->params->{house_id};
    my ($force_house) = trim($c->request->params->{force_house});
    if (! ($house_id || $force_house) && $reg->confnote() ne $newnote) {
        #
        # no new house - but they did modify the conf note
        #
        $reg->update({
            confnote    => $newnote,
            letter_sent => '',
        });
        _check_spelling($c, $newnote);
        $c->response->redirect($c->uri_for("/registration/view/$id"));
        return;
    }
    my $house;
    if ($force_house) {
        ($house) = model($c, 'House')->search({
            name => $force_house,
        });
        if (! $house) {
            error($c,
                "Unknown house name: $force_house",
                "registration/error.tt2",
            );
            return;
        }
        $house_id = $house->id;     # override
    }
    else {
        ($house) = model($c, 'House')->find($house_id);
    }
    if (! $house_id) {
        # no house was chosen - perhaps no room in the inn
        $c->response->redirect($c->uri_for("/registration/view/$id"));
        return;
    }

    my $sdate  = $reg->date_start;
    my $edate1 = (date($reg->date_end) - 1)->as_d8();
    my $person = $reg->person();
    my $psex = $person->sex;

    my $program = $reg->program();
    my $note = $person->last()
               . ", " . $person->first()
               . " in " . $program->name()
               ;

    #
    # if we forced a request for a triple into a double
    # we can't set curmax in the config record to 3 - max is 2.
    #
    # what about forcing a 3rd person into
    # a double that is a resized triple?
    # that should reset curmax to 3.  see ** below.
    #
    # lastly (hopefully) we can't force too
    # many people into a room.  everyone must
    # have a bed.  this requires looking ahead.
    # except for tents, that is!!
    # furthermore, you can't force into a space reserved
    # for a rental.
    # so weird and so complicated.   jeez.
    #
    # if kids in this registration then we must set curmax = cur.
    # this will effectively resize the room so no one else
    # will be put there.
    #
    my $house_max = $house->max;
    my $cmax = type_max($reg->h_type);

    if ($cmax > $house_max) {
        $cmax = $house_max;
    }
    if ($force_house) {
        # we need to verify that this forced house
        # is not plum full on some day.
        # or that it is reserved for a rental on one of the days.
        #
        my @cf = model($c, 'Config')->search({
            house_id => $house_id,
            the_date => { 'between' => [ $sdate, $edate1 ] },
            cur      => $house_max,
        });
            # tents are the exception - but you (or the user) need to force it.
        if (@cf && !$house->tent()) {
            error($c,
                "Sorry, no beds left in $force_house"
                     . " on " . date($cf[0]->the_date())
                     . ".",
                "registration/error.tt2",
            );
            return;
        }
        my @rental_cf = model($c, 'Config')->search({
            house_id => $house_id,
            the_date => { 'between' => [ $sdate, $edate1 ] },
            sex      => 'R',
        });
        if (@rental_cf) {
            error($c,
                "Sorry, $force_house is reserved for a rental on "
                    . date($rental_cf[0]->the_date())
                    . ".",
                "registration/error.tt2",
            );
            return;
        }
    }
    #
    # we have passed all the hurdles.
    #
    my @note_opt = ();
    if ($newnote && (!$reg->confnote() || $reg->confnote() ne $newnote)) {
        _check_spelling($c, $newnote);
        @note_opt = (
            confnote    => $newnote,
            letter_sent => '',
        );
    }
    $reg->update({
        house_id => $house_id,
        h_name   => '',
        @note_opt,
    });
    _reg_hist($c, $id, 
        ($force_house? "FORCE ": "")
        . "Lodged as $string{$new_htype} in $house_name_of{$house_id}.");
    my $kids = $reg->kids;
    for my $cf (model($c, 'Config')->search({
                    house_id => $house_id,
                    the_date => { 'between' => [ $sdate, $edate1 ] }
                })
    ) {
        my $csex = $cf->sex;        # csex is the sex of the config record
                                    # psex is the person's sex
        if ($cmax < $cf->cur + 1) {
            $cmax = $house_max;     # note **
        }
        if ($kids) {
            $cmax = 1;      # cur _will_ be 1
        }
        $cf->update({
            curmax     => $cmax,
            cur        => $cf->cur + 1,
            sex        => ((   $csex eq 'U'
                            || $csex eq 'B'
                            || $csex eq $psex  )? $psex
                           :$new_htype !~ m{dbl}? $csex
                           :                      'X'
                          ),
                            # the above middle condition
                            # is for forcing a male into
                            # a female dormitory.  It's still
                            # female dorm, yes?  The force is
                            # required.  Oh, the complexity!
            program_id => $reg->program_id(),
            rental_id  => 0,
        });
        if ($string{housing_log}) {
            hlog($c,
                 $house_name_of{$house_id}, $cf->the_date(),
                 "lodge",
                 $house_id, $cmax, $cf->cur(), $cf->sex(),
                 $reg->program_id(), 0,
                 $note,
            );
        }
    }
    my ($alert, $who) = (0, '');
    if ($string{house_alert} =~ m{~$house_name_of{$house_id}=([^~]+)~}ms) {
        $alert = 1;
        $who = $1;
    }
    check_makeup_new($c, $house_id, $sdate);
    $c->response->redirect($c->uri_for("/registration/view/$id/$alert/$who"));
}

#
# almost the same as lodge - except we
# clear the prior house assignment first.
#
sub relodge : Local {
    my ($self, $c, $id) = @_;
    my $reg = model($c, 'Registration')->find($id);
    stash($c, reg => $reg);
    if ($reg->house_id()) {
        my $house = $reg->house;
        # the user may have vacated, then chosen "Back"
        # and tried to vacate again.  so we check that there
        # is still a house.
        #
        stash($c, message1 => "Vacated " . $house->name . ".");
                                    # see lodge.tt2 
        _vacate($c, $reg);
    }
    lodge($self, $c, $id);
}

#
# restore/clear/undo/decrement the config records for the registration
#
sub _vacate {
    my ($c, $reg) = @_;

    my $sdate  = $reg->date_start;
    my $edate1 = (date($reg->date_end) - 1)->as_d8();
    my $house_id = $reg->house_id;
    my $hmax = $reg->house->max;
    my $person = $reg->person();
    my $note = $person->last()
               . ", " . $person->first()
               . " in " . $reg->program->name()
               ;
    for my $cf (model($c, 'Config')->search({
                    house_id => $house_id,
                    the_date => { 'between' => [ $sdate, $edate1 ] }
                })
    ) {
        # if we're back to empty.
        # set curmax and sex back
        #
        # if we're back to one
        #   find out the gender of the remaining person.
        #   VERY tricky, indeed.
        #   It may have been a dormitory where we had forced
        #   a man.   And then all the women left.
        #
        # and don't undo the program id, right?
        # well, if there is no one left in the room
        # we might as well set the program id and rental_id to 0.
        #
        # if we're not back to one should we see
        # if all involved are of the same sex?  nah.
        # let's leave a flaw in this - like Islamic art.
        #
        my @opts = ();
        if ($cf->cur() == 1) {
            push @opts,
                 curmax     => $hmax,
                 sex        => 'U',
                 program_id => 0,
                 rental_id  => 0,
                 ;
        }
        if ($cf->cur() == 2) {
            my $the_date = $cf->the_date;
            my @reg = model($c, 'Registration')->search({
                house_id   => $house_id,
                date_start => { '<=', $the_date },
                date_end   => { '>',  $the_date },
                id         => { '!=', $reg->id  },      # not the current reg
            });
            if (@reg == 1) {
                push @opts, sex => $reg[0]->person->sex;
            }
            else {
                my @blocks = model($c, 'Block')->search({
                    house_id => $house_id,
                    sdate => { '<=', $the_date },
                    edate => { '>',  $the_date },
                });
                if (@blocks) {
                    push @opts, sex => 'B';
                }
                else {
                    $c->log->info("Inconsistent config records??? "
                                . " $#reg and house id = "
                                . $cf->house_id
                                . " and the date = $the_date");
                }
            }
        }
        $cf->update({
            cur => $cf->cur() - 1,
            @opts,
        });
        if ($string{housing_log}) {
            hlog($c,
                 $house_name_of{$house_id}, $cf->the_date(),
                 "vacate",
                 $house_id, $cf->curmax(), $cf->cur(), $cf->sex(),
                 $cf->program_id(), $cf->rental_id(),
                 $note,
            );
        }
    }
    $reg->update({
        house_id => 0,
    });
    _reg_hist($c, $reg->id(), "Vacated $house_name_of{$house_id}.");

    check_makeup_vacate($c, $house_id, $sdate);
}

#
# patterns for matching people and/or for programs
# are optionally provided.
#
# this is a multi-way search depending on the parameters:
#
# - registrations in the current program
# - registrations in several programs
# - programs
#
sub seek : Local {
    my ($self, $c, $prog_id, $reg_id) = @_;

    my $today_d8 = tt_today($c)->as_d8();
    my $reg_pat = $c->request->params->{reg_pat} || "";
    my $oreg_pat = $reg_pat;
    $reg_pat =~ s{\*}{%}g if $reg_pat;
    $reg_pat = trim($reg_pat);
    my ($pref_last, $pref_first);
    if ($reg_pat =~ m{(\S+)\s+(\S+)}) {
        ($pref_last, $pref_first) = ($1, $2);
    }
    else {
        $pref_last = $reg_pat;
        $pref_first = "";
    }
    my @name_match = ();
    if ($pref_last) {
        push @name_match, 'person.last' => { like => "$pref_last%"  };
    }
    if ($pref_first) {
        push @name_match, 'person.first' => { like => "$pref_first%" };
    }
    my @prog_match = ();
    my $prog_pat = $c->request->params->{prog_pat};
    my $oprog_pat = $prog_pat;
    $prog_pat =~ s{\*}{%}g if $prog_pat;
    if (empty($prog_pat)) {
        push @prog_match, program_id => $prog_id,
    }
    else {
        push @prog_match, 'program.name'  => { 'like' => "$prog_pat%" },
                          'program.edate' => { '>=' => $today_d8      },
    }
    if (! @name_match) {
        # if no prog match either then just stay where you are/were.
        # they must have hit Search (or Return) by mistake
        if (empty($prog_pat)) {
            $c->response->redirect($c->uri_for("/registration/view/$reg_id"));
            return;
        }
        # just a program match
        # and if only one program matches
        # go to the first alphabetic person
        #
        my (@progs) = model($c, 'Program')->search(
            {
                name  => { 'like' => "$prog_pat%" }, 
                edate => { '>='   => $today_d8    },
            },
            {
                order_by => 'sdate',
            },
        );
        if (@progs == 1) {
            first_reg(undef, $c, $progs[0]->id());
            return;
        }
        elsif (@progs == 0) {
            stash($c,
                message  => "No match.",
                reg_pat  => $oreg_pat,
                prog_pat => $oprog_pat,
            );
            view($self, $c, $reg_id);
            return;
        }

        # we have some matching programs.
        my @files = <$rst/online/*>;
        stash($c,
            programs => \@progs,
            online   => scalar(@files),
            pr_pat   => "",
            template => "program/list.tt2",
        );
        return;
    }
    my @regs = model($c, 'Registration')->search(
        {
            @prog_match,
            @name_match,
            # date_start => { '>=' => $today_d8 },
            # had this condition but then we couldn't find people
            # in the current program because their date_start
            # was < today.
        },
        {
            join     => [qw/ person program /],
            order_by => [qw/ person.last person.first me.date_start /],
            prefetch => [qw/ person /],
        }
    );
    if (@regs == 1) {
        # we already have it... so no need to get again????
        $c->response->redirect($c->uri_for("/registration/view/"
                                           . $regs[0]->id()));
    }
    elsif (@regs == 0) {
        # no regs - stay where you are/were. - with a message
        stash($c,
            message  => "No match.",
            reg_pat  => $oreg_pat,
            prog_pat => $oprog_pat,
        );
        view($self, $c, $reg_id);
        return;
    }
    else {
        # are all the registrations in the same program?
        my $multiple = 0;
        if (empty($prog_pat)) {
            stash($c, program => model($c, 'Program')->find($prog_id));
        }
        else {
            my %p_ids;
            for my $r (@regs) {
                $p_ids{$r->program_id()} = 1; 
            }
            my $nprogs = keys %p_ids;
            if ($nprogs == 1) {
                my ($only_prog_id) = keys %p_ids;
                my $pr = model($c,'Program')->find($only_prog_id);
                stash($c, program => $pr);
            }
            else {
                stash($c, multiple_progs => 1);
                $multiple = 1;
            }
        }
        my @files = <$rst/online/*>;
        stash($c,
            online     => scalar(@files),
            pat        => $oreg_pat,
            regs       => _reg_table($c, \@regs, multiple => $multiple),
            other_sort => "list_reg_post",
            template   => "registration/list_reg.tt2",
            other_sort_name => "By Postmark",
        );
    }
}

#
# via an AJAX call on the daily picture.
# who is in the room?
#
sub who_is_there : Local {
    my ($self, $c, $sex, $house_id, $the_date) = @_;

    my $mmi_admin = $c->check_user_roles('mmi_admin');
    my $prog_staff = $c->check_user_roles('prog_staff');

    # the sex parameter tells us whether
    # this house is booked to a rental or to registrants in programs.
    #
    if ($sex eq 'R') {
        # it is a rental
        # find a booking_rental with house $house_id on $the_date
        my (@rb) = model($c, 'RentalBooking')->search(
            {
                house_id   => $house_id,
                date_start => { '<=', $the_date },
                date_end   => { '>=', $the_date },
                    # [] not [) given the design of rental_booking.
                    # registration bookings are different
            },
            {
                join     => [qw/ rental house /],
                prefetch => [qw/ rental house /],
            }
        );
        my $rb = $rb[0];    # should only be 1
        $c->res->output(
            "<center>"
            . $rb->house->name()
            . "</center>"
            . "<p><table cellpadding=2>"
            . "<tr><td><a target=happening class=pr_links href="
            . $c->uri_for("/rental/view/" . $rb->rental_id() . "/1")
            . ">"
            . $rb->rental->name() . " - "
            . $string{$rb->h_type()}
            . "</a></td></tr>"
            . "</table>"
        );
        return;
    }
    #
    # it must be one or more registrations - or blocks
    #
    # the end date is strictly less because
    # we reserve housing up to the night before their end date.
    #
    # so:
    #      date_start <= $the_date < date_end
    #
    my @regs = model($c, 'Registration')->search(
        {
            house_id   => $house_id,
            date_start => { '<=', $the_date },
            date_end   => { '>',  $the_date },
        },
        {
            join     => [qw/ person program /],
            prefetch => [qw/ person program /],
            order_by => [qw/ person.last person.first me.date_start /],
        }
    );
    my @blocks = model($c, 'Block')->search({
        house_id   => $house_id,
        sdate => { '<=', $the_date },
        edate => { '>',  $the_date },
        allocated => 'yes',
    });
    if (! @regs && ! @blocks) {
        $c->res->output("Unknown");     # shouldn't happen
        return;
    }
    my $reg_names = "";
    for my $r (@regs) {
        my $rid = $r->id();
        my $pr = $r->program();
        my $mmi = $pr->school()->mmi();
        my $name = $r->person->last() . ", " . $r->person->first();
        my $pr_name = $pr->name();
        my $relodge = "";
        if ((!$mmi && $prog_staff) || ($mmi && $mmi_admin)) {
            $name = "<a target=happening href="
                  . $c->uri_for("/registration/view/$rid")
                  . ">"
                  . $name
                  . "</a>"
                  ;
            # a poor man's drag and drop relodging
            # they didn't like it - too iconically cryptic
            #
            #$relodge = "<td width=30 align=center><a target=happening href="
            #         . $c->uri_for("/registration/relodge/$rid")
            #         . qq# title="ReLodge!">#
            #         . "<img src=/static/images/move_arrow.gif border=0>"
            #         . "</a></td>"
            #         ;
            $pr_name = "<a target=happening href="
                     . $c->uri_for("/program/view/")
                     . $pr->id()
                     . ">"
                     . $pr_name
                     . "</a>"
                     ;
        }
        $reg_names .= "<tr>"
                   . "<td>"
                   . $name
                   . _get_kids($r->kids())
                   . "</td>"
                   . "<td>$pr_name</td>"
                   #. $relodge
                   . "</tr>";
    }
    # escaping single quotes not needed?
    #$reg_names =~ s{'}{\\'}g;       # for O'Dwyer etc.
                                # can't use &apos; :( why?
    for my $b (@blocks) {
        my $nbeds = $b->nbeds();
        my $pl = ($nbeds == 1)? "": "s";
        my $reason = $b->reason();
        if ($reason =~ m{meeting\s+place\s+for}i) {
            $reg_names .= "<tr><td>"
                       .  "<a target=happening href=/block/view/"
                       .  $b->id()
                       .  ">$reason</a>"
                       .  "</td></tr>"
                       ;
        }
        else {
            $reg_names .= "<tr><td>"
                       .  "<a target=happening href=/block/view/"
                       .  $b->id()
                       .  ">$nbeds bed$pl blocked</a></td><td>"
                       .  $reason
                       .  "</td></tr>"
                       ;
        }
    }
    $c->res->output("<center>"
                   . $house_name_of{$house_id}
                   . "</center>"
                   . "<p><table cellpadding=2>$reg_names</table>"
                   );
}

sub _get_kids {
    my ($s) = @_;
    if (! defined $s) {
        return "";
    }
    my @ages = $s =~ m{(\d+)}g;
    if (!@ages) {
        return "";
    }
    elsif (@ages == 1) {
        return " with child";
    }
    else {
        return " with children";
    }
}

#
# view the first (alphabetically) registration for this program
# OR, if there are no registrations, say so in an error screen.
#
sub first_reg : Local {
    my ($self, $c, $program_id) = @_;

    my ($reg) = model($c, 'Registration')->search(
        {
            program_id => $program_id,
        },
        {
            rows     => 1,
            join     => [qw/ person /],
            order_by => [qw/ person.last person.first /],
            prefetch => [qw/ person /],
        }
    );
    if ($reg) {
        stash($c, reg => $reg);
        _view($c, $reg);
    }
    else {
        $c->response->redirect(
            $c->uri_for("/registration/list_reg_name/$program_id")
        );
    }
}

# get the stash, put the values in a form in a template
# let the user alter the values
# the form action is ceu_do
sub ceu : Local {
    my ($self, $c, $reg_id) = @_;

    my $reg = model($c, 'Registration')->find($reg_id);
    my $stash = ceu_license_stash($reg);
    stash($c,
        %$stash,
        template => 'registration/ceu.tt2',
    );
}

sub ceu_do : Local {
    my ($self, $c) = @_;
    my $html = show_ceu_license($c->request->params);
    $c->res->output($html);
}

my $npeople;
my @people;
my @star;
my $containing;
my $email_all;

# a side effect is to append any email $to mail_all
sub _person_data {
    my ($i) = @_;

    if ($i >= $npeople) {
        return "";
    }
    my $p = $people[$i];
    my $email = $p->email;
    my $email_to = "";
    $email_to = "<a href='mailto:$email'>$email</a>" if $email;
    if ($containing eq 'all') {
        $email_all .= $email . ", " if $email;
        return "<b>" . $p->last . ", " . $p->first . "</b>"
             . ($star[$i]? '<span class=extended> *</span>'
                :          '')
             . "<br>"
             . $p->addr1 . "<br>"
             . ($p->addr2? $p->addr2 . "<br>": "")
             . $p->city . ", " . $p->st_prov . " " . $p->zip_post . "<br>"
             . ($p->country? $p->country . "<br>": "")
             . ($p->tel_home? $p->tel_home . " home<br>": "")
             . ($p->tel_work? $p->tel_work . " work<br>": "")
             . ($p->tel_cell? $p->tel_cell . " cell<br>": "")
             . ($email_to   ? $email_to                 : "")
             . "<p>"
             ;
    }
    elsif ($containing eq 'name') {
        return $p->last . ", " . $p->first
             . ($star[$i]? '<span class=extended> *</span>'
                :          '')
             . "<br>";
    }
    elsif ($containing eq 'email') {
        # if no email return nothing.
        # the row gets collapsed, right???.
        #
        $email_all .= $email . ", " if $email;
        return $email_to? ($email_to . "<br>"): "";
    }
}

sub name_addr : Local {
    my ($self, $c, $prog_id) = @_;
    
    my $program = model($c, 'Program')->find($prog_id);
    stash($c,
        program  => $program,
        email    => $program->email_nameaddr(),
        template => "registration/pre_name_addr.tt2",
    );
}

sub name_addr_do : Local {
    my ($self, $c, $prog_id) = @_;

    my $program = model($c, 'Program')->find($prog_id);
    my $edate = $program->edate();

    my $p_order = $c->request->params->{order};
    my $order = ($p_order eq 'name')? [qw/ person.last person.first /]
                :                     [qw/ date_postmark time_postmark /];
    my $including = $c->request->params->{including} || "";
    $containing = $c->request->params->{containing};
    my $format = $c->request->params->{format};
    my @cond = ();
    if ($including eq 'normal') {
        @cond = (
            date_end => { '<=' => $edate },
        );
    }
    elsif ($including eq 'extended') {
        @cond = (
            date_end => { '>' => $edate },
        );
    }
    my (@regs) = model($c, 'Registration')->search(
        {
            program_id        => $prog_id,
            cancelled         => { '!=' => 'yes' },
            # inactive is a mailing list attribute - not appropriate
            # to include here...
            #'person.inactive' => { '!=' => 'yes' },
            @cond,
        },
        {
            join     => [qw/ person /],
            order_by => $order,
            prefetch => [qw/ person /],   
        }
    );
    # ensure that each person has a non-blank email address
    if ($containing eq 'email') {
        @regs = grep { $_->person->email } @regs;
    }
    #
    # eliminate duplicates (via allow_dup_regs like AVI or PRs)
    # not sure how to do the 'distinct' thing above in the SQL...
    #
    my %seen;
    @regs = grep {
                my $per = $_->person();
                ! $seen{ $per->first() . $per->last() }++;
            }
            @regs;
    @star = ();     # see above - _person_data()
    if ($including eq 'both') {
        @star = map {
                    ($_->date_end() > $edate)? 1
                    :                          0
                }
                @regs;
    }
    @people = map { $_->person } @regs;     # not my - see above
    $npeople = @people;

    my $info_rows;
    $email_all = "";     # not my
    my $html = "";
    my $email = "";
    for my $em (keys %{$c->request->params()}) {
        if ($em =~ m{^email}) {
            $email .= $c->request->params->{$em} . ", ";
        }
    }
    my $cc = $c->request->params->{cc};
    if ($cc) {
        $email .= $cc;
    }
    if ($format eq 'csv') {
        # generate participant.csv given 'containing' and @people
        my $out;
        if ($email) {
            open $out, '>', \$html;
        }
        else {
            open $out, '>', "root/static/participant.csv";
        }
        for my $p (@people) {
            if ($containing eq 'name') {
                print {$out} join ',',
                             map { s/"//g; qq{"$_"} }
                             $p->first,
                             $p->last
                             ;
            }
            elsif ($containing eq 'email') {
                print {$out} $p->email;
            }
            else {
                print {$out} join ',',
                             map { s/"//g; qq{"$_"} }
                             $p->first,
                             $p->last,
                             $p->addr1,
                             $p->addr2,
                             $p->city,
                             $p->st_prov,
                             $p->zip_post,
                             $p->country,
                             $p->tel_home,
                             $p->tel_work,
                             $p->tel_cell,
                             $p->email,
                             ;
            }
            print {$out} "\n";
        }
        close $out;
    }
    else {
        if ($format eq 'linear') {
            $info_rows = "";
            for my $i (0 .. $#people) {
                my $s = _person_data($i);
                $info_rows .= "$s\n";
            }
        }
        else {
            # make the 3 across table - too tricky to do
            # in the template.  we want it sorted by last name
            # going down the column.
            #
            my $n = ceil($npeople/3);   # length of 1st, 2nd column
            $info_rows = "<table cellpadding=3>\n";
            for my $i (0 .. $n-1) {
                $info_rows .= "<tr>";
                for my $offset (0, $n, 2*$n) {
                    my $s = _person_data($i+$offset);
                    $info_rows .= "<td valign=top>$s</td>";
                }
                $info_rows .= "</tr>\n";
            }
            $info_rows .= "</table>\n";
        }
        my $tt = Template->new({
            INCLUDE_PATH => 'root/src',
            INTERPOLATE  => 1,
            EVAL_PERL    => 0,
        }) or die Template->error();
        my $stash = {
            program   => $program,
            rows      => $info_rows,
            email_all => $email_all,
            type      => ($including eq 'both'    ? ''
                         :$including eq 'normal'  ? 'Normal '
                         :$including eq 'extended'? 'Extended '
                         :                          ''),
        };
        $tt->process(
            "registration/name_addr.tt2",   # template
            $stash,               # variables
            \$html,               # output
        ) or die $tt->error();
    }
    if ($email) {
        $email =~ s{, $}{};     # chop last comma
        email_letter($c,
               to         => $email,
               from       => "$string{from_title} <$string{from}>",
               subject    => "Participant List for "
                            . $program->name
                            . " from "
                            . $program->dates,
               html       => $html, 
               ctype      => $format eq 'csv'? 'text/csv': 'text/html',
        );
        my $email_entity = $email;
        $email_entity =~ s{<([^>]*)>}{&lt;$1&gt;}g;
        stash($c,
            program  => $program,
            email    => $email_entity,
            template => "registration/name_addr_conf.tt2",
        );
    }
    else {
        if ($format eq 'csv') {
            $c->response->redirect($c->uri_for("/static/participant.csv"));
        }
        else {
            $c->res->output($html);
        }
    }
}

#
#
#
sub tally : Local {
    my ($self, $c, $prog_id) = @_;

    my $pr = model($c, 'Program')->find($prog_id);
    my @regs = model($c, 'Registration')->search(
        {
            program_id => $prog_id,
        },
        {
            join     => [qw/ person /],
            prefetch => [qw/ person /],
        }
    );
    my $registered = 0;
    my $cancelled  = 0;
    my $no_shows   = 0;

    my $males      = 0;
    my $females    = 0;

    my $adults     = 0;
    my $kids       = 0;

    # Payments
    my $deposit    = 0;
    my $can_deposit = 0;
    my $can_payment = 0;
    my $payment    = 0;
    my $balance    = 0;

    # Charges
    my @charges_for = (0) x 8;

    my $credit     = 0;

    my %seen;
    REG:
    for my $r (@regs) {
        if (! $pr->school()->mmi()) {       # MMC
            for my $rp ($r->payments()) {
                my $what   = $rp->what;
                my $amount = $rp->amount();
                if ($what =~ m{deposit}i) {
                    if ($r->cancelled()) {
                        $can_deposit += $amount;
                    }
                    else {
                        $deposit += $amount;
                    }
                }
                elsif ($what =~ m{payment}i) {
                    if ($r->cancelled()) {
                        $can_payment += $amount;
                    }
                    else {
                        $payment += $amount;
                    }
                }
                else {
                    # ??? what else?
                }
            }
        }
        else {      # MMI
            for my $rp ($r->mmi_payments()) {
                my $amount = $rp->amount();
                my $cancelled = $r->cancelled();
                if ($rp->note() =~ m{deposit}xmsi) {
                    if ($cancelled) {
                        $can_deposit += $amount;
                    }
                    else {
                        $deposit += $amount;
                    }
                }
                else {
                    if ($cancelled) {
                        $can_payment += $amount;
                    }
                    else {
                        $payment += $amount;
                    }
                }
            }
        }
        if (my ($credit_rec) = model($c, 'Credit')->search({
                person_id => $r->person_id(),
                reg_id    => $r->id(),
            })
        ) {
            $credit += $credit_rec->amount();
        }
        # charges
        #
        # cancellations don't tally charges or the balance at all.
        # right?
        #
        if (! $r->cancelled()) {
            for my $rc ($r->charges()) {
                $charges_for[$rc->type()] += $rc->amount();
            }
            $balance += $r->balance();
        }

        # have we seen this person before?
        # allow_dup_regs and AVI type programs will have dup regs.
        #
        my $per = $r->person();
        if ($seen{$per->first() . $per->last()}++) {
            next REG;
        }
        ++$registered;
        if ($r->cancelled()) {
            ++$cancelled;
            next REG;
        }
        if (! $r->arrived) {
            ++$no_shows;
            next REG;
        }
        ++$adults;
        if ($r->person->sex() eq 'F') {
            ++$females;
        }
        else {
            ++$males;
        }
        if (my $k = $r->kids()) {
            my @ages = $k =~ m{(\d+)}g;
            $kids += @ages;
        }
    }
    my $tot_charge = 0;
    for my $a (@charges_for) {
        $tot_charge += $a;
        $a = commify($a);
    }
    stash($c,
        program     => $pr,
        id          => $prog_id,
        registered  => $registered,
        cancelled   => $cancelled,
        no_shows    => $no_shows,
        males       => $males,
        females     => $females,
        adults      => $adults,
        kids        => $kids,

        charge_amount => \@charges_for,
        charge_label  => \@charge_type,
        tot_charge    => commify($tot_charge),

        deposit     => commify($deposit),
        payment     => commify($payment),
        balance     => commify($balance),
        tot_inc     => commify($deposit + $payment + $balance),

        can_deposit => commify($can_deposit),
        can_payment => commify($can_payment),
        credit      => commify($credit),
        net_cancel  => commify($can_deposit + $can_payment - $credit), 
        template    => "registration/tally.tt2",
    );
}

sub conf_notes : Local {
    my ($self, $c) = @_;
    my @notes = model($c, 'ConfNote')->search(undef, { order_by => 'abbr' });
    my $html = <<"EOH";
<center>
<h2>Quick Confirmation Notes</h2>
</center>
Place the abbreviation alone on the line and it will be expanded.
<p>
<table cellpadding=3>
<tr><th align=right>Abbr</th><th align=left>Expansion</th></tr>
EOH
    for my $n (@notes) {
        $html .= "<tr><th align=right valign=top>"
              .  $n->abbr()
              .  "</th><td>"
              .  $n->expansion()
              .  "</td></tr>\n";
    }
    $html .= "</table>\n";
    $c->res->output($html);
    return;
}

#
# for the given MMI program automatically register
# everyone who is in a long term program that is concurrent (overlaps)
# with the given program.   Offer the list of long term programs
# and let the user choose which to do the import on.
#
sub mmi_import : Local {
    my ($self, $c, $program_id) = @_;

    my $pr = model($c, 'Program')->find($program_id);
    if (empty($pr->glnum())) {
        error($c,
            $pr->name() . " does not have a GL Number.  Please fix.",
            "registration/error.tt2",
        );
        return;
    }
    my $sdate = $pr->sdate();
    my @progs = model($c, 'Program')->search({
        'school.mmi'       => 'yes',
        'level.long_term'  => 'yes',
        # should we only accept long term registrants from the same school
        # as the course we are importing into???   No.
        #
        sdate  => { '<=', $sdate },
        edate  => { '>=', $sdate },
    },
    {
        order_by => 'sdate asc, edate asc',
        join     => [qw/ school level /],
    });
    stash($c,
        cur_prog  => $pr,
        long_term_progs => \@progs,
        template  => "registration/mmi_import.tt2",
    );
}

sub mmi_import_do : Local {
    my ($self, $c, $program_id) = @_;

    my $program = model($c, 'Program')->find($program_id);
    my %person_ids = ();
    for my $lt_id (keys %{ $c->request->params() }) {
        $lt_id =~ s{^n}{};
        REG:
        for my $reg (model($c, 'Program')->find($lt_id)->registrations()) {
            next REG if $reg->cancelled();
            $person_ids{$reg->person->id()} = 1;
        }
    }
    my $new_regs = 0;
    IDS:
    for my $person_id (keys %person_ids) {
        my @regs = model($c, 'Registration')->search({
                       person_id  => $person_id,
                       program_id => $program_id,
                   });
        next IDS if @regs;      # already registered
        #
        # register this person.
        # we will house them later...
        #

        # what kind of housing should we initially use for this person?
        #
        # look in their past registrations and take the most recent one.
        # this isn't perfect - perhaps it is now winter and they
        # tented before...
        #
        my @prior_reg
            = grep {
                  $_->h_type() !~ m{unknown|not_needed}
              }
              model($c, 'Registration')->search(
                  { person_id => $person_id        },
                  { order_by  => 'date_start desc' },
              );
        my ($h_type, $pref1, $pref2);
        if (@prior_reg) {
            my $r = $prior_reg[0];
            $h_type = $r->h_type;
            $pref1 = $r->pref1 || $h_type;
            $pref2 = $r->pref2 || $h_type;
        }
        else {
            $h_type = $pref1 = $pref2 = 'dble';
        }
        my $edate = date($program->edate()) + $program->extradays();
        my $person = model($c, 'Person')->find($person_id);
        my ($outstand_str, $ob_alert) = outstanding_balance($c, $person);
        model($c, 'Registration')->create({
            person_id  => $person_id,
            program_id => $program_id,
            house_id   => 0,
            h_type     => $h_type,
            pref1      => $pref1,
            pref2      => $pref2,
            cancelled  => '',    # to be sure
            arrived    => '',    # ditto
            date_start => $program->sdate(),
            date_end   => $edate->as_d8(),
            balance    => 0,
            manual     => '',
            comment    => $outstand_str,
        });
        # finances???
        ++$new_regs;
    }
    if ($new_regs) {
        $program->update({
            reg_count => $program->reg_count() + $new_regs,
        });
    }
    $c->response->redirect(
        $c->uri_for("/registration/list_reg_name/$program_id")
    );
}

sub nonzero : Local {
    my ($self, $c, $program_id) = @_;

    my @regs = model($c, 'Registration')->search(
        {
            program_id => $program_id,
            balance    => { '!=' => 0 },
            cancelled  => { '!=' => 'yes' },
        },
        {
            join     => [qw/ person /],
            prefetch => [qw/ person /],   
            order_by => [qw/ person.last person.first /],
        },
    );
    $c->stash->{program} = model($c, 'Program')->find($program_id);
    $c->stash->{regs} = \@regs;
    $c->stash->{template} = "registration/nonzero.tt2";
}

sub carpool : Local {
    my ($self, $c, $prog_id) = @_;

    my $program = model($c, 'Program')->find($prog_id);
    my @carpoolers = model($c, 'Registration')->search(
        {
            program_id => $prog_id,
            carpool    => 'yes',
            cancelled  => { '!=' => 'yes' },
        },
        {
            join     => [ qw/ person / ],
            prefetch => [ qw/ person / ],
            order_by => [ qw/ person.zip_post / ],
        }
    );
    stash($c,
        program    => $program,
        carpoolers => \@carpoolers,
        template   => 'registration/carpool.tt2',
        cur_time   => scalar(localtime),
    );
}

#
# find the alphabetically first registration in the
# current Personal Retreat program.
#
sub pr : Local {
    my ($self, $c) = @_;

    my @prog = model($c, 'Program')->search({
        name  => { 'like' => '%personal%retreat%' },
        edate => { '>='   => today()->as_d8() },
    });
    if (! @prog) {
        $c->response->redirect($c->uri_for("/program/list"));
        return;
    }
    my $pr_id = $prog[0]->id();
    my ($reg) = model($c, 'Registration')->search(
        {
            program_id => $pr_id,
        },
        {
            rows     => 1,
            join     => [qw/ person /],
            order_by => [qw/ person.last person.first/],
            prefetch => [qw/ person /],
        }
    );
    if ($reg) {
        stash($c, reg => $reg);
        _view($c, $reg);
    }
    else {
        $c->response->redirect($c->uri_for("/program/view/$pr_id"));
    }
}

sub view_adj : Local {
    my ($self, $c, $prog_id, $reg_id, $last, $first, $dir) = @_;

    my $relation = ($dir eq 'next')? '>'  : '<';
    my $ord      = ($dir eq 'next')? 'asc': 'desc';
    #
    # e.g. for previous registration:
    #
    # select *
    # from registration r, people p
    # where program_id = 2002 and 
    # (p.last < 'Blum' or (p.last = 'Blum' and p.first < 'Gloria'))
    # and p.id = r.person_id
    # order by p.last desc, p.first desc limit 1;
    #
    # This worries about two people with the same last name.
    # Yes, but with one person registered twice (or more) for a PR it fails.
    #
    # Need to sort by registration.id (like the AllRegs list is now)
    # and include that in the condition.
    # Much more complex than one at first imagines!
    #
    my @regs = model($c, 'Registration')->search(
        {
            program_id => $prog_id,
            -or => [
                'person.last' => { $relation => $last },
                -and => [
                    'person.last'  => $last,
                    'person.first' => { $relation => $first },
                ],
                -and => [
                    'person.last'  => $last,
                    'person.first' => $first,
                    'me.id'        => { $relation => $reg_id },
                ],
            ],
        },
        {
            rows     => 1,
            join     => [qw/ person /],
            order_by => [
                            "person.last  $ord",
                            "person.first $ord",
                            "me.id        $ord",
                        ],
            prefetch => [qw/ person /],
        }
    );
    if (@regs) {
        $c->response->redirect($c->uri_for("/registration/view/" .
                               $regs[0]->id()));
    }
    else {
        # likely BOF beginning of file or EOF.
        $c->response->redirect($c->uri_for("/registration/view/$reg_id"));
    }
}

sub automatic : Local {
    my ($self, $c, $reg_id, $mode) = @_;

    my $reg = model($c, 'Registration')->find($reg_id);
    $reg->update({
        manual => ($mode? 'yes': ''),
    });
    # if moving to manual convert automatic charges to manual.
    #
    if ($mode) {
        model($c, 'RegCharge')->search({
            reg_id    => $reg_id,
            automatic => 'yes',
        })->update({
            automatic => '',
        });
    }

    my @who_now = get_now($c);
    push @who_now, reg_id => $reg_id;

    _compute($c, $reg, 0, @who_now);

    $c->response->redirect($c->uri_for("/registration/view/$reg_id"));
}

sub edit_dollar : Local {
    my ($self, $c, $reg_id) = @_;

    my $reg = model($c, 'Registration')->find($reg_id);
    my $auto_total = 0;
    for my $ch ($reg->charges()) {
        if ($ch->automatic()) {
            $auto_total += $ch->amount();
        }
    }
    stash($c,
        manual_charges => [
            model($c, 'RegCharge')->search({
                reg_id => $reg_id,
                automatic => '',
            })
        ],
        charge_label => \@charge_type,
        auto_total => $auto_total,
        reg => $reg,
        template => 'registration/edit_dollar.tt2',
    );
}

sub charge_delete : Local {
    my ($self, $c, $reg_id, $ch_id, $from) = @_;

    my ($reg) = model($c, 'Registration')->find($reg_id);
    my ($charge) = model($c, 'RegCharge')->find($ch_id);
    stash($c,
        reg      => $reg,
        charge   => $charge,
        template => 'registration/reg_charge_del.tt2',
    );
}

sub charge_delete_do : Local {
    my ($self, $c, $reg_id, $ch_id, $from) = @_;

    my $reg = model($c, 'Registration')->find($reg_id);
    my ($charge) = model($c, 'RegCharge')->find($ch_id);
    if ($c->request->params->{yes}) {
        my $what = 'Deleted charge of $'
                 . commify($charge->amount)
                 . " - "
                 . $charge_type[$charge->type]
                 . ($charge->what? ' - ' . $charge->what: '')
                 ;
        $charge->delete();
        my @who_now = get_now($c);
        model($c, 'RegHistory')->create({
            reg_id   => $reg_id,
            @who_now,
            what    => $what,
        });
        $reg->calc_balance();
    }
    if (defined $from && $from eq 'edit_dollar') {
        $c->response->redirect(
            $c->uri_for("/registration/edit_dollar/$reg_id")
        );
    }
    else {
        $c->response->redirect($c->uri_for("/registration/view/$reg_id"));
    }
}

sub payment_delete : Local {
    my ($self, $c, $reg_id, $pay_id) = @_;

    my $reg = model($c, 'Registration')->find($reg_id);
    my $payment = model($c, 'RegPayment')->find($pay_id);
    stash($c,
        reg => $reg,
        payment => $payment,
        template => 'registration/reg_pay_del.tt2',
    );
}

sub payment_delete_do : Local {
    my ($self, $c, $reg_id, $pay_id, $from) = @_;

    my $reg = model($c, 'Registration')->find($reg_id);
    if ($c->request->params->{yes}) {
        my $payment = model($c, 'RegPayment')->find($pay_id);
        $payment->delete();
        $reg->calc_balance();
        _reg_hist($c, $reg_id, "Deleted payment of \$"
                               . $payment->amount()
                               . "."
                               );
    }
    if (defined $from && $from eq 'edit_dollar') {
        $c->response->redirect(
            $c->uri_for("/registration/edit_dollar/$reg_id")
        );
    }
    else {
        $c->response->redirect($c->uri_for("/registration/view/$reg_id"));
    }
}

sub payment_update : Local {
    my ($self, $c, $pay_id, $from) = @_;

    my $pay = model($c, 'RegPayment')->find($pay_id);
    my $type = $pay->type();
    my $type_opts = "";
    for my $t (qw/ D C S O /) {
        $type_opts .= "<option value=$t"
                   .  ($type eq $t? " selected": "")
                   .  ">"
                   .  $string{"payment_$t"}
                   .  "\n";
                   ;
    }
    my $what = $pay->what();
    stash($c,
        from        => $from,
        pay         => $pay,
        type_opts   => $type_opts,
        dep_checked => ($what eq 'Deposit'? " checked": ""),
        pay_checked => ($what eq 'Payment'? " checked": ""),
        template    => "registration/edit_payment.tt2",
    );
}
sub payment_update_do : Local {
    my ($self, $c, $pay_id) = @_;

    my $pay = model($c, 'RegPayment')->find($pay_id);
    my $reg = $pay->registration();
    my $the_dt = trim($c->request->params->{the_date});
    my $dt = date($the_dt);
    if (! $dt) {
        error($c,
            "Illegal date: $the_dt",
            'gen_error.tt2',
        );
        return;
    }
    my $amount = trim($c->request->params->{amount});
    if (invalid_amount($amount)) {
        error($c,
            "Illegal amount: $amount",
            'gen_error.tt2',
        );
        return;
    }
    my $type = $c->request->params->{type};
    my $what = $c->request->params->{what};
    $pay->update({
        the_date => $dt->as_d8(),
        # date changes but time remains the same ??? Okay?
        amount   => $amount,
        type     => $type,
        what     => $what,
    });

    # add reg history record
    _reg_hist($c, $reg->id(), "Updated $string{'payment_' . $type} payment of \$$amount.");

    if ($what eq 'Deposit') {
        # need to update the deposit field in the reg record
        #
        $reg->update({
            deposit => $amount,
        });
    }
    # ??? also update who, when
    $reg->calc_balance();
    if ($c->request->params->{from} eq 'edit_dollar') {
        $c->response->redirect(
            $c->uri_for("/registration/edit_dollar/" . $pay->reg_id())
        );
    }
    else {
        $c->response->redirect(
            $c->uri_for("/registration/view/" . $pay->reg_id())
        );
    }
}
sub charge_update : Local {
    my ($self, $c, $chg_id, $from) = @_;

    my $chg = model($c, 'RegCharge')->find($chg_id);
    stash($c,
        from     => $from,
        chg      => $chg,
        type_opts => charges_and_payments_options($chg->type()),
        template => 'registration/edit_charge.tt2',
    );
}
sub charge_update_do : Local {
    my ($self, $c, $chg_id) = @_;

    my $chg = model($c, 'RegCharge')->find($chg_id);
    my $reg = $chg->registration();
    my $old_amount = $chg->amount();
    my $amount = trim($c->request->params->{amount});
    if (invalid_amount($amount)) {
        error($c,
            "Illegal amount: $amount",
            'gen_error.tt2',
        );
        return;
    }
    my $what = $c->request->params->{what};
    my $type = $c->request->params->{type};
    my @who_now = get_now($c);
    $chg->update({
        amount => $amount,
        type   => $type,
        what   => $c->request->params->{what},
        @who_now,
    });
    $reg->calc_balance();

    $what = " - $what" if $what;
    $amount = commify($amount);
    $old_amount = commify($old_amount);
    model($c, 'RegHistory')->create({
        reg_id    => $chg->reg_id(),
        @who_now,
        what    => "Updated \$$old_amount charge: \$$amount - $charge_type[$type]$what",
    });
    if ($c->request->params->{from} eq 'edit_dollar') {
        $c->response->redirect(
            $c->uri_for("/registration/edit_dollar/" . $chg->reg_id())
        );
    }
    else {
        $c->response->redirect(
            $c->uri_for("/registration/view/" . $chg->reg_id())
        );
    }
}

sub work_study : Local {
    my ($self, $c, $prog_id) = @_;

    my $prog = model($c, 'Program')->find($prog_id);
    my @regs = model($c, 'Registration')->search(
        {
            program_id => $prog_id,
            work_study => 'yes',
            cancelled  => { '!=' => 'yes' },
        },
        {
            join     => [qw/ person /],
            order_by => [qw/ person.first person.last /],
            prefetch => [qw/ person /],   
        }
    );
    stash($c,
        program  => $prog,
        regs     => \@regs,
        template => 'registration/work_study.tt2',
    );
}

sub search : Local {
    my ($self, $c, $prog_id) = @_;

    my $prog = model($c, 'Program')->find($prog_id);
    stash($c,
        program  => $prog,
        template => 'registration/find.tt2',
    );
}

sub search_do : Local {
    my ($self, $c, $prog_id) = @_;

    my $prog = model($c, 'Program')->find($prog_id);
    my $pat = $c->request->params->{pat};
    my @regs = model($c, 'Registration')->search({
        program_id => $prog_id,
        -or => [
            comment  => { 'like' => "%$pat%" },   
            confnote => { 'like' => "%$pat%" },   
        ],
    });
    stash($c,
        pat      => $pat,
        program  => $prog,
        regs     => \@regs,
        template => 'registration/comments.tt2',
    );
}

sub uncancel : Local {
    my ($self, $c, $reg_id) = @_;

    my $reg = model($c, 'Registration')->find($reg_id);

    # unmark cancelled
    $reg->update({
        cancelled => '',
    });

    # was any credit given?
    my ($cr) = model($c, 'Credit')->search({
        reg_id => $reg_id,
    });
    if ($cr) {
        if ($cr->used_reg_id() != 0) {
            # cannot uncancel - the credit has been used.
            error($c,
                "Sorry, cannot uncancel this registration.  The credit was used.",
                "registration/error.tt2",
            );
            return;
        }
        $cr->delete();
    }

    # add one to reg_count in the program
    my $prog_id   = $reg->program_id;
    my $pr = model($c, 'Program')->find($prog_id);
    $pr->update({
        reg_count => \'reg_count + 1',
    });

    # add reg history record
    _reg_hist($c, $reg_id, "UNcancelled");

    # do an update so the free nights, housing, etc can be set again.
    $c->response->redirect($c->uri_for("/registration/update/$reg_id"));
}

#
# mostly for having multiple regs for housing purposes
# but could be called for PRs.
# Dup renamed Aux but we'll keep the sub name.
#
sub duplicate : Local {
    my ($self, $c, $reg_id) = @_;

    my $reg = model($c, 'Registration')->find($reg_id);
    my $pr = $reg->program();
    # ??? verify that allow_dup_regs is set for this program???
    my $p  = $reg->person();

    stash($c,
        deposit       => 0,
        date_postmark => $reg->date_postmark(),
        time_postmark => $reg->time_postmark(),
        dup           => ($pr->PR()? "": "yes"),
    );
    _rest_of_reg($pr, $p, $c, tt_today($c),
                 $reg->pref1(), $reg->pref2(), $reg->cabin_room());
}

sub grab_new : Local {
    my ($self, $c) = @_;
    system("grab wait");
    $c->response->redirect($c->uri_for("/registration/list_online"));
}

sub receipt : Local {
    my ($self, $c, $reg_id, $type) = @_;

    if ($type eq 'print') {
        _send_receipt($c, $reg_id, $type);
    }
    else {
        my $reg = model($c, 'Registration')->find($reg_id);
        stash($c,
            reg      => $reg,
            template => "registration/receipt.tt2",
        );
    }
}
sub email_receipt : Local {
    my ($self, $c, $reg_id) = @_;
    my $email_addrs = $c->request->params->{email_addrs};
    # check addresses?
    _send_receipt($c, $reg_id, 'email', $email_addrs);
}
sub _send_receipt {
    my ($c, $reg_id, $type, $addrs) = @_;
    my $reg = model($c, 'Registration')->find($reg_id);
    my $html = "";
    my $tt = Template->new({
        INTERPOLATE  => 1,
        INCLUDE_PATH => "$rst/templates/letter",
        EVAL_PERL    => 0,
    });
    my @leaders = $reg->program->leaders;
    my $presenter;
    if (@leaders) {
        my $l = $leaders[0];
        my $p = $l->person();
        $presenter = $l->just_first()? $p->first(): $p->name();
    }
    else {
        $presenter = '';
    }
    my $stash = {
        today     => today(),
        reg       => $reg,
        presenter => $presenter,
        print     => $type eq 'print',
    };
    $tt->process(
        "receipt.tt2",  # template
        $stash,         # variables
        \$html,         # output
    ) or die "error in processing template: "
             . $tt->error();
    my $from =
        ($reg->program->school->mmi())?
            'Mount Madonna Institute '
           .'<MMIreservations@mountmadonnainstitute.org>'
        : "$string{from_title} <$string{from}>";
        ;
    if ($type eq 'email') {
        email_letter($c,
            to      => $addrs,
            from    => $from,
            subject => "Receipt for " . $reg->program->title,
            html    => $html, 
        );
    }
    my @who_now = get_now($c);
    model($c, 'RegHistory')->create({
        reg_id   => $reg_id,
        @who_now,
        what    => "Receipt ${type}ed",
    });
    if ($type eq 'print') {
        $c->res->output($html);
    }
    else {
        $c->response->redirect($c->uri_for("/registration/view/$reg_id"));
    }
    return;
}

sub online_history : Local {
    my ($self, $c) = @_;

    my ($sdate, $edate);

    @mess = ();
    %P = %{ $c->request->params() };
    my $key = $P{sort_key} || 'name';
    if ($P{sdate} eq 'week') {
        $sdate = today() - 7;
        $edate = today();
    }
    else {
        my $dt = date($P{sdate});
        if (! $dt) {
            push @mess, "Invalid start date: $P{sdate}";
        }
        else {
            $sdate = $dt;
        }
        if (empty $P{edate}) {
            $edate = today();    
        }
        else {
            $dt = date($P{edate});
            if (! $dt) {
                push @mess, "Invalid end date: $P{edate}";
            }
            else {
                $edate = $dt;
            }
        }
        if (!@mess && $edate < $sdate) {
            push @mess, "End date cannot be before start date";
        }
        if (@mess) {
            error($c,
                join("<br>", @mess),
                "registration/error.tt2",
            );
            return;
        }
    }
    my $y = $sdate->year;
    my $m = $sdate->month;
    my $rsod = "root/static/online_done/";
    my @regs;
    REG_DIR:
    while (1) {
        my $dir = sprintf("$rsod%04d-%02d", $y, $m);
        REG_FILE:
        for my $f (<$dir/*>) {
            my $dir_fname = $f;
            $dir_fname =~ s{$rsod}{}xms;
            my $href = x_file_to_href($f);
            if (!$href->{date}) {
                $c->log->info("missing date in $f");
                next REG_FILE;
            }
            my $reg_date = date($href->{date});
            next REG_FILE if $reg_date < $sdate || $reg_date > $edate;
            my $reg = 0;
            if ($href->{reg_id}) {
                $reg = model($c, 'Registration')->find($href->{reg_id});
            }
            elsif ($href->{trans_id}) {
                ($reg) = model($c, 'Registration')->search({transaction_id => $href->{trans_id}})
            }
            my $prog = model($c, 'Program')->find($href->{pid});
            my $pname = $prog? $prog->name: $href->{pname};
            push @regs, {
                name      => "$href->{last}, $href->{first}",
                program   => $pname,
                reg_id    => $href->{reg_id},
                reg_date8 => $reg_date->as_d8(),
                reg_date  => $reg_date,
                fname     => $dir_fname,
                transaction_id => $href->{trans_id},
                reg_exists => $reg,
            };
        }
        ++$m;
        if ($m > 12) {
            $m = 1;
            ++$y;
        }
        if ($y > $edate->year || ($y == $edate->year && $m > $edate->month)) {
            last REG_DIR;
        }
    }
    @regs = sort {
                lc $a->{$key} cmp lc $b->{$key}
            }
            @regs;
    stash($c,
        sdate    => $sdate,
        sdate8   => $sdate->as_d8(),
        edate    => $edate,
        edate8   => $edate->as_d8(),
        regs     => \@regs,
        template => "registration/online_history.tt2",
    );
}

sub restore : Local {
    my ($self, $c, $dir, $trans_id) = @_;

    my $fname = "root/static/online_done/$dir/$trans_id";
    if (! -f $fname) {
        error($c,
            "no such file: $fname",
            "registration/error.tt2",
        );
        return;
    }
    rename $fname, "root/static/online/$trans_id";
    $c->response->redirect($c->uri_for("/registration/list_online"));
}

1;
