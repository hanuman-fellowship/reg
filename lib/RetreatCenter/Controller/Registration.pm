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
    link_share
    normalize
/;
    # damn awkward to keep this Global thing initialized... :(
    # is there no way to do this better???
use Global qw/
    %string
    %house_name_of
    %houses_in
    %houses_in_cluster
/;
use Template;
use Mail::SendEasy;

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
    if ($dates{date_end}) {
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
                $date = date($1)->format("%m/%d");
            }
            elsif (m{x_time => (.*)}) {
                $time = $1;
            }
            elsif (m{x_fname => (.*)}) {
                $first = $1;
            }
            elsif (m{x_lname => (.*)}) {
                $last = $1;
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
            date  => $date,
            time  => $time,
            fname => $fname,
        };
    }
    @online = sort {
                  $a->{pname} cmp $b->{pname} or
                  $a->{date}  cmp $b->{date}  or
                  $a->{time}  cmp $b->{time}
              }
              @online;
    $c->stash->{online} = \@online;
    $c->stash->{template} = "registration/list_online.tt2";
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
    my ($self, $c, $prog_id, $all) = @_;

    my $pat = $c->request->params->{pat} || "";
    $pat = trim($pat);
    my ($pref_last, $pref_first);
    if ($pat =~ m{(\S+)\s+(\S+)}) {
        ($pref_last, $pref_first) = ($1, $2);
    }
    else {
        $pref_last = $pat;
        $pref_first = "";
    }
    $c->stash->{pat} = $pat;

    my $pr = model($c, 'Program')->find($prog_id);

