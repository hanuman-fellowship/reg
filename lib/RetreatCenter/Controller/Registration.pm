use strict;
use warnings;
package RetreatCenter::Controller::Registration;
use base 'Catalyst::Controller';

use DBIx::Class::ResultClass::HashRefInflator;      # ???

use lib '../../';       # so you can do a perl -c here.
use Date::Simple qw/
    date
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
/;
use POSIX qw/
    ceil
/;

    # damn awkward to keep this Global thing initialized... :(
    # is there no way to do this better???
use Global qw/
    %string
    %house_name_of
    %houses_in
    %houses_in_cluster
    $alert
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
    
    if ($dates{date_start}) {
        $dates{early} = 'yes';
    }
    else {
        $dates{early}      = '';
        $dates{date_start} = $pr->sdate;
    }
    my $edate = $pr->edate();
    my $edate2 = (date($pr->edate()) + $pr->extradays())->as_d8();
        # edate2 may be different in case this is an 'extended' program.
    if ($dates{date_end}
        && $dates{date_end} ne $edate
        && $dates{date_end} ne $edate2
    ) {
        $dates{late} = 'yes';
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
        my ($date, $time, $first, $last, $pid);
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
        }
        close $in;
        my $pr = model($c, 'Program')->find($pid);
        # what if not found??? see below.
        (my $fname = $f) =~ s{root/static/online/}{};
        push @online, {
            first => $first,
            last  => $last,
            pname => $pr? $pr->name
                    :     "Unknown Program",
            pid   => $pid,
            date  => $date,
            time  => $time,
            fname => $fname,
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

sub grab_new : Local {
    my ($self, $c) = @_;

    Global->init($c);
    my $ftp = Net::FTP->new($string{ftp_site}, Passive => $string{ftp_passive})
        or die "cannot connect to $string{ftp_site}";    # not die???
    $ftp->login($string{ftp_login}, $string{ftp_password})
        or die "cannot login ", $ftp->message; # not die???
    $ftp->cwd($string{ftp_transactions})
        or die "cannot cwd to $string{ftp_transactions} ", $ftp->message;
    $ftp->ascii();
    # don't do these mkdirs when things settle down???
    mkdir "root/static/online"      unless -d "root/static/online";
    mkdir "root/static/online_done" unless -d "root/static/online_done";

    for my $f ($ftp->ls()) {
        $ftp->get($f, "root/static/online/$f");
        $ftp->delete($f);
    }

    $ftp->quit();
    $c->response->redirect($c->uri_for("/registration/list_online"));
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
            order_by => [qw/ person.last person.first /],
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
    stash($c,
        online          => scalar(@files),
        pat             => $pat,
        daily_pic_date  => $pr->sdate(),
        cal_param       => $pr->sdate_obj->as_d8() . "/1",
        program         => $pr,
        regs            => _reg_table($c, \@regs),
        other_sort      => "list_reg_post",
        other_sort_name => "By Postmark",
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
    dphone
    ephone
    cphone
    ceu_license
    email
    house1
    house2
    cabinRoom
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
    open my $in, "<", "root/static/online/$fname"
        or die "cannot open root/static/online/$fname: $!";
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

    # save the filename so we can delete it when the registration is complete
    stash($c, fname => $fname);

    # verify that we have a pid, first, and last. and an amount.
    # ...???

    #
    # first, find the program
    # without it we can do nothing!
    #
    my ($pr) = model($c, 'Program')->find($P{pid});
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
            tel_home => $P{ephone},
            tel_work => $P{dphone},
            tel_cell => $P{cphone},
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
                if (digits($q->tel_cell) eq digits($P{cphone})) {
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
            tel_home => $P{ephone},
            tel_work => $P{dphone},
            tel_cell => $P{cphone},
            email    => $P{email},
            sex      => ($P{gender} eq 'Male'? 'M': 'F'),
            e_mailings     => $P{e_mailings},
            snail_mailings => $P{snail_mailings},
            share_mailings => $P{share_mailings},
            date_updat => $today,
        });
        my $person_id = $p->id;
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
        stash($c, date_end => "+" . $pr->extradays);
    }
    for my $how (qw/ ad web brochure flyer word_of_mouth /) {
        stash($c, "$how\_checked" => "");
    }
    # sdate/edate (in the hash from the online file)
    # are normally empty - except for personal retreats
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
        cabin_checked   => $P{cabinRoom} eq 'cabin'? "checked": "",
        room_checked    => $P{cabinRoom} eq 'room' ? "checked": "",
        adsource        => $P{advertiserName},
        carpool_checked => $P{carpool}? "checked": "",
        hascar_checked  => $P{hascar }? "checked": "",
        date_postmark   => $date->as_d8(),
        time_postmark   => $P{time},
        deposit         => int($P{amount}),
        deposit_type    => "Online",
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
    my ($pr, $p, $c, $today, $house1, $house2) = @_;

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
    #
    if (my $mem = $p->member) {
        my $status = $mem->category;
        if ($status eq 'Life'
            || ($status eq 'Sponsor' && $mem->date_sponsor >= $today)
                                    # member in good standing
        ) {
            stash($c, status => $status);    # they always get a 30%
                                             # tuition discount.
            my $nights = $mem->sponsor_nights;
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
    my $h_type_opts = "";
    my $h_type_opts2 = "";
    Global->init($c);     # get %string ready.
    HTYPE:
    for my $ht (housing_types(2)) {
        next HTYPE if $ht eq "single_bath" && ! $pr->sbath;
        next HTYPE if $ht eq "quad"        && ! $pr->quad;
        next HTYPE if $ht eq "economy"     && ! $pr->economy;
        if ($ht !~ m{unknown|not_needed} && $pr->housecost->$ht == 0) {
            next HTYPE;
        }

        my $selected = ($ht eq $house1 )? " selected": "";
        my $selected2 = ($ht eq $house2)? " selected": "";
        $h_type_opts .= "<option value=$ht$selected>$string{$ht}\n";
        $h_type_opts2 .= "<option value=$ht$selected2>$string{$ht}\n";
    }
    stash($c,
        program => $pr,
        person => $p,
        h_type_opts  => $h_type_opts,
        h_type_opts1 => $h_type_opts,
        h_type_opts2 => $h_type_opts2,
        confnotes    => [
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
    my $PR = ($prog->name =~ m{personal retreat}i);
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
$c->log->info("sd $sdate ed $edate pd $prog_days");
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
    %dates = transform_dates($pr, %dates);
    if ($dates{date_start} > $dates{date_end}) {
        error($c,
            "Start date is after the end date.",
            "registration/error.tt2",
        );
        return;
    }
    my $cabin_room = "";
    if ($P{cabin} && ! $P{room}) {
        $cabin_room = "cabin";
    }
    elsif (!$P{cabin} && $P{room}) {
        $cabin_room = "room";
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
        free_prog_taken => $P{free_prog},
        cancelled     => '',    # to be sure
        arrived       => '',    # ditto
        cabin_room    => $cabin_room,
        leader_assistant => '',
        pref1         => $P{pref1},
        pref2         => $P{pref2},
        share_first   => $P{share_first},
        share_last    => $P{share_last},
        %dates,         # optionally
    });
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
    model($c, 'RegPayment')->create({
        @who_now,
        amount  => $P{deposit},
        type    => $P{deposit_type},
        what    => 'Deposit',
    });

    # add the automatic charges
    _compute($c, $reg, @who_now);

    # notify those who want to know of each registration as it happens
    if ($pr->notify_on_reg) {
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
    if ($P{fname}) {
        rename "root/static/online/$P{fname}",
               "root/static/online_done/$P{fname}";
    }

    # finally, bump the reg_count in the program record
    $pr->update({
        reg_count => $pr->reg_count + 1,
    });
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
# WITHIN this routine.  this is the only place
# they are used.
#
sub _compute {
    my ($c, $reg, @who_now) = @_;

    Global->init($c);
    my $pr  = $reg->program;
    my $mem = $reg->person->member;

    # tuition
    my $tuition = $pr->tuition;
    if ($pr->extradays && $reg->date_end > $pr->edate) {
        # they need to pay the full tuition amount
        $tuition = $pr->full_tuition;
    }
    model($c, 'RegCharge')->create({
        @who_now,
        automatic => 'yes',
        amount    => $tuition,
        what      => 'Tuition',
    });

    # sponsor/life members get a discount on tuition
    # up to a max.
    if ($reg->status) {
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

    # assuming we have decided on their housing at this point...
    # we do have an h_type but perhaps not a housing_id.
    #
    # figure housing cost
    my $housecost = $pr->housecost;

    my $h_type = $reg->h_type;           # what housing type was assigned?
    my $lead_assist = $reg->leader_assistant;   # no housing charge
                                                # for these people
    my $h_cost = ($h_type eq 'not_needed'
                  || $h_type eq 'unknown')? 0
                 :                          $housecost->$h_type;
                                            # column name is correct, yes?
$c->log->info("$h_type hc $h_cost");
$c->log->info("pd $prog_days");
    my ($tot_h_cost, $what);
	if ($housecost->type eq "Per Day") {
		$tot_h_cost = $prog_days*$h_cost;
$c->log->info("thc $tot_h_cost");
        my $plural = ($prog_days == 1)? "": "s";
        $what = "$prog_days day$plural Lodging at \$$h_cost per day";
    }
    else {
        $tot_h_cost = int($h_cost * ($prog_days/$tot_prog_days));
$c->log->info("thc $tot_h_cost");
        $what = "Lodging - Total Cost";
        if ($prog_days != $tot_prog_days) {
            my $plural = ($prog_days == 1)? "": "s";
            $what .= " - $prog_days day$plural";
        }
    }
    if ($lead_assist) {
        $tot_h_cost = 0;
    }
$c->log->info("tot cost = $tot_h_cost");
    if ($tot_h_cost != 0) {
        model($c, 'RegCharge')->create({
            @who_now,
            automatic => 'yes',
            amount    => $tot_h_cost,
            what      => $what,
        });
    }

    # extra days - at the default housecost rate
    # but not for leaders/assistants???
    my $def_h_cost = 0;
    if ($extra_days && ! $lead_assist) {
        my ($def_housecost) = model($c, 'HouseCost')->search({
            name => 'Default',
        });
        $def_h_cost = ($h_type eq 'not_needed'
                       || $h_type eq 'unknown')? 0
                      :                          $def_housecost->$h_type;
                                                 # column name is correct, yes?
        $tot_h_cost += $extra_days*$def_h_cost;
        my $plural = ($extra_days == 1)? "": "s";
        if ($def_h_cost != 0) {
            model($c, 'RegCharge')->create({
                @who_now,
                automatic => 'yes',
                amount    => $extra_days*$def_h_cost,
                what      => "$extra_days day$plural Lodging"
                            ." at \$$def_h_cost per day",
            });
        }
    }

    my $life_free = 0;
    if ($reg->free_prog_taken && $tot_h_cost) {
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
            member_id  => $mem->id,
            num_nights => 0,
            action     => 4,        # take free program
            @who_now,
        });
    }
	if (!$life_free && !$lead_assist && $housecost->type eq "Per Day") {
        if ($prog_days + $extra_days >= $string{disc1days}) {
            model($c, 'RegCharge')->create({
                @who_now,
                automatic => 'yes',
                amount    => -1*(int(($string{disc1pct}/100)*$tot_h_cost)),
                what      => "$string{disc1pct}% Lodging discount for"
                            ." programs >= $string{disc1days} days",
            });
        }
        if ($prog_days + $extra_days >= $string{disc2days}) {
            model($c, 'RegCharge')->create({
                @who_now,
                automatic => 'yes',
                amount    => -1*(int(($string{disc2pct}/100)*$tot_h_cost)),
                what      => "$string{disc2pct}% Lodging discount for"
                            ." programs >= $string{disc2days} days",
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
	if (my $ntaken = $reg->nights_taken) {

        my @boxes = (
            [ $prog_days,  $h_cost     ],
            [ $extra_days, $def_h_cost ],
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
        # deduct these nights from the person's member record.
        #
        $mem->update({
            sponsor_nights => $mem->sponsor_nights - $ntaken,     # cool, eh?
        });
        #
        # and add a NightHist record to specify what happened
        #
        model($c, 'NightHist')->create({
            @who_now,
            member_id  => $mem->id,
            num_nights => $ntaken,
            action     => 2,    # take nights
        });
    }
   
    #
    # is there a minimum of $15 per day for lodging???
    # figure the kids cost from the initial UNdiscounted rate.
    # bringing your kids during your free program - they still pay.
    #
    if (my $kids = $reg->kids) {
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
    if ($reg->ceu_license) {
        model($c, 'RegCharge')->create({
            @who_now,
            automatic => 'yes',
            amount    => $string{ceu_lic_fee},
            what      => "CEU License fee",
        });
    }

    # calculate the balance, update the reg record
    my $balance = 0;
    for my $ch ($reg->charges) {
        $balance += $ch->amount;
    }
    for my $py ($reg->payments) {
        $balance -= $py->amount;
    }
    $reg->update({
        balance => $balance,
    });
    # phew!
}

#
# send a confirmation letter.
# fill in a template and send it off.
# use the template toolkit outside of the Catalyst mechanism.
# if there is a non-blank confnote
# create a ConfHistory record for this sending.
#
sub send_conf : Local {
    my ($self, $c, $id) = @_;

    my $reg = model($c, 'Registration')->find($id);
    my $pr = $reg->program;
    Global->init($c);
    my $htdesc = $string{$reg->h_type};
    $htdesc =~ s{\s*\(.*\)}{};           # don't need this
    $htdesc =~ s{Mount Madonna }{};      # ... Center Tent
    my $personal_retreat = $pr->title =~ m{personal\s*retreat}i;
    my $start = ($reg->date_start)? $reg->date_start_obj: $pr->sdate_obj;
    my @carpoolers = model($c, 'Registration')->search({
        program_id => $pr->id,
        carpool    => 'yes',
    });      # Join???
    @carpoolers = sort {
                      $a->person->zip_post cmp $b->person->zip_post
                  }
                  @carpoolers;
    my $stash = {
        user     => $c->user,
        person   => $reg->person,
        reg      => $reg,
        program  => $pr,
        personal_retreat => $personal_retreat,
        sunday   => $personal_retreat
                    && ($reg->date_start_obj->day_of_week() == 0),
        friday   => $start->day_of_week() == 6,
        today    => tt_today($c),
        deposit  => $reg->deposit,
        htdesc   => $htdesc,
        article  => ($htdesc =~ m{^[aeiou]}i)? 'an': 'a',
        carpoolers => \@carpoolers,
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
    # printed or sent.
    #
    _reg_hist($c, $id, "Confirmation Letter sent");
    $reg->update({
        letter_sent => 'yes',   # this duplicates the RegHistory record
                                # above but is much easier accessed.
    });
    #
    # if no email put letter to screen for printing and snail mailing.
    # ??? needs some help here...  what to do after printing?
    # just go back.  or have a bookmark to go somewhere???
    # can we print it automatically?  don't know. better to not to.
    #
    if (! $reg->person->email) {
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
    if ($prog->level() eq 'S') {
        my $dcm = dcm_registration($c, $reg->person->id());
        if (ref($dcm)) {
            $dcm_reg_id = $dcm->id();
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
            if (my ($reg) = model($c, 'Registration')->search({
                                person_id  => $person->id(),
                                program_id => $reg->program_id(),
                            })
            ) {
                my $id = $reg->id();
                $share = "<a href=/registration/view/$id>$share</a>";
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
    stash($c,
        online         => scalar(@files),
        share          => $share,
        non_pr         => $prog->name !~ m{personal retreat}i,
        daily_pic_date => $reg->date_start(),
        cal_param      => $reg->date_start_obj->as_d8() . "/1",
        cur_cluster    => ($reg->house_id)? $reg->house->cluster_id: 1,
        dcm_reg_id     => $dcm_reg_id,
        program        => $prog,
        template       => "registration/view.tt2",
    );
}

sub pay_balance : Local {
    my ($self, $c, $id, $from) = @_;

    my $reg = model($c, 'Registration')->find($id);
    stash($c,
        message  => payment_warning($c),
        from     => $from,
        reg      => $reg,
        template => "registration/pay_balance.tt2",
    );
}

sub pay_balance_do : Local {
    my ($self, $c, $id) = @_;

    my $reg = model($c, 'Registration')->find($id);
    my $amount = trim($c->request->params->{amount});
    my $type   = $c->request->params->{type};
    if ($amount !~ m{^\d+$}) {
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
    my @who_now = get_now($c, $id);
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
        $c->response->redirect($c->uri_for("/registration/list_reg_name/"
                               . $reg->program->id));
    }
    else {
        # $from eq 'view'
        # view registration again
        $c->response->redirect($c->uri_for("/registration/view/$id"));
    }
}

sub cancel : Local {
    my ($self, $c, $id) = @_;

    my $reg = model($c, 'Registration')->find($id);
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
    my ($self, $c, $id) = @_;

    my $credit    = $c->request->params->{yes};
    my $amount    = $c->request->params->{amount};
    my $reg       = model($c, 'Registration')->find($id);

    $reg->update({
        cancelled => 'yes',
    });

    # return any assigned housing to the pool
    _vacate($c, $reg) if $reg->house_id;

    # add reg history record
    _reg_hist($c, $id,
        "Cancelled - "
        .  (($credit)? "Credit of \$$amount given."
            :          "No credit given.")
    );

    # put back free nights/program
    my $taken = $reg->nights_taken;
    my $free  = $reg->free_prog_taken;
    if ($taken || $free) {
        my $mem = $reg->person->member();
        my @who_now = get_now($c, $id);
        if ($taken) {
            my $new_nights = $mem->sponsor_nights + $taken;
            $mem->update({
                sponsor_nights => $new_nights,
            });
            model($c, 'NightHist')->create({
                member_id  => $mem->id,
                num_nights => $new_nights,
                action     => 1,        # set nights
                @who_now,
            });
        }
        if ($free) {
            $mem->update({
                free_prog_taken => '',
            });
            model($c, 'NightHist')->create({
                member_id  => $mem->id,
                num_nights => 0,
                action     => 3,        # clear free program
                @who_now,
            });
        }
    }

    # give credit
    my $date_expire;
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

    # decrement the reg_count in the program record
    my $prog_id   = $reg->program_id;
    model($c, 'Program')->find($prog_id)->update({
        reg_count => \'reg_count - 1',
    });

    #
    # send cancellation confirmation letter
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
        $c->response->redirect($c->uri_for("/registration/view/$id"));
    }
    else {
        $c->res->output($html);
    }
}

#
# utility sub for adding RegHistory records
# takes care of getting the current user, date and time.
#
sub _reg_hist {
    my ($c, $id, $what) = @_;

    my $username = $c->user->username();
    my ($u) = model($c, 'User')->search({
        username => $username,
    });
    my $user_id = $u->id;
    my $now_date = tt_today($c)->as_d8();
    my $now_time = get_time()->t24();
    model($c, 'RegHistory')->create({
        reg_id => $id,
        what => $what,
        user_id  => $user_id,
        the_date => $now_date,
        time     => $now_time,
    });
}

sub new_charge : Local {
    my ($self, $c, $id) = @_;

    my $reg = model($c, 'Registration')->find($id);
    stash($c,
        reg      => $reg,
        template => "registration/new_charge.tt2",
    );
}
sub new_charge_do : Local {
    my ($self, $c, $id) = @_;

    my $amount = trim($c->request->params->{amount});
    my $what   = trim($c->request->params->{what});
    
    my @mess = ();
    if (empty($amount)) {
        push @mess, "Missing Amount";
    }
    if ($amount !~ m{^-?\d+$}) {
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
        reg_id    => $id,
        user_id   => $user_id,
        the_date  => $now_date,
        time      => $now_time,
        amount    => $amount,
        what      => $what,
        automatic => '',        # this charge will not be cleared
                                # when editing a registration.
    });
    my $reg = model($c, 'Registration')->find($id);
    $reg->update({
        balance => $reg->balance + $amount,
    });
    $c->response->redirect($c->uri_for("/registration/view/$id"));
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
            order_by => [qw/ person.last person.first /],
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
    my $proghead = "";
    if ($opt{multiple}) {
        $proghead = "<th align=left>Program</th>\n";
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
$posthead
</tr>
EOH
    my $body = "";
    for my $reg (@$reg_aref) {
        my $per = $reg->person;
        my $id = $reg->id;
        my $name = $per->last . ", " . $per->first;
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
                  :(!$reg->letter_sent)?
                       "<img src=/static/images/envelope.jpg height=$ht>"
                  :    "";
        if ($need_house && $hid) {
            # no height= since it pixelizes it :(
            if ($h_type ne $pref1 && $h_type ne $pref2) {
                $mark = "<img src=/static/images/unhappy2.gif>&nbsp;$mark";
            }
            elsif ($h_type ne $pref1) {
                $mark = "<img src=/static/images/unhappy1.gif>&nbsp;$mark";
            }
        }
        my $program_td = "";
        if ($opt{multiple}) {
            $program_td = "<td>" . $reg->program->name() . "</td>\n";
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
            && ($reg->program->school() == 0
                || $c->check_user_roles('mmi_admin'))
        ) {
            $pay_balance =
                "<a href='/registration/pay_balance/$id/list_reg_name'>"
               ."$pay_balance</a>";
        }
        if ($reg->program->school() == 0
            || $c->check_user_roles('mmi_admin')
        ) {
            $name = "<a href='/registration/view/$id'>$name</a>";
        }
        $body .= <<"EOH";
<tr>

$program_td
<td align=right>$mark</td>

<td>    <!-- width??? -->
$name
</td>

<td align=right>$pay_balance</td>
<td>$type</td>
<td>$house</td>
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
    $reg->update({
        confnote => cf_expand($c, $c->request->params->{confnote}),
    });
    _reg_hist($c, $id, "Confirmation Note updated.");
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
    _reg_hist($c, $id, "Comment updated.");
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
    my $mon       = $reg->date_start_obj->month();
    HTYPE:
    for my $htname (housing_types(2)) {
        next HTYPE if $htname eq "single_bath" && ! $pr->sbath;
        next HTYPE if $htname eq "quad"        && ! $pr->quad;
        next HTYPE if $htname eq "economy"     && ! $pr->economy;
        next HTYPE if    $htname ne "unknown"
                      && $htname ne "not_needed"
                      && $pr->housecost->$htname() == 0;     # wow!
        next HTYPE if $htname eq 'center_tent' && wintertime($mon);

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
            && (! $mem->free_prog_taken || $reg->free_prog_taken)
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
        carpool_checked => $reg->carpool()? "checked": "",
        hascar_checked  => $reg->hascar() ? "checked": "",
        cabin_checked   => $c_r eq 'cabin'? "checked": "",
        room_checked    => $c_r eq 'room' ? "checked": "",
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
# clear all automatic charges
# look carefully at any _changes_ in nights taken or free program
#   and adjust the member record in advance of the recomputation.
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
    model($c, 'RegCharge')->search({
        reg_id    => $id,
        automatic => 'yes',
    })->delete();

    my $reg = model($c, 'Registration')->find($id);
    my $pr  = model($c, 'Program'     )->find($reg->program_id);

    my @who_now = get_now($c, $id);

    my $mem = $reg->person->member;
    if ($reg->free_prog_taken && ! $P{free_prog}) {
        # they changed their mind about taking a free program
        # so clear it in the member area.  and add a NightHist record.
        $mem->update({
            free_prog_taken => '',
        });
        model($c, 'NightHist')->create({
            member_id  => $mem->id,
            reg_id     => $id,
            num_nights => 0,
            action     => 3,        # clear free program
            @who_now,
        });
    }
    my $taken_before = $reg->nights_taken();
    if ($taken_before && $taken_before != $taken) {
        # put the nights back so we can taken them again (or not).
        # add a NightHist record
        my $new_nights = $mem->sponsor_nights + $taken_before;
        $mem->update({
            sponsor_nights => $new_nights,
        });
        model($c, 'NightHist')->create({
            member_id  => $mem->id,
            reg_id     => $id,
            num_nights => $new_nights,
            action     => 1,        # set nights
            @who_now,
        });
    }

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
    my $cabin_room = "";
    if ($P{cabin} && ! $P{room}) {
        $cabin_room = "cabin";
    }
    elsif (!$P{cabin} && $P{room}) {
        $cabin_room = "room";
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
        confnote      => cf_expand($c, $c->request->params->{confnote}),
        nights_taken  => $taken,
        free_prog_taken => $P{free_prog},
        cabin_room    => $cabin_room,
        share_first   => $P{share_first},
        share_last    => $P{share_last},
        pref1         => $P{pref1},
        pref2         => $P{pref2},
        %dates,         # optionally
    });
    _compute($c, $reg, @who_now);
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
    _rest_of_reg($pr, $p, $c, tt_today($c), "dble", "dble");
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    my $reg = model($c, 'Registration')->find($id);
    my $person_id = $reg->person_id;
    my $prog_id   = $reg->program_id;

    _vacate($c, $reg) if $reg->house_id;
    $reg->delete();
    model($c, 'Program')->find($prog_id)->update({
        reg_count => \'reg_count - 1',
    });
    $c->response->redirect($c->uri_for("/person/view/$person_id"));
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
               } map {
                   my $p = $_->person;
                   {
                       id     => $_->id,
                       name   => $p->last . ", " . $p->first,
                       arrive => ($_->date_start eq $sdate)? ""
                                 :               $_->date_start_obj->format,
                       leave  => ($_->date_end eq $edate
                                  || $_->date_end eq $edate2)? ""
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

sub lodge : Local {
    my ($self, $c, $id) = @_;

    my $reg        = model($c, 'Registration')->find($id);
    my $pr         = $reg->program();
    my $program_id = $reg->program_id();

    #
    # housed with a friend who is also registered for this program?
    #
    my $share_house_id = 0;
    my $share_house_name = "";
    my $share_first = $reg->share_first();
    my $share_last  = $reg->share_last();
    my $name = "$share_first $share_last";
    my $message2 = "";
    if ($share_first) {
        my ($person) = model($c, 'Person')->search({
            first => $share_first,
            last  => $share_last,
        });
        if ($person) {
            my ($reg2) = model($c, 'Registration')->search({
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
                if ($reg2->house_id) {
                    if ($reg2->h_type eq $reg->h_type) {
                        $share_house_name = $reg2->house->name;
                        $share_house_id   = $reg2->house_id;
                        $message2 = "Share $share_house_name"
                                   ." with $share_first $share_last?";
                    }
                    else {
                        $message2 = "$name is housed in a '"
                                  . $reg2->h_type_disp
                                  . "' not '"
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
                }
            }
        }
    }
    my $sdate = $reg->date_start;
    my $edate1 = (date($reg->date_end) - 1)->as_d8();

    my $mon = $reg->date_start_obj->month();
    my $summer = 5 <= $mon && $mon <= 10;

    my $h_type = $reg->h_type;
    my $bath   = ($h_type =~ m{bath}  )? "yes": "";
    my $tent   = ($h_type =~ m{tent}  )? "yes": "";
    my $center = ($h_type =~ m{center})? "yes": "";
    my $psex   = $reg->person->sex;
    my $max    = type_max($h_type);
    my $cabin  = $reg->cabin_room eq 'cabin';
    my @kids   = ($reg->kids)? (cur => { '>', 0 })
                 :             ();

    my @h_opts = ();
    my $n = 0;
    my $selected = 0;

    #
    # which clusters (and in what order) have
    # been designated for this program?
    #
    PROGRAM_CLUSTER:
    for my $pc (model($c, 'ProgramCluster')->search(
                { program_id => $program_id },
                {
                    join     => 'cluster',
                    prefetch => 'cluster',
                    order_by => 'seq',
                }
               )
    ) {
        # Can we eliminate this entire cluster
        # due to the type of houses/sites in it?
        #
        # using the _name_ of the cluster
        # is not the best idea but hey ...
        # one _could_ put a tent and a room in the same cluster, right?
        #
        my $cl_name = $pc->cluster->name();
        my $cl_tent   = $cl_name =~ m{tent|terrace}i;
        my $cl_center = $cl_name =~ m{center}i;
        if (($tent && !$cl_tent) ||
            (!$tent && $cl_tent) ||
            ($summer && (!$center && $cl_center ||
                         $center && !$cl_center   ))
                # watch out for the word center
                # in indoor housing!
        ) {
            next PROGRAM_CLUSTER;
        }

        HOUSE:
        for my $h (@{$houses_in_cluster{$pc->cluster_id()}}) {
            # note no database access yet ... it is all in memory
            # is the max of the house inconsistent with $max?
            # or the bath status
            #
            if (($h->max < $max) ||
                ($h->bath && !$bath) ||
                (!$h->bath && $bath)
            ) {
                next HOUSE;
            }
            my $h_id = $h->id;
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
                    curmax => { '<', $max },    # too small
                    -and => [                   # can't resize - someone there
                        curmax => { '>', $max },
                        cur    => { '>', 0    },
                    ],
                    @kids,                      # kids => cur > 0
                ],
            });
            next HOUSE if @cf;        # nope

            # we have a good house.
            # no problematic config records were found.
            #
            # what are the attributes of the configuration records?
            #
            # P - perfect size - no further resize needed
            # O - occupied (but there is space for more)
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
                $code_sum += $string{house_sum_occupied};        # string
            }
            if ($F) {
                $codes .= "F";
                $code_sum -= 20;            # discourage this!
            }
            if ($P) {
                $code_sum += $string{house_sum_perfect_fit};     # string
            }
            else {
                $codes .= "R";      # resize needed - not as good...
            }
            if ($h->cabin) {
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
    }   # end of PROGRAM_CLUSTER
    #
    # and now the big sort:
    #
    @h_opts = map {
                    $_->[0]
                }
                sort {
                  $b->[1] <=> $a->[1] ||      # POC      - descending
                  $a->[2] <=> $b->[2]         # priority - ascending
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
    # enforce the max_lodge_opts
    # just truncate those beyond the stipulated max.
    #
    if (@h_opts > $string{max_lodge_opts}) {
        $#h_opts = $string{max_lodge_opts};
    }
    if ($share_house_id && ! $selected) {
        # male, female want to share
        # one of them is already housed.
        # the room is not in the list because of the gender mismatch
        # or a tent with nominally only one space.
        #
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
    if (@h_opts && ! $selected) {
        # no house is otherwise selected
        # insert a select into the first one.
        $h_opts[0] =~ s{>}{ selected>};
    }
    # include kids and housing prefs
    if (my @ages = $reg->kids() =~ m{(\d+)}g) {
        stash($c, kids => " with child" . ((@ages > 1)? "ren":""));
    }
    stash($c, house_prefs => "<br>Housing choices: "
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
        quad
        economy
        dormitory
        center_tent
        own_tent
        own_van
        commuting
    /) {
        next HTYPE if $htname eq "single_bath" && ! $pr->sbath;
        next HTYPE if $htname eq "quad"        && ! $pr->quad;
        next HTYPE if $htname eq "economy"     && ! $pr->economy;
        next HTYPE if $pr->housecost->$htname == 0;     # wow!
        next HTYPE if $htname eq 'center_tent' && !$summer;

        my $selected = ($htname eq $cur_htype)? " selected": "";
        my $htdesc = $string{$htname};
        $htdesc =~ s{\(.*\)}{};              # registrar doesn't need this
        $htdesc =~ s{Mount Madonna }{};      # ... Center Tent
        $h_type_opts .= "<option value=$htname$selected>$htdesc\n";
    }
    # hacky :(  how else please?
    $h_type_opts .= "<option value=unknown"
                 .  ($cur_htype eq "unknown"? " selected"
                     :                        ""         )
                 .  ">Unknown\n";
    $h_type_opts .= "<option value=not_needed"
                 .  ($cur_htype eq "not_needed"? " selected"
                     :                           ""         )
                 .  ">Not Needed\n";

    $h_type = _htrans($h_type);

    stash($c,
        reg           => $reg,
        note          => $cn,
        note_lines    => lines($cn) + 3,
        message2      => $message2,
        h_type        => $h_type,
        cal_param     => $reg->date_start_obj->as_d8() . "/1",
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
    my $new_htype = $c->request->params->{htype};
    if ($reg->h_type() ne $new_htype) {
        # the housing type was changed
        $reg->update({
            h_type => $new_htype,
        });
        # recompute the automatic charges since h_type changed
        model($c, 'RegCharge')->search({
            reg_id    => $id,
            automatic => 'yes',
        })->delete();
        my @who_now = get_now($c, $id);
        _compute($c, $reg, @who_now);

        if ($new_htype =~ m{^(own_van|commuting|unknown|not_needed)$}) {
                        # hash lookup instead?
            $c->response->redirect($c->uri_for("/registration/view/$id"));
            return;
        }
        # we need to search again with the new type
        lodge($self, $c, $id);
        # ??? another way of calling? with same params???
        return;
    }

    #
    # settle on exactly which house we're using.
    #
    my ($house_id) = $c->request->params->{house_id};
    my ($force_house) = trim($c->request->params->{force_house});
    if (! ($house_id || $force_house)) {
        $reg->update({
            confnote => cf_expand($c, $c->request->params->{confnote}),
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
    my $house_max = $house->max;

    my $sdate  = $reg->date_start;
    my $edate1 = (date($reg->date_end) - 1)->as_d8();
    my $psex = $reg->person->sex;
    my $cmax = type_max($reg->h_type);
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
    # so weird and so complicated.   jeez.
    #
    # if kids in this registration then we must set curmax = cur.
    # this will effectively resize the room so no one else
    # will be put there.
    #
    if ($force_house && $cmax > $house_max) {
        $cmax = $house_max;
    }
    if ($force_house) {
        # we need to verify that this forced house
        # is not plum full on some day.
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
                     . " on " . date($cf[0]->the_date)
                     . ".",
                "registration/error.tt2",
            );
            return;
        }
    }
    #
    # we have passed all the hurdles.
    #
    $reg->update({
        house_id => $house_id,
        h_name   => '',
        confnote => cf_expand($c, $c->request->params->{confnote}),
    });
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
            program_id => $reg->program_id,
        });
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
        # we might as well set the program id to 0.
        #
        # if we're not back to one should we see
        # if all involved are of the same sex?  nah.
        # let's leave a flaw in this - like Islamic art.
        #
        my @opts = ();
        if ($cf->cur() == 1) {
            push @opts,
                curmax     => $hmax,
                sex        =>   'U',
                program_id =>     0
                ;
        }
        if ($cf->cur == 2 && $cf->sex eq 'X') {
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
    }
    $reg->update({
        house_id => 0,
    });
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
            order_by => [qw/ person.last person.first /],
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
    my %note;
    for my $cf (model($c, 'ConfNote')->all()) {
        $note{$cf->abbr()} = etrim($cf->expansion());
    }
    $s =~ s{^(\S+)$}{ $note{$1} || $1 }gem;
    $s;
}

#
# via an AJAX call on the daily picture.
# who is in the room?
#
sub who_is_there : Local {
    my ($self, $c, $sex, $house_id, $the_date) = @_;

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
    # it must be one or more registrations
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
            order_by => [qw/ person.last person.first /],
        }
    );
    if (! @regs) {
        $c->res->output("Unknown");     # shouldn't happen
        return;
    }
    my $reg_names = "";
    for my $r (@regs) {
        my $rid = $r->id();
        my $pr = $r->program();
        my $name = $r->person->last() . ", " . $r->person->first();
        my $relodge = "";
        if ($pr->school() == 0 
            || $c->check_user_roles('mmi_admin')
        ) {
            $name = "<a target=happening href="
                  . $c->uri_for("/registration/view/$rid")
                  . ">"
                  . $name
                  . "</a>"
                  ;
            $relodge = "<td width=30 align=center><a target=happening href="
                     . $c->uri_for("/registration/relodge/$rid")
                     . "><img src=/static/images/move_arrow.gif border=0>"
                     . "</a></td>"
                     ;
        }
        $reg_names .= "<tr>"
                   . "<td>"
                   . $name
                   . _get_kids($r->kids())
                   . "<td><a target=happening href="
                   . $c->uri_for("/program/view/")
                   . $pr->id()
                   . ">"
                   . $pr->name()
                   . "</a></td>"
                   . "</td>"
                   . $relodge
                   . "</tr>";
    }
    $reg_names =~ s{'}{\\'}g;       # for O'Dwyer etc.
                                # can't use &apos; :( why?
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
my $containing;

sub _person_data {
    my ($i) = @_;

    if ($i >= $npeople) {
        return "";
    }
    my $p = $people[$i];
    if ($containing eq 'all') {
        return "<b>" . $p->last . ", " . $p->first . "</b><br>"
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
        return $p->last . ", " . $p->first . "<br>";
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

    my $p_order = $c->request->params->{order};
    my $order = ($p_order eq 'name')? [qw/ person.last person.first /]
                :                     [qw/ date_postmark time_postmark /];
    my (@regs) = model($c, 'Registration')->search(
        {
            program_id => $prog_id,
            cancelled  => '',
        },
        {
            join     => [qw/ person /],
            order_by => $order,
            prefetch => [qw/ person /],   
        }
    );
    # here we're only interested in the person information so...
    #
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
            $mailto = "<a href='mailto:?bcc=$mailto'>Email All</a><p>\n";
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

    for my $r (@regs) {
        ++$registered;
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
        if ($r->cancelled) {
            ++$cancelled;
            next;
        }
        if (! $r->arrived) {
            ++$no_shows;
            next;
        }
        ++$adults;
        if ($r->person->sex eq 'F') {
            ++$females;
        }
        else {
            ++$males;
        }
        if (my $k = $r->kids) {
            my @ages = $k =~ m{(\d+)}g;
            $kids += @ages;
        }
        # charges
        for my $rc ($r->charges()) {
            my $what   = $rc->what();
            my $amount = $rc->amount();
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
        $balance += $r->balance();
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
<tr><th align=left>Abbr</th><th align=left>Expansion</th></tr>
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
        my $sdate = $program->sdate_obj();
        my $m = $sdate->month();
        if ($h_type =~ m{tent} && wintertime($m)) {
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

1;
