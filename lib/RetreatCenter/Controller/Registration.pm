use strict;
use warnings;
package RetreatCenter::Controller::Registration;
use base 'Catalyst::Controller';

use DBIx::Class::ResultClass::HashRefInflator;      # ???

use lib '../../';       # so you can do a perl -c here.
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
    commify
    wintertime
    dcm_registration
    stash
    error
    payment_warning
    housing_types
    ptrim
    other_reserved_cids
    PR_other_reserved_cids
    invalid_amount
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
    $alert
    @clusters
/;
use Template;

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('program/list');    # ???
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
    for my $f (<root/static/online/*>) {
        open my $in, "<", $f
            or die "cannot open $f: $!\n";
        my ($date, $time, $first, $last, $pid, $synthesized);
        $synthesized = 0;
        while (<$in>) {
            if (m{x_date => (.*)}) {
                $date = date($1);
            }
            elsif (m{x_time => (.*)}) {
                $time = get_time($1);
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
        }
        close $in;
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
        (my $fname = $f) =~ s{root/static/online/}{};
        push @online, {
            first => $first,
            last  => $last,
            pname => $pname,
            pid   => $pid,
            date  => $date,
            time  => $time,
            fname => $fname,
            synth => $synthesized,
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
    my @files = <root/static/online/*>;
    my $sdate = $pr->sdate();
    my $nmonths = date($pr->edate())->month()
                - date($sdate)->month()
                + 1;
    stash($c,
        program         => $pr,
        pat             => $pat,
        daily_pic_date  => $sdate,
        cal_param       => "$sdate/$nmonths",
        regs            => _reg_table($c, \@regs),
        other_sort      => "list_reg_post",
        other_sort_name => "By Postmark",
        online          => scalar(@files),
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
    my @files = <root/static/online/*>;
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
    my @files = <root/static/online/*>;
    stash($c,
        online          => scalar(@files),
        program         => $pr,
        regs            => _reg_table($c, \@regs, postmark => 0),
        other_sort      => "list_reg_post",
        other_sort_name => "By Postmark",
        template        => "registration/list_reg.tt2",
    );
}

my %needed = map { $_ => 1 } qw/
    pid
    fname
    lname
    street1
    street2
    city
    state
    zip
    country
    home
    work
    cell
    ceu_license
    email
    house1
    house2
    cabin_room
    howHeard
    advertiserName
    gender
    carpool
    hascar
    amount
    date
    time
    e_mailings
    snail_mailings
    share_mailings
    sdate
    edate
    withwhom_first
    withwhom_last
    progchoice
    green_amount
/;

#
# an online registration via a file
#
sub get_online : Local {
    my ($self, $c, $fname) = @_;
    
    #
    # first extract all information from the file.
    #
    my %P;
    my $in;
    if (! open $in, "<", "root/static/online/$fname") {
        $c->response->redirect($c->uri_for("/registration/list_online"));
        return;
    }
    while (<$in>) {
        chomp;
        my ($key, $value) = m{^x_(\w+) => (.*)$};
        next unless $key;
        if ($needed{$key}) {
            $P{$key} = $value;
        }
        elsif ($key =~ m{^request\d+}) {
            $P{request} .= "$value\n";
        }
    }
    close $in;

    $P{green_amount} ||= 0;     # in case not set at all

    # save the filename so we can delete it when the registration is complete
    stash($c, fname => $fname);

    # verify that we have a pid, first, and last. and an amount.
    # ...???

    #
    # first, find the program
    # without it we can do nothing!
    #
    my $pr;
    if ($P{pid} == 0) {
        # find the appropriate Personal Retreat given the start date
        #
        my $sdate = date($P{sdate})->as_d8();
        ($pr) = model($c, 'Program')->search({
            name  => { -like => '%personal%retreat%' },
            sdate => { '<=' => $sdate },
            edate => { '>=' => $sdate },
        });
        if ($pr) {
            $P{pid} = $pr->id();
        }
        else {
            error($c,
                <<"EOH",
There is no Personal Retreat Program for $P{sdate}.
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
        ($pr) = model($c, 'Program')->find($P{pid});
    }
    if (! $pr) {
        error($c,
            "Unknown Program - cannot proceed",
            "registration/error.tt2",
        );
        return;
    }

    #
    # find or create a person object.
    #
    $P{fname} = normalize($P{fname});
    $P{lname} = normalize($P{lname});
    my @ppl = ();
    (@ppl) = model($c, 'Person')->search(
        {
            first => $P{fname},
            last  => $P{lname},
        },
    );
    my $p;
    my $today = tt_today($c)->as_d8();
    if (! @ppl || @ppl == 0) {
        #
        # no match so create a new person
        # check for misspellings first???
        # do an akey search, pop up list???
        # or cell phone search???
        #
        $p = model($c, 'Person')->create({
            first    => $P{fname},
            last     => $P{lname},
            addr1    => $P{street1},
            addr2    => $P{street2},
            city     => $P{city},
            st_prov  => $P{state},
            zip_post => $P{zip},
            country  => $P{country},
            akey     => nsquish($P{street1}, $P{street2}, $P{zip}),
            tel_home => $P{home},
            tel_work => $P{work},
            tel_cell => $P{cell},
            email    => $P{email},
            sex      => ($P{gender} eq 'Male'? 'M': 'F'),
            id_sps   => 0,
            e_mailings     => $P{e_mailings},
            snail_mailings => $P{snail_mailings},
            share_mailings => $P{share_mailings},
            date_updat => $today,
            date_entrd => $today,
        });
    }
    else {
        if (@ppl == 1) {
            # only one match so go for it
            $p = $ppl[0];
        }
        else {
            # disambiguate somehow???
            # cell first, then zip
            for my $q (@ppl) {
                if (digits($q->tel_cell) eq digits($P{cell})) {
                    $p = $q;
                }
            }
            if (!$p) {
                for my $q (@ppl) {
                    if ($q->zip_post eq $P{zip}) {
                        $p = $q;
                    }
                }
            }
            # else what else to do???
            if (! $p) {
                $p = $ppl[0];
            }
        }
        # we have one unique person
        #
        # that person's address etc gets the values
        # from the web registration.
        $p->update({
            addr1    => $P{street1},
            addr2    => $P{street2},
            city     => $P{city},
            st_prov  => $P{state},
            zip_post => $P{zip},
            country  => $P{country},
            akey     => nsquish($P{street1}, $P{street2}, $P{zip}),
            tel_home => $P{home},
            tel_work => $P{work},
            tel_cell => $P{cell},
            email    => $P{email},
            sex      => ($P{gender} eq 'Male'? 'M': 'F'),
            e_mailings     => $P{e_mailings},
            snail_mailings => $P{snail_mailings},
            share_mailings => $P{share_mailings},
            date_updat => $today,
        });
        my $person_id = $p->id();
    }

    #
    # various fields from the online file make their way
    # into the stash...

    # comments
    my $comment = "";
    if ($P{request}) {
        $comment = $P{request};
    }
    if ($P{progchoice} eq 'full') {
        stash($c, date_end => $pr->edate_obj() + $pr->extradays);
    }
    for my $how (qw/ ad web brochure flyer word_of_mouth /) {
        stash($c, "$how\_checked" => "");
    }
    # sdate/edate (in the hash from the online file)
    # are normally empty - except for personal retreats
    # OR for programs with extra days.
    #
    if ($P{sdate}) {
        stash($c, date_start => date($P{sdate}));
    }
    if ($P{edate}) {
        stash($c, date_end => date($P{edate}));
    }

    my $date = date($P{date});

    $P{time} = get_time($P{time})->t24();       # convert to 24 hour time
                                # could have just removed the colon but ...

    #
    # date_start and date_end are always present in the table record.
    # they are the program start/end dates unless overridden.
    # in the stash and on the screen they are blank if they
    # are the same as the program start/end dates.
    #
    # early and late are set accordingly when writing to
    # the database.
    #

    stash($c,
        comment         => $comment,
        share_first     => normalize($P{withwhom_first}),
        share_last      => normalize($P{withwhom_last}),
        cabin_checked   => $P{cabin_room} eq 'cabin'? "checked": "",
        room_checked    => $P{cabin_room} eq 'room' ? "checked": "",
        adsource        => $P{advertiserName},
        carpool_checked => $P{carpool}? "checked": "",
        hascar_checked  => $P{hascar }? "checked": "",
        date_postmark   => $date->as_d8(),
        time_postmark   => $P{time},
        green_amount    => $P{green_amount},
        deposit         => int($P{amount} - $P{green_amount}),
        deposit_type    => 'O',
        ceu_license     => $P{ceu_license},
        "$P{howHeard}_checked" => "selected",
    );

    _rest_of_reg($pr, $p, $c, $today, $P{house1}, $P{house2});
}

#
# the stash is partially filled in (from an online or manual reg).
# fill in the rest of it by looking at the program and person
# and render the view.
#
sub _rest_of_reg {
    my ($pr, $p, $c, $today, $house1, $house2, $cabin_room) = @_;

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
                  person_id  => $p->id(),
                  program_id => $pr->id(),
              });
    if (! $pr->allow_dup_regs() && @reg) {
        stash($c,
            template => "registration/dup.tt2",
            person   => $p,
            program  => $pr,
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
                     $p->affils;
    for my $pr_affil_id (map { $_->id } $pr->affils) {
        if (! exists $cur_affils{$pr_affil_id}) {
            model($c, 'AffilPerson')->create({
                a_id => $pr_affil_id,
                p_id => $p->id,
            });
        }
    }

    #
    # pop up comment?
    #
    # better way of searching the ids???
    #
    for my $a ($p->affils) {
        if ($a->id() == $alert) {
            my $s = $p->comment;
            $s =~ s{\r?\n}{\\n}g;
            stash($c, alert_comment => $s);
            last;
        }
    }
    #
    # life member or current sponsor?  with nights left?
    # they must be in good standing if sponsor
    # and can't take free nights if the housing cost is not a Per Day type.
    # and not if MMI program.
    #
    my $mem = $p->member();
    if ($pr->school() == 0 && $mem) {
        my $status = $mem->category;
        if ($status eq 'Life'
            || ($status eq 'Sponsor' && $mem->date_sponsor >= $today)
                                    # member in good standing
        ) {
            stash($c, status => $status);    # they always get a 30%
                                             # tuition discount.
            my $nights = $mem->sponsor_nights();
            if ($pr->housecost->type eq 'Per Day' && $nights > 0) {
                stash($c, nights => $nights);
            }
            if ($status eq 'Life' && ! $mem->free_prog_taken) {
                stash($c, free_prog => 1);
            }
        }
    }

    # any credits?
    if ($p->credits()) {
        CREDIT:
        for my $cr ($p->credits()) {
            if (! $cr->date_used && $cr->date_expires > $today) {
                stash($c, credit => $cr);
                last CREDIT;
            }
        }
    }

    if ($pr->footnotes =~ m{[*]}) {
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
        next HTYPE if $ht eq "single_bath" && ! $pr->sbath;
        next HTYPE if $ht eq "single"      && ! $pr->single;
        next HTYPE if $ht eq "economy"     && ! $pr->economy;
        next HTYPE if $ht eq "commuting"   && ! $pr->commuting;
        if ($ht !~ m{unknown|not_needed} && $pr->housecost->$ht == 0) {
            next HTYPE;
        }
        next HTYPE if $ht eq "center_tent" && wintertime($pr->sdate());

        my $selected = ($ht eq $house1 )? " selected": "";
        my $selected2 = ($ht eq $house2)? " selected": "";
        $h_type_opts .= "<option value=$ht$selected>$string{$ht}\n";
        $h_type_opts2 .= "<option value=$ht$selected2>$string{$ht}\n";
    }
    stash($c,
        program       => $pr,
        person        => $p,
        h_type_opts   => $h_type_opts,
        h_type_opts1  => $h_type_opts,
        h_type_opts2  => $h_type_opts2,
        confnotes     => [
            model($c, 'ConfNote')->search(undef, { order_by => 'abbr' })
        ],
        template    => "registration/create.tt2",
    );
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

#
# who is doing this?  and what's the current date/time?
#
sub get_now {
    my ($c, $reg_id) = @_;

    return
        reg_id   => $reg_id,
        user_id  => $c->user->obj->id,
        the_date => tt_today($c)->as_d8(),
        time     => get_time()->t24()
        ;
    # we return an array of 8 values perfect
    # for passing to a DBI insert/update.
}

# now we actually create the registration
# if from an online source there will be a filename
# in the %P which needs deleting.
#
sub create_do : Local {
    my ($self, $c) = @_;

    _get_data($c);
    if (@mess) {
        error($c,
            join("<br>", @mess),
            "registration/error.tt2",
        );
        return;
    }
    my $pr = model($c, 'Program')->find($P{program_id});
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
        comment       => $P{comment},
        h_type        => $P{h_type},
        h_name        => $P{h_name},
        kids          => $P{kids},
        confnote      => cf_expand($c, $c->request->params->{confnote}),
        status        => $P{status},
        nights_taken  => $taken,
        cancelled     => '',    # to be sure
        arrived       => '',    # ditto
        pref1         => $P{pref1},
        pref2         => $P{pref2},
        share_first   => normalize($P{share_first}),
        share_last    => normalize($P{share_last}),
        manual        => $P{dup}? "yes": "",
        cabin_room    => $P{cabin_room} || "",
        leader_assistant => '',
        free_prog_taken  => $P{free_prog},

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
    my @who_now = get_now($c, $reg_id);

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
        @who_now,
        what    => 'Registration Created',
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
            what    => 'Credit from the '
                       . $pr_g->name . ' program in '
                       . $pr_g->sdate_obj->format("%B %Y"),
        });
        # and mark the credit as taken
        $cr->update({
            date_used   => tt_today($c)->as_d8(),
            used_reg_id => $reg_id,
        });
    }
    # the payment (deposit)
    if ($pr->school == 0 && $P{deposit}) {
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
            the_date  => tt_today($c)->as_d8(),
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
            INCLUDE_PATH => 'root/static/templates/letter',
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
        );
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
    if (exists $P{fname}) {
        my $dir = "root/static/online_done/"
                . substr($P{date_postmark}, 0, 4)
                . '-'
                . substr($P{date_postmark}, 4, 2)
                ;
        mkdir $dir unless -d $dir;
        rename "root/static/online/$P{fname}",
               "$dir/$P{fname}";
    }

    # was there an online donation to the green fund?
    #
    if ($P{green_amount}) {
        # which XAccount id?
        my ($xa) = model($c, 'XAccount')->search({
            glnum => $string{green_glnum},
        });
        if ($xa) {
            model($c, 'XAccountPayment')->create({
                xaccount_id => $xa->id(),
                person_id   => $P{person_id},
                amount      => $P{green_amount},
                type        => 'O',     # credit
                what        => '',
                @who_now[2..7],     # not reg_id => $reg_id
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
                INCLUDE_PATH => 'root/static/templates/letter',
                EVAL_PERL    => 0,
            });
            $tt->process(
                "green.tt2",      # template
                $stash,           # variables
                \$html,           # output
            );
            email_letter($c,
                to      => $reg->person->name_email(),
                from    => "$string{green_name} <$string{green_from}>",
                subject => $string{green_subj},
                html    => $html,
            );
        }
        else {
            # error! - no glnum for green fund???
        }
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
    # clear auto charges
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
        if ($pr->retreat()) {
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
                what      => $what,
            });
        }

        # sponsor/life members get a discount on tuition
        # up to a max.  and only for MMC events, not MMI.
        #
        if ($pr->school() == 0 && $reg->status() && $tuition > 0) {
            # Life members can take a free program ... so:
            if ($reg->free_prog_taken) {
                model($c, 'RegCharge')->create({
                    @who_now,
                    automatic => 'yes',
                    amount    => -1*$tuition,
                    what      => "Life member - free program - tuition waived.",
                });
            }
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
                    what      => "$string{spons_tuit_disc}% Tuition discount for "
                                . $reg->status . " member$maxed",
                });
            }
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
            amount    => $tot_h_cost,
            what      => $what,
        });
    }
    if ($auto && $pr->school() != 0 && ! $lead_assist) {
        # MMI registrants have an extra day at the commuting rate.
        #
        my $commute_cost = $housecost->commuting();
        model($c, 'RegCharge')->create({
            @who_now,
            automatic => 'yes',
            amount    => $commute_cost,
            what      => "1 day at commuting rate of \$$commute_cost",
        });
        $tot_h_cost += $commute_cost;
    }

    # extra days - at the current personal retreat housecost rate.
    # but not for leaders/assistants???  right?
    # show leader/asst on reg screen???   show footnotes differently?
    #
    my $extra_h_cost = 0;
    if ($auto && $extra_days && ! $lead_assist) {
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
            what      => "Life member - free program - lodging waived",
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
        && $pr->school() == 0      # not MMI
        && !$life_free
        && !$lead_assist
        && $housecost->type eq "Per Day"
    ) {
        if ($prog_days + $extra_days >= $string{disc1days}) {
            model($c, 'RegCharge')->create({
                @who_now,
                automatic => 'yes',
                amount    => -1*(int(($string{disc1pct}/100)*$tot_h_cost + .5)),
                what      => "$string{disc1pct}% Lodging discount for"
                            ." programs >= $string{disc1days} days",
            });
        }
        if ($prog_days + $extra_days >= $string{disc2days}) {
            model($c, 'RegCharge')->create({
                @who_now,
                automatic => 'yes',
                amount    => -1*(int(($string{disc2pct}/100)*$tot_h_cost + .5)),
                what      => "$string{disc2pct}% Lodging discount for"
                            ." programs >= $string{disc2days} days",
            });
        }
	}
    #
    # Personal Retreat discounts during special period
    #
    if ($pr->PR()
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
        my $meal_cost = $string{member_meal_cost};
        my $plural = ($ntaken == 1)? "": "s";
        model($c, 'RegCharge')->create({
            @who_now,
            automatic => 'yes',
            amount    => ($ntaken * $meal_cost),
            what      => "$ntaken day$plural of meals"
                       . " at \$$meal_cost per day for "
                       . $reg->status() . " member",
        });
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
        if ($af->descrip() =~ m{mmi\s+discount}i) {
            $requested = 1;
            last AFFIL;
        }
    }
    if ($auto && $requested) {
        model($c, 'RegCharge')->create({
            @who_now,
            automatic => 'yes',
            amount    => -1*(int(($string{mmi_discount}/100)*$tot_h_cost + .5)),
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
            what      => "CEU License fee",
        });
    }

    _calc_balance($reg);

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

sub _calc_balance {
    my ($reg) = @_;

    # calculate the balance, update the reg record
    my $balance = 0;
    for my $ch ($reg->charges) {
        $balance += $ch->amount;
    }
    my $payments = ($reg->program->school() != 0)? "mmi_payments"
                  :                                "payments"
                  ;
    for my $py ($reg->$payments) {
        $balance -= $py->amount;
    }
    $reg->update({
        balance => $balance,
    });
}

#
# send a confirmation letter.
# fill in a template and send it off.
# use the template toolkit outside of the Catalyst mechanism.
# if there is a non-blank confnote
# create a ConfHistory record for this sending.
#
sub send_conf : Local {
    my ($self, $c, $id, $preview) = @_;

    my $reg = model($c, 'Registration')->find($id);
    my $pr = $reg->program;
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
        today    => tt_today($c),
        deposit  => $reg->deposit,
        htdesc   => $htdesc,
        article  => ($htdesc =~ m{^[aeiou]}i)? 'an': 'a',
        carpoolers => $carpoolers,
    };
    my $html = "";
    my $tt = Template->new({
        INCLUDE_PATH => 'root/static/templates/letter',
        EVAL_PERL    => 0,
    });
    $tt->process(
        $pr->cl_template . ".tt2",      # template
        $stash,                         # variables
        \$html,                         # output
    );
    #
    # assume the letter will be successfully
    # printed or sent - if you are not previewing, that is.
    #
    if (! $preview) {
        _reg_hist($c, $id, "Confirmation Letter sent");
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
    if (! $reg->person->email || $preview) {
        $c->res->output($html);
        return;
    }
    email_letter($c,
           to      => $reg->person->name_email(),
           from    => "$string{from_title} <$string{from}>",
           subject => "Confirmation of Registration for " . $pr->title(),
           html    => $html, 
    );
    my @who_now = get_now($c, $id);
    if ($reg->confnote) {
        model($c, 'ConfHistory')->create({
            @who_now,
            note => $reg->confnote,
        });
    }
    $c->response->redirect($c->uri_for("/registration/view/$id"));
}

sub view : Local {
    my ($self, $c, $reg_id) = @_;

    my $reg = model($c, 'Registration')->find($reg_id);
    stash($c, reg => $reg);
    _view($c, $reg);
}

sub _view {
    my ($c, $reg) = @_;
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
    # to DCM?
    my $dcm_reg_id = 0;
    my $dcm_type = '';
    if ($prog->level() eq 'S') {
        my $dcm = dcm_registration($c, $reg->person->id());
        if (ref($dcm)) {
            $dcm_reg_id = $dcm->id();
            my $lev = $dcm->program->level();
            $dcm_type = $lev eq 'D'? 'Diploma'
                       :$lev eq 'C'? 'Certificate'
                       :$lev eq 'M'? 'Masters'
                       :             'DCM'
                       ;
        }
        # else if $dcm > 1 !!!! ???? give error
        # prohibit it from happening in the first place!
        # my $person = model($c, 'Person')->find($person_id);
        # my $name = $person->first() . " " . $person->last();
        # $c->stash->{mess}
        #   = (@dcm)? "$name is enrolled in <i>more than one</i> D/C/M program!"
        #   :       "$name is not enrolled in <i>any</i> D/C/M program!";
    }
    my @files = <root/static/online/*>;
    my $share_first = $reg->share_first();
    my $share_last  = $reg->share_last();
    my $share = "$share_first $share_last";
    if ($share_first) {
        if (my ($person) = model($c, 'Person')->search({
                               first => $share_first,
                               last  => $share_last,
                           })
        ) {
            if (my ($next_reg) = model($c, 'Registration')->search({
                                     person_id  => $person->id(),
                                     program_id => $reg->program_id(),
                                 })
            ) {
                my $next_id = $next_reg->id();
                $share = "<a href=/registration/view/$next_id>$share</a>";
            }
            else {
                # not registered - but are they in the online list?
                my ($found_first, $found_last) = (0, 0);
                for my $f (<root/static/online/*>) {
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
                    $share .= " - <span class=required><b>is</b> in the online list</span>";
                }
                else {
                    $share .= " - <span class=required>not registered</span>";
                }
            }
        }
        else {
            $share .= " - <span class=required>could not find</span>";
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
        $nmonths = date($prog->edate())->month()
                   - date($sdate)->month()
                   + 1;
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
    stash($c,
        pers_label     => $pers_label,
        online         => scalar(@files),
        share          => $share,
        non_pr         => ! $PR,
        daily_pic_date => $sdate,
        cal_param      => "$sdate/$nmonths",
        # ??? can get cluster id from Global settings, yes???
        cur_cluster    => ($reg->house_id)? $reg->house->cluster_id: 1,
        dcm_reg_id     => $dcm_reg_id,
        dcm_type       => $dcm_type,
        program        => $prog,
        only_one       => (@same_name_reg == 1),
        send_preview   => ($PR || $same_name_reg[0]->id() == $reg->id()),
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
    stash($c,
        message  => payment_warning('mmc'),
        from     => $from,
        reg      => $reg,
        template => "registration/pay_balance.tt2",
    );
}

sub pay_balance_do : Local {
    my ($self, $c, $reg_id) = @_;

    my $reg = model($c, 'Registration')->find($reg_id);
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
    my @who_now = get_now($c, $reg_id);
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
        arrived => 'yes',
    });
    if ($balance == 0) {
        model($c, 'RegHistory')->create({
            @who_now,
            what => 'Arrival and Payment of Balance',
        });
    }
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

    if ($reg->program->school() != 0) {
        # when MMI students cancel, there is no credit, no letter
        #
        cancel_do($self, $c, $id, 1);       # 1 => mmi
        return;
    }
    my $today = tt_today($c);
    Global->init($c);
    stash($c,
        today    => $today,
        ndays    => $reg->program->sdate_obj - $today,
        reg      => $reg,
        amount   => $string{credit_amount},
        template => "registration/credit_confirm.tt2",
    );
}

sub cancel_do : Local {
    my ($self, $c, $id, $mmi) = @_;

    my $credit      = $c->request->params->{give_credit};
    my $send_letter = $c->request->params->{send_letter};
    my $amount      = $c->request->params->{amount};
    my $reg         = model($c, 'Registration')->find($id);

    if (!$mmi && defined $amount && invalid_amount($amount)) {
        error($c,
            "Illegal amount: $amount",
            'gen_error.tt2',
        );
        return;
    }
    $reg->update({
        cancelled => 'yes',
    });

    # return any assigned housing to the pool
    _vacate($c, $reg) if $reg->house_id();

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

    my $date_expire;
    if (! $mmi) {
        # give credit
        #
        if ($credit) {
            # credit record
            my $sdate = $reg->program->sdate_obj();
            $date_expire = date(
                $sdate->year() + 1,
                $sdate->month(),
                $sdate->day(),
            );
            model($c, 'Credit')->create({
                reg_id       => $id,
                person_id    => $reg->person->id(),
                amount       => $amount,
                date_given   => tt_today($c)->as_d8(),
                date_expires => $date_expire->as_d8(),
                date_used    => "",
                used_reg_id  => 0,
                # How about who did this??? and what time?
            });
        }
    }
    # add reg history record
    _reg_hist($c, $id,
        "Cancelled"
        . ($mmi? ""
          :      (($credit)? " - Credit of \$$amount given."
                  :          " - No credit given."))
    );

    # decrement the reg_count in the program record
    my $prog_id   = $reg->program_id;
    my $pr = model($c, 'Program')->find($prog_id);
    $pr->update({
        reg_count => \'reg_count - 1',
    });

    if (! $mmi && $send_letter) {
        #
        # send the cancellation confirmation letter for MMC programs
        #
        my $html = "";
        my $tt = Template->new({
            INCLUDE_PATH => 'root/static/templates/letter',
            EVAL_PERL    => 0,
        });
        my $template = $reg->program->cl_template . "_cancel.tt2";
        if (! -f "root/static/templates/letter/$template") {
            $template = "default_cancel.tt2";
        }
        my $stash = {
            person      => $reg->person,
            program     => $reg->program,
            credit      => $credit,
            amount      => $amount,
            date_expire => $date_expire,
            user        => $c->user,
            today       => tt_today($c),
        };
        $tt->process(
            $template,      # template
            $stash,         # variables
            \$html,         # output
        );
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
        from     => $from,
        reg      => $reg,
        template => "registration/new_charge.tt2",
    );
}
sub new_charge_do : Local {
    my ($self, $c, $reg_id) = @_;

    my $amount = trim($c->request->params->{amount});
    my $what   = trim($c->request->params->{what});
    
    my @mess = ();
    if (empty($amount)) {
        push @mess, "Missing Amount";
    }
    if (invalid_amount($amount)) {
        push @mess, "Illegal Amount: $amount";
    }
    if (empty($what)) {
        push @mess, "Missing What";
    }
    if (@mess) {
        error($c,
            join("<br>", @mess),
            "registration/error.tt2",
        );
        return;
    }

    # another way to get the user data???
    my $username = $c->user->username();
    my ($u) = model($c, 'User')->search({
        username => $username,
    });
    my $user_id = $u->id;

    my $today = tt_today($c);
    my $now_date = $today->as_d8();
    my $now_time = get_time()->t24();

    model($c, 'RegCharge')->create({
        reg_id    => $reg_id,
        user_id   => $user_id,
        the_date  => $now_date,
        time      => $now_time,
        amount    => $amount,
        what      => $what,
        automatic => '',        # this charge will not be cleared
                                # when editing a registration.
    });
    my $reg = model($c, 'Registration')->find($reg_id);
    $reg->update({
        balance => $reg->balance + $amount,
    });
    if ($c->request->params->{from} eq 'edit_dollar') {
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
        # only if the program is not in the past.
        #
        if (@$reg_aref) {
            my $pr = $reg_aref->[0]->program();
            if ($pr->sdate() <= today()->as_d8()) {
                $show_arrived = 1;
            }
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
        my $balance = $reg->balance();
        my $type = $reg->h_type_disp();

        my $h_type = $reg->h_type();
        my $pref1 = $reg->pref1();
        my $pref2 = $reg->pref2();

        my $need_house = (defined $type)? $type !~ m{commut|van|unk}i
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
                    && ($level eq 'S' || $level eq ' ')
                    && !$reg->letter_sent)?
                       "<img src=/static/images/envelope.jpg height=$ht>"
                  :    "";
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
        if ($school != 0 && $pr->level() eq 'S') {
            #
            # A/D/C/M marks for MMI _course_ registrations
            # not registrants in the D/C/M programs themselves
            #
            my $dcm = dcm_registration($c, $reg->person->id());
            my $type = 'A';
            if (ref($dcm)) {
                $type = $dcm->program->level();
            }
            elsif ($dcm) {
                $type = '?';
            }
            if (!($type eq 'A' || $school == 3)
                && $mark =~ m{envelope}
            ) {
                # Auditor and School of Massage (3 is hard coded :( )
                # can have envelope for non-sent confirmation letters
                # others no.
                #
                $mark = $type;
            }
            else {
                $mark = "$type $mark";
            }
        }
        if ($show_arrived
            && $reg->arrived() eq 'yes'
            && $reg->cancelled() ne 'yes'
        ) {
            $mark = "<span class=arrived_star>*</span> $mark";
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
            && ($school == 0 || $mmi_admin)
        ) {
            $pay_balance =
                "<a href='/registration/pay_balance/$id/list_reg_name'>"
               ."$pay_balance</a>";
        }
        if ($school == 0 || $mmi_admin) {
            $name = "<a href='/registration/view/$id'>$name</a>";
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
    $body ||= "";
<<"EOH";        # returning a bare string heredoc constant?  sure.
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
sub update_confnote_do : Local{
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
    $c->response->redirect($c->uri_for("/registration/view/$id"));
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
    for my $ref (qw/ad web brochure flyer word_of_mouth/) {
        stash($c, "$ref\_selected" => ($reg->referral eq $ref)? "selected": "");
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
    my $status = $reg->status;      # status at time of first registration
    if ($status) {
        my $mem = $reg->person->member;
        my $nights = $mem->sponsor_nights + $reg->nights_taken;
        if ($pr->housecost->type eq 'Per Day' && $nights > 0) {
            stash($c, nights => $nights);
        }
        if ($status eq 'Life'
            && (! $mem->free_prog_taken || $reg->free_prog_taken())
        ) {
            stash($c, free_prog => 1);
        }
    }
    my $c_r = $reg->cabin_room();
    stash($c,
        person          => $reg->person,
        reg             => $reg,
        program         => $pr,
        h_type_opts     => $h_type_opts,
        h_type_opts1    => $h_type_opts1,
        h_type_opts2    => $h_type_opts2,
        carpool_checked => $reg->carpool()   ? "checked": "",
        hascar_checked  => $reg->hascar()    ? "checked": "",
        cabin_checked   => $c_r eq 'cabin'   ? "checked": "",
        room_checked    => $c_r eq 'room'    ? "checked": "",
        work_study_checked => $reg->work_study()? "checked": "",
        note_lines      => lines($reg->confnote()) + 3,
        comment_lines   => lines($reg->comment ()) + 3,
        leader_assistant_checked => $P{leader_assistant}? "checked": "",
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

    my @who_now = get_now($c, $id);

    %dates = transform_dates($pr, %dates);
    if ($dates{date_start} > $dates{date_end}) {
        error($c,
            "Start date is after the end date.",
            "registration/error.tt2",
        );
        return;
    }
    if ($reg->house_id()
        && (($P{h_type} ne $reg->h_type())
            ||
            ($dates{date_start} != $reg->date_start())
            ||
            ($dates{date_end}   != $reg->date_end())
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
    my @note_opt = ();
    if ($reg->confnote() ne $newnote) {
        @note_opt = (
            confnote    => $newnote,
            letter_sent => '',
        );
    }
    $reg->update({
        ceu_license   => $P{ceu_license},
        referral      => $P{referral},
        adsource      => $P{adsource},
        carpool       => $P{carpool},
        hascar        => $P{hascar},
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
        work_study    => $P{work_study},
        free_prog_taken    => $P{free_prog},
        work_study_comment => $P{work_study_comment},

        %dates,         # optionally
        @note_opt,           # ditto
    });

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
# we now need to get the rest of the registration details.
#
sub manual : Local {
    my ($self, $c) = @_;

    my @mess = ();
    my $deposit      = $c->request->params->{deposit};
    if ($deposit !~ m{^\d+$}) {
        push @mess, "Illegal deposit: $deposit";
    }
    my $deposit_type = $c->request->params->{deposit_type};
    my $date_post    = $c->request->params->{date_post};
    my $d = date($date_post);
    if (! $d) {
        push @mess, "Illegal postmark date: $date_post";
    }
    if (@mess) {
        error($c,
            join("<br>", @mess),
            "registration/error.tt2",
        );
        return;
    }
    $date_post = $d;
    my $program_id   = $c->request->params->{program_id};
    my $person_id    = $c->request->params->{person_id};

    my $pr = model($c, 'Program')->find($program_id);
    my $p  = model($c, 'Person')->find($person_id);

    stash($c,
        deposit       => $deposit,
        deposit_type  => $deposit_type,
        date_postmark => $date_post->as_d8(),
        time_postmark => "1200",        # good guess?
        cabin_checked => "",
        room_checked  => "",
    );
    _rest_of_reg($pr, $p, $c, tt_today($c), 'dble', 'dble', 'room');
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
# choosing a house (given a housing type)
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

    #
    # housed with a friend who is also registered for this program?
    #
    my $share_house_id = 0;
    my $share_house_name = "";
    my $share_first = $reg->share_first();
    my $share_last  = $reg->share_last();
    my $name = "$share_first $share_last";
    my $message2 = "";
    my $reg2;
    if ($share_first) {
        my ($person) = model($c, 'Person')->search({
            first => $share_first,
            last  => $share_last,
        });
        if ($person) {
            ($reg2) = model($c, 'Registration')->search({
                person_id => $person->id,
                program_id => $program_id,
            });
            # if space left, same dates, same h_type, etc etc.
            # oh jeez - I can't do everything.
            # the best, I guess, would be to simply inform
            # the registrar of where their friend is housed.
            # if that room appears in the list (I can default it)
            # then they can choose it.
            if ($reg2) {
                if ($reg2->cancelled()) {
                    $message2 = "$share_first $share_last has cancelled.";
                }
                elsif ($reg2->house_id) {
                    if ($reg2->h_type eq $reg->h_type) {
                        $share_house_name = $reg2->house->name;
                        $share_house_id   = $reg2->house_id;
                        $message2 = "Share $share_house_name"
                                   ." with $share_first $share_last?";
                    }
                    else {
                        $message2 = "$name is housed in a '"
                                  . $reg2->h_type_disp
                                  . "' not a '"
                                  . $reg->h_type_disp
                                  . "'."
                                  ;
                    }
                }
                else {
                    $message2 = "$name has not yet been housed.";
                }
            }
            else {
                $message2 = "$name has not yet registered for "
                          . $reg->program->name . ".";
            }
        }
        else {
            $message2 = "Could not find a person named $name.";
        }
        #
        # if the person hasn't yet registered for this program
        # look for them in the online files.
        #
        if ($message2 =~ m{Could not find|has not yet reg}) {
            my $found = 0;
            ONLINE:
            for my $f (<root/static/online/*>) {
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
                    $message2 = "$share_first $share_last <b>has</b> registered"
                               ." online but has not yet been imported.";
                    $found = 1;
                    last ONLINE;
                }
            }
            if (! $found) {
                #
                # make sure the confirmation note has a notice
                # about their friend who has not yet registered.
                #
                if ($reg->confnote() !~ m{$share_first $share_last}) {
                    my $cn = ptrim($reg->confnote());
                    if ($cn) {
                        $cn .= "<p></p>";
                    }
                    $reg->update({
                        confnote => $cn
                                  . "<p>$share_first $share_last still needs"
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
    my $cabin  = $reg->cabin_room() eq 'cabin';
    my @kids   = ($reg->kids)? (cur => { '>', 0 })
                 :             ();

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
        my $cl_tent   = $cl_name =~ m{tent|terrace}i;
        my $cl_center = $cl_name =~ m{center}i;
        if (($tent && !$cl_tent) ||
            (!$tent && $cl_tent) ||
            ($summer && (!$center && $cl_center ||
                         $center && !$cl_center   ))
                # watch out for the word center
                # in indoor housing cluster names!
        ) {
            next CLUSTER;
        }
        HOUSE:
        for my $h (@{$houses_in_cluster{$cl_id}}) {
            # is the max of the house inconsistent with $max?
            # or the bath status
            #
            # quads are okay when looking for a dorm
            # and this takes some fancy footwork.
            #
            my $h_id = $h->id;
            if (($h->max < $low_max) ||
                ($h->bath && !$bath) ||
                (!$h->bath && $bath)
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
            # P - perfect size - no further resize needed
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
                $codes .= "O";
                $code_sum += $string{house_sum_occupied};
            }
            if ($F) {
                $codes .= "F";
                $code_sum += $string{house_sum_foreign};     # discourage this!
                                                             # will be < 0.
            }
            if ($P) {
                $code_sum += $string{house_sum_perfect_fit};
            }
            else {
                $codes .= "R";      # resize needed - not as good...
            }
            if ($reserved_cids{$cl_id}) {
                $codes .= "r";
                $code_sum += $string{house_sum_reserved};
            }
            if ($h->cabin()) {
                $codes .= "C";
                if ($cabin) {
                    $code_sum += $string{house_sum_cabin};
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
                      . $h->name
                      . $codes
                      . "</option>\n"
                      ;
            push @h_opts, [ $opt, $code_sum, $h->priority ];
            ++$n;
            if ($h_id == $share_house_id) {
                $selected = 1;
            }
        }   # end of houses in this cluster
    }   # end of CLUSTER
    #
    # and now the big sort:
    #
    @h_opts = map {
                    $_->[0]
              }
              sort {
                  $b->[1] <=> $a->[1] ||      # 1st by code_sum - descending
                  $a->[2] <=> $b->[2]         # 2nd by priority - ascending
              }
              @h_opts;
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
    if (my @ages = $reg->kids() =~ m{(\d+)}g) {
        stash($c, kids => " with child" . ((@ages > 1)? "ren":""));
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
        daily_pic_date => $reg->date_start,
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
        stash($c,
            reg_id   => $id,
            template => "registration/dblclick.tt2",
        );
        return;
    }
    my $new_htype = $c->request->params->{htype};
    my @who_now = get_now($c, $id);
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
    if ($reg->confnote() ne $newnote) {
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
    _reg_hist($c, $id, "Lodged as $string{$new_htype} in $house_name_of{$house_id}.");
    my $kids = $reg->kids;
    for my $cf (model($c, 'Config')->search({
                    house_id => $house_id,
                    the_date => { 'between' => [ $sdate, $edate1 ] }
                })
    ) {
        my $csex = $cf->sex;
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
                            || $csex eq $psex)? $psex
                           :                    'X'),
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
    $c->response->redirect($c->uri_for("/registration/view/$id"));
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
        # if we're back to one and the sex is 'X'
        #    find out the gender of the remaining person.
        #    VERY tricky, indeed.
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
        if ($cf->cur() == 2 && $cf->sex eq 'X') {
            my $the_date = $cf->the_date;
            my @reg = model($c, 'Registration')->search({
                house_id   => $house_id,
                date_start => { '<=', $the_date },
                date_end   => { '>',  $the_date },
                id         => { '!=', $reg->id  },
            });
            if (@reg == 1) {
                push @opts, sex => $reg[0]->person->sex;
            }
            else {
                $c->log->info("Inconsistent config records??? $#reg");
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
        my @files = <root/static/online/*>;
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
        my @files = <root/static/online/*>;
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

sub cf_expand {
    my ($c, $s) = @_;
    $s = etrim($s);
    return $s if empty($s);
    # ??? get these each time??? cache them!
    # certainly!  in Global.
    my %note;
    for my $cf (model($c, 'ConfNote')->all()) {
        $note{$cf->abbr()} = etrim($cf->expansion());
    }
    $s =~ s{<p>(\S+)</p>}{'<p>' . ($note{$1} || $1) . '</p>'}gem;
    $s;
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
        my $mmi = $pr->school() != 0;
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
    $reg_names =~ s{'}{\\'}g;       # for O'Dwyer etc.
                                # can't use &apos; :( why?
    for my $b (@blocks) {
        my $nbeds = $b->nbeds();
        my $pl = ($nbeds == 1)? "": "s";
        $reg_names .= "<tr><td>"
                   .  "<a target=happening href=/block/view/"
                   .  $b->id()
                   .  ">$nbeds bed$pl blocked</a></td><td>"
                   .  $b->reason()
                   .  "</td></tr>"
                   ;
    }
    $c->res->output("<center>"
                   . $house_name_of{$house_id}
                   . "</center>"
                   . "<p><table cellpadding=2>$reg_names</table>"
                   );
}

sub _get_kids {
    my ($s) = @_;
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

sub ceu : Local {
    my ($self, $c, $reg_id, $override_hours) = @_;
    $c->res->output(
        ceu_license(
            model($c, 'Registration')->find($reg_id),
            $override_hours,
        )
    );
    return;
}

my $npeople;
my @people;
my @star;
my $containing;

sub _person_data {
    my ($i) = @_;

    if ($i >= $npeople) {
        return "";
    }
    my $p = $people[$i];
    if ($containing eq 'all') {
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
             . ($p->email   ? $p->email                 : "")
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
        return $p->email? ($p->email . "<br>")
               :          ""
               ;
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
    my $including = $c->request->params->{including};
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
            program_id => $prog_id,
            cancelled  => { '!=' => 'yes' },
            @cond,
        },
        {
            join     => [qw/ person /],
            order_by => $order,
            prefetch => [qw/ person /],   
        }
    );
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
    @star = ();
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
    my $mailto = "";
    $containing = $c->request->params->{containing};
    if ($c->request->params->{format} eq 'linear') {
        $info_rows = "";
        for my $i (0 .. $#people) {
            my $s = _person_data($i);
            $info_rows .= "$s\n";
            if ($containing eq "email") {
                $s =~ s{<br>}{};
                $mailto .= "$s," if $s;
            }
        }
        if ($containing eq "email") {
            $mailto =~ s{,$}{};
            $mailto = "<a href='mailto: ?bcc=$mailto'>Email All</a><p>\n";
                # for some reason, we need the space after the :
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

            $info_rows .= "<td valign=top>" . _person_data($i) . "</td>";
            $info_rows .= "<td valign=top>" . _person_data($i+$n) . "</td>";
            $info_rows .= "<td valign=top>" . _person_data($i+2*$n) . "</td>";

            $info_rows .= "</tr>\n";
        }
        $info_rows .= "</table>\n";
        if ($containing eq "email") {
            $mailto =~ s{,$}{};
            $mailto = "<a href='mailto:?bcc=$mailto'>Email All</a><p>\n";
        }
    }
    my $html = "";
    my $tt = Template->new({
        INCLUDE_PATH => 'root/src',
        EVAL_PERL    => 0,
    }) or die Template->error();
    my $stash = {
        program => $program,
        rows    => $info_rows,
        mailto  => $mailto,
        type    => ($including eq 'both'    ? ''
                   :$including eq 'normal'  ? 'Normal '
                   :$including eq 'extended'? 'Extended '
                   :                          ''),
    };
    $tt->process(
        "registration/name_addr.tt2",   # template
        $stash,               # variables
        \$html,               # output
    ) or die $tt->error();
    my $email = "";
    for my $em (keys %{$c->request->params()}) {
        if ($em =~ m{^email}) {
            $email .= $c->request->params->{$em} . ", ";
        }
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
        $c->res->output($html);
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

    my $tuition    = 0;
    my $lodging    = 0;
    my $adjustment = 0;

    my $deposit    = 0;
    my $payment    = 0;
    my $balance    = 0;

    my $credit     = 0;

    my %seen;
    REG:
    for my $r (@regs) {
        for my $rp ($r->payments()) {
            my $what   = $rp->what;
            my $amount = $rp->amount();
            if ($what =~ m{deposit}i) {
                $deposit += $amount;
            }
            elsif ($what =~ m{payment}i) {
                $payment += $amount;
            }
            else {
                # ??? what else?
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
        for my $rc ($r->charges()) {
            my $what   = $rc->what();
            my $amount = $rc->amount();
            if (! $r->cancelled()) {
                if ($what =~ m{tuition}i) {
                    $tuition += $amount;
                }
                elsif ($what =~ m{lodging}i) {
                    $lodging += $amount;
                }
                else {
                    $adjustment += $amount;
                }
            }
        }
        if (! $r->cancelled()) {
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
    stash($c,
        program    => $pr,
        id         => $prog_id,
        registered => $registered,
        cancelled  => $cancelled,
        no_shows   => $no_shows,
        males      => $males,
        females    => $females,
        adults     => $adults,
        kids       => $kids,
        tuition    => commify($tuition),
        lodging    => commify($lodging),
        adjustment => commify($adjustment),
        deposit    => commify($deposit),
        payment    => commify($payment),
        credit     => commify($credit),
        balance    => commify($balance),
        template   => "registration/tally.tt2",
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
# everyone who is in a D/C/M program that is concurrent
# with the given program.   Offer the list of D/C/M programs
# and let the user choose which to do the import on.
#
sub mmi_import : Local {
    my ($self, $c, $program_id) = @_;

    my $p = model($c, 'Program')->find($program_id);
    my $sdate = $p->sdate();
    my @progs = model($c, 'Program')->search({
        school => { '!=', 0      },
        # should we only accept DCM people in the same school
        # as the course we are importing into???
        #
        level  => { '!=', 'S'    },
        sdate  => { '<=', $sdate },
        edate  => { '>=', $sdate },
    },
    {
        order_by => 'sdate asc, edate asc',
    });
    stash($c,
        cur_prog  => $p,
        dcm_progs => \@progs,
        template  => "registration/mmi_import.tt2",
    );
}

sub mmi_import_do : Local {
    my ($self, $c, $program_id) = @_;

    my $program = model($c, 'Program')->find($program_id);
    my %person_ids = ();
    for my $dcm_id (keys %{ $c->request->params() }) {
        $dcm_id =~ s{^n}{};
        REG:
        for my $reg (model($c, 'Program')->find($dcm_id)->registrations()) {
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
        #
        # if the current program is in the wintertime, keep looking
        # for a non-tent option in reverse chronological order.
        #
        # a small weakness - if the prior registrations were all
        # in the wintertime and now they want a tent - we can't guess that.
        #
        my @h_types
            = grep {
                  m{\S} && ! m{unknown|not_needed}
                      # we only want valid types
              }
              map {
                  $_->h_type()
              }
              model($c, 'Registration')->search(
                  { person_id => $person_id        },
                  { order_by  => 'date_start desc' },
              );
        my $h_type = shift @h_types;
        if ($h_type =~ m{tent} && wintertime($program->sdate())) {
            $h_type = "";
            H_TYPE:
            for my $ht (@h_types) {
                if ($ht !~ m{tent}) {
                    $h_type = $ht;
                    last H_TYPE;
                }
            }
        }
        $h_type ||= "dble";     # a good choice for a last chance default
        my $edate = date($program->edate()) + $program->extradays();
        model($c, 'Registration')->create({
            person_id  => $person_id,
            program_id => $program_id,
            house_id   => 0,
            h_type     => $h_type,
            cancelled  => '',    # to be sure
            arrived    => '',    # ditto
            date_start => $program->sdate(),
            date_end   => $edate->as_d8(),
            balance    => 0,
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

    my @who_now = get_now($c, $reg_id);

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
        auto_total => $auto_total,
        reg => $reg,
        template => 'registration/edit_dollar.tt2',
    );
}

sub charge_delete : Local {
    my ($self, $c, $reg_id, $ch_id, $from) = @_;

    model($c, 'RegCharge')->find($ch_id)->delete();
    _calc_balance(model($c, 'Registration')->find($reg_id));
    if ($from eq 'edit_dollar') {
        $c->response->redirect(
            $c->uri_for("/registration/edit_dollar/$reg_id")
        );
    }
    else {
        $c->response->redirect($c->uri_for("/registration/view/$reg_id"));
    }
}

sub payment_delete : Local {
    my ($self, $c, $reg_id, $pay_id, $from) = @_;

    model($c, 'RegPayment')->find($pay_id)->delete();
    _calc_balance(model($c, 'Registration')->find($reg_id));
    if ($from eq 'edit_dollar') {
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
    if ($what eq 'Deposit') {
        # need to update the deposit field in the reg record
        #
        $reg->update({
            deposit => $amount,
        });
    }
    # ??? also update who, when
    _calc_balance($pay->registration());
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

    stash($c,
        from => $from,
        chg => model($c, 'RegCharge')->find($chg_id),
        template => 'registration/edit_charge.tt2',
    );
}
sub charge_update_do : Local {
    my ($self, $c, $chg_id) = @_;

    my $chg = model($c, 'RegCharge')->find($chg_id);
    my $amount = trim($c->request->params->{amount});
    if (invalid_amount($amount)) {
        error($c,
            "Illegal amount: $amount",
            'gen_error.tt2',
        );
        return;
    }
    $chg->update({
        amount => $amount,
        what   => $c->request->params->{what},
    });
    _calc_balance($chg->registration());
    # ??? also update who, when
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
    system("grab");
    $c->response->redirect($c->uri_for("/registration/list_online"));
}

1;