#    my ($pr1) = model($c, 'Program')->search(
#        { id      => $prog_id },
#        { columns => [ qw/ name edate sdate /] }
#    );
#$c->log->info('=' x 50);
#$c->log->info("stuff = $pr1");
#$c->log->info('hi' . $pr1->name . $pr1->edate . $pr1->title);
#$c->log->info("pr = " . $pr);
#
#    my $href = $rs->find($prog_id, { columns => ['name', 'edate']});
#$c->log->info(Dumper($href));
#    my $href = $rs->find($prog_id);
#$c->log->info(Dumper($href));
#$c->log->info("=====> hashref $href->{name} and $href->{edate}");
#
#my $rs = $c->model('RetreatCenterDB::Program');
#RetreatCenterDB::Program->result_class('DBIx::Class::ResultClass::HashRefInflator');
#my $row = $rs->search(
#    { id      => $prog_id },
#    { columns => [ qw/ name edate sdate /] }
#);
#my $href = $row->next();
#my $href = $c->model('RetreatCenterDB::Program')->storage->dbh_do(
#    sub {
#        my ($storage, $dbh, $prog_id, @cols) = @_;
#        my $cols = join(q{, }, @cols);
#        $dbh->selectrow_hashref(
#            "SELECT $cols FROM program where id = $prog_id");
#    },
#    $prog_id, qw/ name edate sdate /
#);
#use Data::Dumper;
#$c->log->info("=====> " . Dumper(\$href));

    $c->stash->{daily_pic_date} = $pr->sdate();
    $c->stash->{program} = $pr;
    # ??? dup'ed code in matchreg and list_reg_name
    # DRY??? don't repeat yourself!
    my @name_match = ();
    my @all = ();
    if ($pref_last) {
        push @name_match, 'person.last' => { like => "$pref_last%"  };
    }
    if ($pref_first) {
        push @name_match, 'person.first' => { like => "$pref_first%" };
    }
    if (!($all || @name_match)) {
        @all = (
            -or => [
                arrived => '',
                balance => { '>', 0 },
            ],
            cancelled => '',
        );
    }
    my @regs = model($c, 'Registration')->search(
        {
            program_id     => $prog_id,
            @name_match,
            @all,
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
        if ($r->date_start <= today()->as_d8()
            && $r->balance > 0
            && ! $r->cancelled
        ) {
            $c->response->redirect($c->uri_for("/registration/pay_balance/" .
                                   $regs[0]->id . "/list_reg_name"));
        }
        else {
            $c->response->redirect($c->uri_for("/registration/view/" .
                                   $regs[0]->id));
        }
        return;
    }
    Global->init($c);
    $c->stash->{regs} = _reg_table(\@regs);
    $c->stash->{other_sort} = "list_reg_post";
    $c->stash->{other_sort_name} = "By Postmark";
    my @files = <root/static/online/*>;
    $c->stash->{online} = scalar(@files);
    $c->stash->{template} = "registration/list_reg.tt2";
}

sub list_reg_post : Local {
    my ($self, $c, $prog_id) = @_;

    my $pr = model($c, 'Program')->find($prog_id);
    $c->stash->{program} = $pr;
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
    $c->stash->{regs} = _reg_table(\@regs, 1);
    $c->stash->{other_sort} = "list_reg_name";
    $c->stash->{other_sort_name} = "By Name";
    my @files = <root/static/online/*>;
    $c->stash->{online} = scalar(@files);
    $c->stash->{template} = "registration/list_reg.tt2";
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
    withWhom
/;

#
# an online registration via a file
#
sub get_online : Local {
    my ($self, $c, $fname) = @_;
    
    #
    # first extract all information from the file.
    #
    my %hash;
    open my $in, "<", "root/static/online/$fname"
        or die "cannot open root/static/online/$fname: $!";
    while (<$in>) {
        chomp;
        my ($key, $value) = m{^x_(\w+) => (.*)$};
        next unless $key;
        if ($needed{$key}) {
            $hash{$key} = $value;
        }
        elsif ($key =~ m{^request\d+}) {
            $hash{request} .= "$value\n";
        }
    }
    close $in;

    # save the filename so we can delete it when the registration is complete
    $c->stash->{fname} = $fname;

    # verify that we have a pid, first, and last. and an amount.
    # ...

    #
    # first, find the program
    # without it we can do nothing!
    #
    my ($pr) = model($c, 'Program')->find($hash{pid});
    if (! $pr) {
        $c->stash->{mess} = "Unknown Program - cannot proceed";
        $c->stash->{template} = "registration/error.tt2";
        return;
    }

    #
    # find or create a person object.
    #
    my @ppl = ();
    (@ppl) = model($c, 'Person')->search(
        {
            first => $hash{fname},
            last  => $hash{lname},
        },
    );
    my $p;
    my $today = today()->as_d8();
    if (! @ppl || @ppl == 0) {
        #
        # no match so create a new person
        # check for misspellings first???
        # do an akey search, pop up list???
        # or cell phone search???
        #
        $p = model($c, 'Person')->create({
            first    => $hash{fname},
            last     => $hash{lname},
            addr1    => $hash{street1},
            addr2    => $hash{street2},
            city     => $hash{city},
            st_prov  => $hash{state},
            zip_post => $hash{zip},
            country  => $hash{country},
            akey     => nsquish($hash{street1}, $hash{street2}, $hash{zip}),
            tel_home => $hash{ephone},
            tel_work => $hash{dphone},
            tel_cell => $hash{cphone},
            email    => $hash{email},
            sex      => ($hash{gender} eq 'Male'? 'M': 'F'),
            id_sps   => 0,
            e_mailings     => $hash{e_mailings},
            snail_mailings => $hash{snail_mailings},
            share_mailings => $hash{share_mailings},
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
                if (digits($q->tel_cell) eq digits($hash{cphone})) {
                    $p = $q;
                }
            }
            if (!$p) {
                for my $q (@ppl) {
                    if ($q->zip_post eq $hash{zip}) {
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
            addr1    => $hash{street1},
            addr2    => $hash{street2},
            city     => $hash{city},
            st_prov  => $hash{state},
            zip_post => $hash{zip},
            country  => $hash{country},
            akey     => nsquish($hash{street1}, $hash{street2}, $hash{zip}),
            tel_home => $hash{ephone},
            tel_work => $hash{dphone},
            tel_cell => $hash{cphone},
            email    => $hash{email},
            sex      => ($hash{gender} eq 'Male'? 'M': 'F'),
            e_mailings     => $hash{e_mailings},
            snail_mailings => $hash{snail_mailings},
            share_mailings => $hash{share_mailings},
            date_updat => $today,
        });
        my $person_id = $p->id;
    }

    #
    # various fields from the online file make their way
    # into the stash...

    # comments
    $c->stash->{comment} = <<"EOC";
1-$hash{house1}  2-$hash{house2}  $hash{cabinRoom}  online
EOC
    if ($hash{withWhom}) {
        $c->stash->{comment} .= "Sharing a room with $hash{withWhom}\n";
    }
    if ($hash{request}) {
        $c->stash->{comment} .= $hash{request};
    }

    for my $how (qw/ ad web brochure flyer word_of_mouth /) {
        $c->stash->{"$how\_checked"} = "";
    }
    $c->stash->{"$hash{howHeard}_checked"} = "selected";

    $c->stash->{adsource} = $hash{advertiserName};

    $c->stash->{carpool_checked} = $hash{carpool}? "checked": "";
    $c->stash->{hascar_checked}  = $hash{hascar }? "checked": "";

    # various hidden fields - to pass to create_do().
    my $date = date($hash{date});
    $c->stash->{date_postmark} = $date->as_d8();
    $c->stash->{time_postmark} = $hash{time};
    $c->stash->{deposit} = int($hash{amount});
    $c->stash->{deposit_type} = "Online";

    #
    # date_start and date_end are always present in the table record.
    # they are the program start/end dates unless overridden.
    # in the stash and on the screen they are blank if they
    # are the same as the program start/end dates.
    #
    # early and late are set accordingly when writing to
    # the database.
    #

    # sdate/edate (in the hash from the online file)
    # are normally empty - except for personal retreats
    if ($hash{sdate}) {
        $c->stash->{date_start} = date($hash{sdate});
    }
    if ($hash{edate}) {
        $c->stash->{date_end} = date($hash{edate});
    }

    # put the license # in the hash, we'll set ceu = 1 later.
    $c->stash->{ceu_license} = $hash{ceu_license};

    rest_of_reg($pr, $p, $c, $today, $hash{house1});
}

#
# the stash is partially filled in (from an online or manual reg).
# fill in the rest of it by looking at the program and person
# and render the view.
#
sub rest_of_reg {
    my ($pr, $p, $c, $today, $house1) = @_;

    $c->stash->{program} = $pr;
    $c->stash->{person} = $p;

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
    for my $a ($p->affils) {
        if ($a->descrip =~ m{pop up}i) {
            my $s = $p->comment;
            $s =~ s{\r?\n}{\\n}g;
            $c->stash->{popup_comment} = $s;
            last;
        }
    }
    #
    # life member or current sponsor?  with nights left?
    # they must be in good standing if sponsor
    # and can't take free nights if the housing cost is not a Perday type.
    #
    if (my $mem = $p->member) {
        my $status = $mem->category;
        if ($status eq 'Life'
            || ($status eq 'Sponsor' && $mem->date_sponsor >= $today)
                                    # member in good standing
        ) {
            $c->stash->{status} = $status;   # they always get a 30%
                                             # tuition discount.
            my $nights = $mem->sponsor_nights;
            if ($pr->housecost->type eq 'Perday' && $nights > 0) {
                $c->stash->{nights} = $nights;
            }
            if ($status eq 'Life' && ! $mem->free_prog_taken) {
                $c->stash->{free_prog} = 1;
            }
        }
    }

    # any credits?
    if ($p->credits()) {
        CREDIT:
        for my $cr ($p->credits()) {
            if (! $cr->date_used && $cr->date_expires > $today) {
                $c->stash->{credit} = $cr;
                last CREDIT;
            }
        }
    }

    if ($pr->footnotes =~ m{[*]}) {
        $c->stash->{ceu} = 1;
    }
    # the housing select list.
    # default is the first housing choice.
    # lots of names for the house type... :(
    # these are also the method and column names
    my %h_type = qw(
        com    commuting
        ov     own_van
        ot     own_tent
        ct     center_tent
        dorm   dormitory
        econ   economy
        quad   quad
        tpl    triple
        dbl    dble
        dbl/ba dble_bath
        sgl    single
        sgl/ba single_bath
    );
    # order is important:
    my $h_type_opts = "<option value=unknown>Unknown\n";
    Global->init($c);     # get %string ready.
    HTYPE:
    for my $ht (qw(
        com
        ov
        ot
        ct
        dorm
        econ
        quad
        tpl
        dbl
        dbl/ba
        sgl
        sgl/ba
    )) {
        next HTYPE if $ht eq "sgl/ba" && ! $pr->sbath;
        next HTYPE if $ht eq "quad"   && ! $pr->quad;
        next HTYPE if $ht eq "econ"   && ! $pr->economy;
        # also ...
        my $htname = $h_type{$ht};
        next HTYPE if $pr->housecost->$htname == 0;     # wow!

        my $selected = ($ht eq $house1)? " selected": "";
        my $htdesc = $string{$htname};
        $htdesc =~ s{\(.*\)}{};              # registrar doesn't need this
        $htdesc =~ s{Mount Madonna }{};      # ... Center Tent
        $h_type_opts .= "<option value=$htname$selected>$htdesc\n";
    }
    $c->stash->{h_type_opts} = $h_type_opts;
    $c->stash->{confnotes} = [
        model($c, 'ConfNote')->search(undef, { order_by => 'abbr' })
    ];

    $c->stash->{template} = "registration/create.tt2";
}

my @mess;
my %hash;
my %dates;
my $taken;
my $tot_prog_days;
my $prog_days;
my $extra_days;

sub _get_data {
    my ($c) = @_;

    %hash = %{ $c->request->params() };
    my $pr = model($c, 'Program')->find($hash{program_id});

    # BIG TIME messing with dates.
    # I'm reminded of a saying:
    #
    #    "If you have a date in your program
    #     you have a bug in your program."
    #
    %dates = ();
    @mess = ();
    $extra_days = 0;
    my $sdate = date($pr->sdate);       # personal retreats???
    my $edate = date($pr->edate);       # defaults to today???
    $tot_prog_days = $prog_days = $edate - $sdate;

    my $date_start;
    if ($hash{date_start}) {
        # what about personal retreats???
        Date::Simple->relative_date(date($pr->sdate));
        $date_start = date($hash{date_start});
        Date::Simple->relative_date();
        if ($date_start) {
            $dates{date_start} = $date_start->as_d8();
            if ($date_start < $sdate) {
                $extra_days += $sdate - $date_start;
            }
            else {
                $prog_days -= $date_start - $sdate;     # jeeez
            }
        }
        else {
            push @mess, "Illegal date: $hash{date_start}";
        }
    }
    else {
        $dates{date_start} = '';
    }
    my $date_end;
    if ($hash{date_end}) {
        # when scheduling a personal retreat
        # the "To Date" is relative to the start date
        # not the end of the program!   ??? in doc, please.
        Date::Simple->relative_date(
            ($pr->name =~ m{personal retreat}i)? $date_start
            :                                    date($pr->edate)
        );
        $date_end = date($hash{date_end});
        Date::Simple->relative_date();
        if ($date_end) {
            $dates{date_end} = $date_end->as_d8();
            if ($date_end > $edate) {
                $extra_days += $date_end - $edate;
            }
            else {
                $prog_days -= $edate - $date_end;
            }
        }
        else {
            push @mess, "Illegal date: $hash{date_end}";
        }
    }
    else {
        $dates{date_end} = '';
    }

    $taken = 0;
    if ($hash{nights_taken} && ! empty($hash{nights_taken})) {
        $taken = trim($hash{nights_taken});
        if ($taken !~ m{^\d+$}) {
            push @mess, "Illegal free nights taken: $taken.";
        }
        elsif ($taken > $hash{max_nights}) {
            push @mess, "Cannot take more than $hash{max_nights} free nights.";
        }
        elsif ($taken && $hash{free_prog}) {
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
        the_date => today()->as_d8(),
        time     => sprintf "%02d:%02d", (localtime())[2, 1];
    # we return an array of 8 values perfect
    # for passing to a DBI insert/update.
}

# now we actually create the registration
# if from an online source there will be a filename
# in the hash which needs deleting.
#
sub create_do : Local {
    my ($self, $c) = @_;

    _get_data($c);
    if (@mess) {
        $c->stash->{mess} = join "<br>", @mess;
        $c->stash->{template} = "registration/error.tt2";
        return;
    }
    my $pr = model($c, 'Program')->find($hash{program_id});
    %dates = transform_dates($pr, %dates);
    if ($dates{date_start} > $dates{date_end}) {
        $c->stash->{mess} = "Start date is after the end date.";
        $c->stash->{template} = "registration/error.tt2";
        return;
    }
    my $reg = model($c, 'Registration')->create({
        person_id     => $hash{person_id},
        program_id    => $hash{program_id},
        deposit       => $hash{deposit},
        date_postmark => $hash{date_postmark},
        time_postmark => $hash{time_postmark},
        ceu_license   => $hash{ceu_license},
        referral      => $hash{referral},
        adsource      => $hash{adsource},
        carpool       => $hash{carpool},
        hascar        => $hash{hascar},
        comment       => $hash{comment},
        h_type        => $hash{h_type},
        h_name        => $hash{h_name},
        kids          => $hash{kids},
        confnote      => _expand($c, $c->request->params->{confnote}),
        status        => $hash{status},
        nights_taken  => $taken,
        free_prog_taken => $hash{free_prog},
        cancelled     => '',    # to be sure
        arrived       => '',    # ditto
        %dates,         # optionally
    });
    my $reg_id = $reg->id();

    # prepare for history records
    my @who_now = get_now($c, $reg_id);

    # first, we have some PAST history
    model($c, 'RegHistory')->create({
        reg_id   => $reg_id,
        user_id  => $c->user->obj->id,
        the_date => $hash{date_postmark},
        time     => $hash{time_postmark},
        what     => ($hash{fname}? 'Online Registration'
                    :              'Manual Registration'),
    });

    # now current history
    model($c, 'RegHistory')->create({
        @who_now,
        what    => 'Registration Created',
    });

    # credit, if any
    if ($hash{credit_id}) {
        my $cr = model($c, 'Credit')->find($hash{credit_id});
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
            date_used   => today()->as_d8(),
            used_reg_id => $reg_id,
        });
    }
    # the payment (deposit)
    model($c, 'RegPayment')->create({
        @who_now,
        amount  => $hash{deposit},
        type    => $hash{deposit_type},
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
               html       => $html, 
               subject    => "Notification of Registration for " . $pr->title,
               to         => $pr->notify_on_reg,
               from       => $string{from},
               from_title => $string{from_title},
        );
        model($c, 'RegHistory')->create({
            @who_now,
            what    => 'On Register Notification Sent',
        });
    }

    # if this registration was from an online file
    # move it aside.  we have finished processing it at this point.
    if ($hash{fname}) {
        rename "root/static/online/$hash{fname}",
               "root/static/online_done/$hash{fname}";
    }

    # finally, bump the reg_count in the program record
    $pr->update({
        #reg_count => \'reg_count + 1',      # tricky??? unneeded
        reg_count => $pr->reg_count + 1,
    });
    $c->response->redirect($c->uri_for("/registration/"
        . (($reg->h_type =~ m{van|commut|unk})? "view"
           :                                    "lodge")
    . "/$reg_id"));
}

#
# automatic charges - computed from the contents
# of the registration record.
#
sub _compute {
    my ($c, $reg, @who_now) = @_;

    Global->init($c);
    my $pr  = $reg->program;
    my $mem = $reg->person->member;

    # tuition
    my $tuition = $pr->tuition;
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
    # we do have an h_type but perhaps not an h_name.
    #
    # figure housing cost
    my $housecost = $pr->housecost;

    my $h_type = $reg->h_type;           # what housing type was assigned?
    my $h_cost = $housecost->$h_type;      # column name is correct, yes?
    my ($tot_h_cost, $what);
	if ($housecost->type eq "Perday") {
		$tot_h_cost = $prog_days*$h_cost;
        my $plural = ($prog_days == 1)? "": "s";
        $what = "$prog_days day$plural Lodging at \$$h_cost per day";
    }
    else {
        $tot_h_cost = int($h_cost * ($prog_days/$tot_prog_days));
        $what = "Lodging - Total Cost";
        if ($prog_days != $tot_prog_days) {
            my $plural = ($prog_days == 1)? "": "s";
            $what .= " - $prog_days day$plural";
        }
    }
    if ($tot_h_cost != 0) {
        model($c, 'RegCharge')->create({
            @who_now,
            automatic => 'yes',
            amount    => $tot_h_cost,
            what      => $what,
        });
    }

    # extra days - at the default housecost rate
    my $def_h_cost = 0;
    if ($extra_days) {
        my ($def_housecost) = model($c, 'HouseCost')->search({
            name => 'Default',
        });
        $def_h_cost = $def_housecost->$h_type;
        $tot_h_cost += $extra_days*$def_h_cost;
        my $plural = ($extra_days == 1)? "": "s";
        model($c, 'RegCharge')->create({
            @who_now,
            automatic => 'yes',
            amount    => $extra_days*$def_h_cost,
            what      => "$extra_days day$plural Lodging"
                        ." at \$$def_h_cost per day",
        });
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
	if (!$life_free && $housecost->type eq "Perday") {
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
        today    => today(),
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
           html       => $html, 
           subject    => "Confirmation of Registration for " . $pr->title,
           to         => $reg->person->email,
           from       => $string{from},
           from_title => $string{from_title},
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

    my $reg = $c->stash->{reg} = model($c, 'Registration')->find($reg_id);
    my $prog = $c->stash->{program} = $reg->program;
    $c->stash->{comment} = link_share($c, $prog->id(), $reg->comment());
    if ($prog->footnotes =~ m{[*]}) {
        $c->stash->{ceu} = 1;
    }
    $c->stash->{non_pr} = $prog->name !~ m{personal retreat}i;
    $c->stash->{daily_pic_date} = $reg->date_start();
    my @files = <root/static/online/*>;
    $c->stash->{online} = scalar(@files);
    $c->stash->{template} = "registration/view.tt2";
}

sub pay_balance : Local {
    my ($self, $c, $id, $from) = @_;

    my $reg = model($c, 'Registration')->find($id);
    $c->stash->{from} = $from;
    $c->stash->{reg} = $reg;
    $c->stash->{template} = "registration/pay_balance.tt2";
}

sub pay_balance_do : Local {
    my ($self, $c, $id) = @_;

    my $reg = model($c, 'Registration')->find($id);
    my $amount = $c->request->params->{amount};
    my $type   = $c->request->params->{type};
    if ($amount !~ m{^\s*\d+\s*$}) {
        $c->stash->{mess} = "Illegal amount: $amount";
        $c->stash->{template} = "registration/error.tt2";
        return;
    }
    my $balance = $reg->balance;
    if ($amount > $balance) {
        $c->stash->{mess} = "Payment is more than the balance of $balance.";
        $c->stash->{template} = "registration/error.tt2";
        return;
    }
    my @who_now = get_now($c, $id);
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
    $c->stash->{reg} = $reg;
    my $today = today();
    $c->stash->{today} = $today;
    $c->stash->{ndays} = $reg->program->sdate_obj - $today;
    Global->init($c);
    $c->stash->{amount} = $string{credit_amount};
    $c->stash->{template} = "registration/credit_confirm.tt2";
}

sub cancel_do : Local {
    my ($self, $c, $id) = @_;

    my $credit    = $c->request->params->{yes};
    my $amount    = $c->request->params->{amount};
    my $reg       = model($c, 'Registration')->find($id);
    $reg->update({
        cancelled => 'yes',
    });

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
            date_given   => today->as_d8(),
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
        today       => today(),
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
            html    => $html, 
            subject => "Cancellation of Registration for "
                      . $reg->program->title,
            to      => $reg->person->email,
            from    => $string{from},
            from_title => $string{from_title},
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
    my $now_date = today()->as_d8();
    my ($hour, $min) = (localtime())[2, 1];
    my $now_time = sprintf "%02d:%02d", $hour, $min;
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

    $c->stash->{reg} = model($c, 'Registration')->find($id);
    $c->stash->{template} = "registration/new_charge.tt2";
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
        $c->stash->{mess} = join "<br>", @mess;
        $c->stash->{template} = "registration/error.tt2";
        return;
    }

    my $username = $c->user->username();
    my ($u) = model($c, 'User')->search({
        username => $username,
    });
    my $user_id = $u->id;

    my $today = today();
    my $now_date = $today->as_d8();
    my ($hour, $min) = (localtime())[2, 1];
    my $now_time = sprintf "%02d:%02d", $hour, $min;

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
    my @all = ();
    if ($pref_last) {
        push @name_match, 'person.last' => { like => "$pref_last%"  };
    }
    if ($pref_first) {
        push @name_match, 'person.first' => { like => "$pref_first%" };
    }
    if (! @name_match) {
        @all = (
            cancelled      => '',
            -or => [
                arrived        => '',
                balance => { '>', 0 },
            ]
        );
    }
    my @regs = model($c, 'Registration')->search(
        {
            program_id     => $prog_id,
            @name_match,
            @all,
        },
        {
            join     => [qw/ person /],
            order_by => [qw/ person.last person.first /],
            prefetch => [qw/ person /],   
        }
    );
    Global->init($c);
    $c->res->output(_reg_table(\@regs));
}

#
# if only one - make it larger - for fun.
# this is not used if we go there directly, yes???
#
sub _reg_table {
    my ($reg_aref, $postmark) = @_;
    my $size = 12;
    my $color = "#33a";
    my $other_color = "#fff";
    if (scalar(@$reg_aref) == 1) {
        $size = 18;
        $color = "red";
        $other_color = "#fff";
    }
    my $posthead = "";
    if ($postmark) {
        $posthead = <<"EOH";
<th align=center>Postmark</th>
EOH
    }
    my $heading = <<"EOH";
<tr>
<td></td>
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
        my $balance = $reg->balance;
        my $type = $reg->h_type_disp;
        my $need_house = (defined $type)? $type !~ m{commut|van|unk}i
                         :                0;
        my $hid = $reg->house_id;
        my $house = ($reg->h_name)? "(" . $reg->h_name . ")"
                   :($hid        )? $house_name_of{$hid}
                   :                "";
        my $date = date($reg->date_postmark);
        my $time = $reg->time_postmark;
        my $mark =         ($reg->cancelled)? 'X'
                  :   ($need_house && !$hid)? 'H'
                  :     (!$reg->letter_sent)? 'L'
                  :                           '&nbsp;';
        if (length($mark) == 1) {
            $mark = "<span class=required>$mark</span>";
        }
        my $postrow = "";
        if ($postmark) {
            $postrow = <<"EOH";
<td>
<span class=rname2>$date&nbsp;&nbsp;$time</span>
</td>
EOH
        }
        my $pay_balance = $balance;
        if (! $reg->cancelled && $balance > 0) {
            $pay_balance =
                "<span class=rname1><a href='/registration/pay_balance/$id/list_reg_name'>"
               ."$pay_balance</a></span>";
        }
        $body .= <<"EOH";
<tr>

<td>$mark</td>

<td>    <!-- width??? -->
<span class=rname1><a href='/registration/view/$id'>$name</a></span></a>
</td>

<td align=right>
$pay_balance
</td>

<td>
<span class=rname2>$type</span>
</td>

<td>
<span class=rname2>$house</span>
</td>

$postrow

</tr>
EOH
    }
    $body ||= "";
<<"EOH";        # returning a bare string heredoc constant?  sure.
<style>
.rname1 {
    font-size: ${size}pt;
    color: $color;
    background: $other_color;
}
.rname2 {
    font-size: ${size}pt;
}
a:hover {
    color: $other_color;
    background: $color;
}
</style>
<table cellpadding=4>
$heading
$body
</table>
EOH
}

sub update_confnote : Local {
    my ($self, $c, $id) = @_;

    my $reg = $c->stash->{reg} = model($c, 'Registration')->find($id);
    my $cn = $c->stash->{note} = $reg->confnote();
    $c->stash->{note_lines} = lines($cn) + 3;
    $c->stash->{confnotes} = [
        model($c, 'ConfNote')->search(undef, { order_by => 'abbr' })
    ];
    $c->stash->{template} = "registration/confnote.tt2";
}
sub update_confnote_do : Local{
    my ($self, $c, $id) = @_;

    my $reg = model($c, 'Registration')->find($id);
    $reg->update({
        confnote => _expand($c, $c->request->params->{confnote}),
    });
    _reg_hist($c, $id, "Confirmation Note updated.");
    $c->response->redirect($c->uri_for("/registration/view/$id"));
}
sub update_comment : Local {
    my ($self, $c, $id) = @_;

    my $reg = $c->stash->{reg} = model($c, 'Registration')->find($id);
    my $comment = $c->stash->{comment} = $reg->comment();
    $c->stash->{comment_lines} = lines($comment) + 3;
    $c->stash->{template} = "registration/comment.tt2";
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
    $c->stash->{reg} = $reg;
    $c->stash->{person} = $reg->person;
    my $pr = $c->stash->{program} = $reg->program;
    for my $ref (qw/ad web brochure flyer word_of_mouth/) {
        $c->stash->{"$ref\_selected"} = ($reg->referral eq $ref)? "selected"
                                       :                          "";
    }
    if ($pr->footnotes =~ m{[*]}) {
        $c->stash->{ceu} = 1;
    }
    my $h_type_opts = "<option value=unknown>Unknown\n";
    Global->init($c);     # get %string ready.
    HTYPE:
    for my $htname (qw(
        commuting
        own_van
        own_tent
        center_tent
        dormitory
        economy
        quad
        triple
        dble
        dble_bath
        single
        single_bath
    )) {
        next HTYPE if $htname eq "single_bath" && ! $pr->sbath;
        next HTYPE if $htname eq "quad"        && ! $pr->quad;
        next HTYPE if $htname eq "economy"     && ! $pr->economy;
        next HTYPE if $pr->housecost->$htname == 0;     # wow!

        my $selected = ($htname eq $reg->h_type)? " selected": "";
        my $htdesc = $string{$htname};
        $htdesc =~ s{\(.*\)}{};              # registrar doesn't need this
        $htdesc =~ s{Mount Madonna }{};      # ... Center Tent
        $h_type_opts .= "<option value=$htname$selected>$htdesc\n";
    }
    $c->stash->{h_type_opts} = $h_type_opts;

    my $status = $reg->status;      # status at time of first registration
    if ($status) {
        my $mem = $reg->person->member;
        my $nights = $mem->sponsor_nights + $reg->nights_taken;
        if ($pr->housecost->type eq 'Perday' && $nights > 0) {
            $c->stash->{nights} = $nights;
        }
        if ($status eq 'Life'
            && (! $mem->free_prog_taken || $reg->free_prog_taken)
        ) {
            $c->stash->{free_prog} = 1;
        }
    }
    $c->stash->{note_lines}    = lines($reg->confnote()) + 3;
    $c->stash->{comment_lines} = lines($reg->comment ()) + 3;
    $c->stash->{confnotes} = [
        model($c, 'ConfNote')->search(undef, { order_by => 'abbr' })
    ];
    $c->stash->{template} = "registration/edit.tt2";
}

sub conf_history : Local {
    my ($self, $c, $id) = @_;

    $c->stash->{reg} = model($c, 'Registration')->find($id);
    $c->stash->{template} = "registration/conf_hist.tt2";
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
        $c->stash->{mess} = join "<br>", @mess;
        $c->stash->{template} = "registration/error.tt2";
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
    if ($reg->free_prog_taken && ! $hash{free_prog}) {
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
        $c->stash->{mess} = "Start date is after the end date.";
        $c->stash->{template} = "registration/error.tt2";
        return;
    }
    if ($reg->house_id()
        && (($hash{h_type} ne $reg->h_type())
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
        $c->stash->{message1} = "Vacated " . $reg->house->name . ".";
                                    # see lodge.tt2 
        _vacate($c, $reg);
    }
    $reg->update({
        ceu_license   => $hash{ceu_license},
        referral      => $hash{referral},
        adsource      => $hash{adsource},
        carpool       => $hash{carpool},
        hascar        => $hash{hascar},
        comment       => etrim($hash{comment}),
        h_type        => $hash{h_type},
        h_name        => $hash{h_name},
        kids          => $hash{kids},
        confnote      => _expand($c, $c->request->params->{confnote}),
        nights_taken  => $taken,
        free_prog_taken => $hash{free_prog},
        %dates,         # optionally
    });
    _compute($c, $reg, @who_now);
    _reg_hist($c, $id, "Registration updated.");
    if ($reg->house_id() || $reg->h_type() =~ m{van|commut|unk}) {
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
        $c->stash->{mess} = join "<br>", @mess;
        $c->stash->{template} = "registration/error.tt2";
        return;
    }
    $date_post = $d;
    my $program_id   = $c->request->params->{program_id};
    my $person_id    = $c->request->params->{person_id};

    my $pr = model($c, 'Program')->find($program_id);
    my $p  = model($c, 'Person')->find($person_id);

    $c->stash->{deposit} = $deposit;
    $c->stash->{deposit_type} = $deposit_type;
    $c->stash->{date_postmark} = $date_post->as_d8();
    $c->stash->{time_postmark} = "12:00";

    rest_of_reg($pr, $p, $c, today());
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    my $reg = model($c, 'Registration')->find($id);
    my $person_id = $reg->person_id;
    my $prog_id   = $reg->program_id;
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
    my @regs = sort {
                   $a->{name} cmp $b->{name}
               } map {
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
    $c->stash->{program} = $pr;
    $c->stash->{registrations} = \@regs;
    $c->stash->{template} = "registration/early_late.tt2";
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
    my $reg = $c->stash->{reg} = model($c, 'Registration')->find($id);
    my $program_id = $reg->program_id();
    #
    # is there a comment saying that they want to be
    # housed with a friend who is also registered for this program?
    #
    my $share_house_id = 0;
    my $share_house_name = "";
    if ($reg->comment =~ m{Sharing a room with\s*([^.]*)[.]}) {
        my $name = $1;
        my ($first, $last) = split m{\s+}, $name;
        $first = normalize($first);
        $last  = normalize($last);
        my ($person) = model($c, 'Person')->search({
            first => $first,
            last  => $last,
        });
        if ($person) {
            my ($reg2) = model($c, 'Registration')->search({
                person_id => $person->id,
                program_id => $program_id,
            });
            # if space left, same dates, same h_type, etc etc.
            # oh jeez - I can't do everything.
            # the best I guess would be to simply inform
            # the registrar of where their friend is housed.
            # if that room appears in the list (I can default it)
            # then they can choose it.
            if ($reg2) {
                if ($reg2->house_id) {
                    if ($reg2->h_type eq $reg->h_type) {
                        $share_house_name = $reg2->house->name;
                        $share_house_id   = $reg2->house_id;
                        $c->stash->{message2} = "Share $share_house_name"
                                               ." with $first $last?";
                    }
                    else {
                        $c->stash->{message2} = "$name requested a housing type of '"
                                              . $reg2->h_type_disp
                                              . "' not '"
                                              . $reg->h_type_disp
                                              . "'."
                                              ;
                    }
                }
                else {
                    $c->stash->{message2} = "$name has not yet been housed.";
                }
            }
            else {
                $c->stash->{message2} = "$name has not yet registered for "
                    . $reg->program->name . ".";
            }
        }
        else {
            $c->stash->{message2} = "Could not find a person named $name.";
        }
    }
    my $sdate = $reg->date_start;
    my $edate1 = (date($reg->date_end) - 1)->as_d8();

    my $h_type = $c->stash->{h_type} = $reg->h_type;
    my $bath   = ($h_type =~ m{bath}  )? "yes": "";
    my $tent   = ($h_type =~ m{tent}  )? "yes": "";
    my $center = ($h_type =~ m{center})? "yes": "";
    my $psex   = $reg->person->sex;
    my $max    = type_max($h_type);

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
        #
        my $cl_name = $pc->cluster->name();
        my $cl_tent   = $cl_name =~ m{tent}i;
        my $cl_center = $cl_name =~ m{center}i;
        if (($tent && !$cl_tent) ||
            (!$tent && $cl_tent) ||
            (!$center && $cl_center) ||  # watch out for the word center
            ($center && !$cl_center)     # in indoor housing!
        ) {
            next PROGRAM_CLUSTER;
        }

        my @c_h_opts;       # for this cluster

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
            # AND why not just ALL the config
            # records for all the houses in the cluster?
            # you're going to get them all anyway
            # so why not get them all at once?
            #
            # well, the first search below eliminates
            # the already fully occupied or gender inappropriate ones.
            # and this is done
            # within the database - reduces the data transfer
            # I _could_ have a 'in => []'
            # and specify all the houses in the cluster
            #
            # is this house truly available for this request
            # from sdate to edate1?
            # look for ways in which it is NOT.
            # space, gender, room size
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
            push @c_h_opts, [ $opt, $code_sum, $h->priority ];
            ++$n;
            if ($h_id == $share_house_id) {
                $selected = 1;
            }
        }   # end of houses in this cluster
        #
        # now we can sort the houses in this cluster
        # and then push them on the list of all chosen houses.
        #
        @c_h_opts = map {
                        $_->[0]
                    }
                    sort {
                      $b->[1] <=> $a->[1] ||      # PO       - descending
                      $a->[2] <=> $b->[2]         # priority - ascending
                    }
                    @c_h_opts;
        push @h_opts, @c_h_opts;
        if (@h_opts > $string{max_lodge_opts}) {
            last PROGRAM_CLUSTER;       # we have enough
        }
    }       # end of PROGRAM_CLUSTER
    if ($share_house_id && ! $selected) {
        # male, female want to share
        # one of them is already housed.
        # the room is not in the list because of the gender mismatch
        # or a tent with nominally only one space.
        # put it in the forced_house space
        $c->stash->{force_house} = $share_house_name;
        #unshift @h_opts,
        #    "<option value=" 
        #    . $share_house_id
        #    . " selected>"
        #    . $share_house_name
        #    . " - X"
        #    . "</option>\n"
        #    ;
        #$selected = 1;
    }
    if (@h_opts && ! $selected) {
        # no house is otherwise selected
        # insert a select into the first one.
        $h_opts[0] =~ s{>}{ selected>};
    }
    $c->stash->{house_opts} = join '', @h_opts;
    $c->stash->{total_opts} = @h_opts; 
    $c->stash->{seen_opts} = $string{seen_lodge_opts};
    $h_type =~ s{dble}{double};     # only for display...
    $h_type =~ s{_(.)}{ \u$1};
    $c->stash->{disp_h_type} = (($h_type =~ m{^[aeiou]})? "an": "a")
                             . " '\u$h_type'";
    $c->stash->{template} = "registration/lodge.tt2";
}

#
# we have identified a house for this registration.
# put this in the registration record itself
# and update the config records appropriately and carefully.
# also add a program_cluster record if it is not there already.
#
sub lodge_do : Local {
    my ($self, $c, $id) = @_;

    my ($house_id) = $c->request->params->{house_id};
    my ($force_house) = trim($c->request->params->{force_house});
    if (! ($house_id || $force_house)) {
        $c->response->redirect($c->uri_for("/registration/view/$id"));
        return;
    }
    my $house_max;
    my $house;
    if ($force_house) {
        ($house) = model($c, 'House')->search({
            name => $force_house,
        });
        if (! $house) {
            $c->stash->{mess} = "Unknown house name: $force_house";
            $c->stash->{template} = "registration/error.tt2";
            return;
        }
        $house_id = $house->id;     # override
        $house_max = $house->max;
    }
    else {
        ($house) = model($c, 'House')->find($house_id);
    }
    my $reg = model($c, 'Registration')->find($id);
    my $sdate  = $reg->date_start;
    my $edate1 = (date($reg->date_end) - 1)->as_d8();
    my $psex = $reg->person->sex;
    my $cmax = type_max($reg->h_type);
    #
    # if we forced a request for a triple into a double
    # we can't set curmax in the config record
    # to 3 - max is 2.
    #
    # what about forcing a 3rd person into
    # a double that is a resized triple?
    # that should reset curmax to 3.  see ** below.
    #
    # lastly (hopefully) we can't force too
    # many people into a room.  everyone must
    # have a bed.  this requires looking ahead.
    # except for tents, that is.
    # so weird and so complicated.   jeez.
    #
    if ($force_house && $cmax > $house_max) {
        $cmax = $house_max;
    }
    if ($force_house) {
        # look ahead to see if a room is plum full on some day.
        my @cf = model($c, 'Config')->search({
            house_id => $house_id,
            the_date => { 'between' => [ $sdate, $edate1 ] },
            cur      => $house_max,
        });
            # tents are the exception - but you need to force it.
        if (@cf && !$house->tent()) {
            $c->stash->{mess} = "Sorry, no beds left in $force_house"
                              . " on " . date($cf[0]->the_date)
                              . ".";
            $c->stash->{template} = "registration/error.tt2";
            return;
        }
    }
    #
    # we have passed all the hurdles.
    #
    $reg->update({
        house_id => $house_id,
        h_name   => '',
    });
    for my $cf (model($c, 'Config')->search({
                    house_id => $house_id,
                    the_date => { 'between' => [ $sdate, $edate1 ] }
                })
    ) {
        my $csex = $cf->sex;
        if ($cmax < $cf->cur + 1) {
            $cmax = $house_max;     # note **
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
    my $reg = $c->stash->{reg} = model($c, 'Registration')->find($id);
    my $house = $reg->house;
    $c->stash->{message1} = "Vacated " . $house->name . ".";
                                # see lodge.tt2 
    _vacate($c, $reg);
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
        #
        my @opts = ();
        if ($cf->cur == 1) {
            push @opts, curmax => $hmax;
            push @opts, sex    => 'U';
        }
        if ($cf->cur == 2 && $cf->sex eq 'X') {
            my $the_date = $cf->the_date;
            my @reg = model($c, 'Registration')->search({
                house_id   => $house_id,
                date_start => { '<=', $the_date },
                date_end   => { '>',  $the_date },
                id         => { '!=', $reg->id },
            });
            if (@reg == 1) {
                push @opts, sex => $reg[0]->person->sex;
            }
            else {
                $c->log->info("WHAT??? $#reg");
            }
        }
        $cf->update({
            cur => $cf->cur - 1,
            @opts,
        });
    }
    $reg->update({
        house_id => 0,
    });
}

sub seek : Local {
    my ($self, $c, $prog_id, $reg_id) = @_;

    my $pattern = $c->request->params->{pattern} || "";
    $pattern = trim($pattern);
    my ($pref_last, $pref_first);
    if ($pattern =~ m{(\S+)\s+(\S+)}) {
        ($pref_last, $pref_first) = ($1, $2);
    }
    else {
        $pref_last = $pattern;
        $pref_first = "";
    }
    my @name_match = ();
    if ($pref_last) {
        push @name_match, 'person.last' => { like => "$pref_last%"  };
    }
    if ($pref_first) {
        push @name_match, 'person.first' => { like => "$pref_first%" };
    }
    if (! @name_match) {
        # no regs - stay where you are/were.
        $c->response->redirect($c->uri_for("/registration/view/$reg_id"));
        return;
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
        # we already have it... so no need to get again????
        $c->response->redirect($c->uri_for("/registration/view/"
                                           . $regs[0]->id()));
    }
    elsif (@regs == 0) {
        # no regs - stay where you are/were.
        $c->response->redirect($c->uri_for("/registration/view/$reg_id"));
    }
    else {
        $c->stash->{program} = model($c, 'Program')->find($prog_id);
        $c->stash->{pat}     = $pref_last . (($pref_first)? " $pref_first": "");
        $c->stash->{regs}    = _reg_table(\@regs);
        $c->stash->{other_sort}      = "list_reg_post";
        $c->stash->{other_sort_name} = "By Postmark";
        my @files             = <root/static/online/*>;
        $c->stash->{online}   = scalar(@files);
        $c->stash->{template} = "registration/list_reg.tt2";
    }
}

sub _expand {
    my ($c, $s) = @_;
    return $s if empty($s);
    my %note;
    for my $cf (model($c, 'ConfNote')->all()) {
        $note{$cf->abbr()} = etrim($cf->expansion());
    }
    $s = etrim($s);
    $s =~ s{^(\S+$)}{ $note{$1} || $1 }gem;
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
        my $h_type = $rb->h_type();
        $h_type =~ s{dble}{double};
        $h_type =~ s{_(.)}{ \u$1};
        my $house = $rb->house();
        $c->res->output(
            "<center>"
            . $house->name()
            . "</center>"
            . "<p><table cellpadding=2>"
            . "<tr><td><a target=happening class=pr_links href="
            . $c->uri_for("/rental/view/" . $rb->rental_id() . "/3")
            . ">"
            . $rb->rental->name() . " - \u$h_type"
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
        $reg_names .= "<tr>"
                   . "<td><a target=happening href="
                   . $c->uri_for("/registration/view/$rid")
                   . ">"
                   . $r->person->last() . ", " . $r->person->first()
                   . "</a>"
                   . "<td><a target=happening href="
                   . $c->uri_for("/program/view/")
                   . $r->program_id()
                   . ">"
                   . $r->program->name()
                   . "</a></td>"
                   . "</td>"
                   . "<td width=30 align=center><a target=happening href="
                   . $c->uri_for("/registration/relodge/$rid")
                   . "><img src=/static/images/move_arrow.gif></a></td>"
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

1;
