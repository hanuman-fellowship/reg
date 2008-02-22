use strict;
use warnings;
package RetreatCenter::Controller::Registration;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.
use Date::Simple qw/date today/;
use Util qw/nsquish digits model trim/;
use Lookup;
    # damn awkward to keep this thing initialized... :(
    # is there no way to do this better???
use Template;
use Mail::SendEasy;

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('program/list');    # ???
}

sub list_online : Local {
    my ($self, $c) = @_;

    my @online;
    for my $f (<root/static/online/*>) {
        open my $in, "<", $f
            or die "cannot open $f: $!\n";
        my ($date, $time, $first, $last, $pname);
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
            elsif (m{x_pname => (.*)}) {
                $pname = $1;
            }
        }
        close $in;
        (my $fname = $f) =~ s{root/static/online/}{};
        push @online, {
            first => $first,
            last  => $last,
            pname => $pname,
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

    system("$ENV{HOME}/bin/getOO");      # do this with Net::FTP???
                                    # yeah.
    $c->response->redirect($c->uri_for("/registration/list_online"));
}

sub list_reg_name : Local {
    my ($self, $c, $prog_id) = @_;

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
    $c->stash->{program} = $pr;
    # ??? dup'ed code in matchreg and list_reg_name
    # DRY??? don't repeat yourself!
    my @regs = map {
                   $_->[2]
               }
               sort {
                   $a->[0] cmp $b->[0] or
                   $a->[1] cmp $b->[1]
               }
               grep {
                   $_->[0] =~ m{^$pref_last}i  and
                   $_->[1] =~ m{^$pref_first}i
               }
               map {
                   my $p = $_->person;
                   [ $p->last, $p->first, $_ ]
               }
               $pr->registrations;
    if (@regs == 1) {
        my $r = $regs[0];
        my $pr = $r->program;
        my $dt = $r->date_start || $pr->sdate;
        # is this precisely what we want or what?!! :)
        if ($dt <= today()->as_d8() && $r->balance > 0) {
            $c->response->redirect($c->uri_for("/registration/pay_balance/" .
                                   $regs[0]->id . "/list_reg_name"));
        }
        else {
            $c->response->redirect($c->uri_for("/registration/view/" .
                                   $regs[0]->id));
        }
        return;
    }
    Lookup->init($c);
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
    my @regs = map {
                   $_->[1]
               }
               sort {
                   $a->[0] cmp $b->[0]
               }
               map { [ $_->date_postmark . $_->time_postmark, $_ ] }
               $pr->registrations;
    for my $r (@regs) {
        $r->{date_mark} = date($r->date_postmark);
    }
    Lookup->init($c);
    $c->stash->{regs} = _reg_table(\@regs, 1);
    $c->stash->{other_sort} = "list_reg_name";
    $c->stash->{other_sort_name} = "By Name";
    my @files = <root/static/online/*>;
    $c->stash->{online} = scalar(@files);
    $c->stash->{template} = "registration/list_reg.tt2";
}

my %needed = map { $_ => 1 } qw/
    pname
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

    # save the filename so we can delete when we're complete
    $c->stash->{fname} = $fname;

    # verify that we have a pid, first, and last. and an amount.
    # ...

    #
    # first, find the program
    # without it we can do nothing!
    #
    my ($pr) = model($c, 'Program')->find($hash{pid});
    if (! $pr) {
        # ??? error screen
    }
    $c->stash->{pr_sdate} = date($pr->sdate);
    $c->stash->{pr_edate} = date($pr->edate);

    $c->stash->{program} = $pr;

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
        #
        # add the program affils to this person
        #
        my $person_id = $p->id();
        for my $aff ($pr->affils()) {
            model($c, 'AffilPerson')->create({
                a_id => $aff->id,
                p_id => $person_id,
            });
        }
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
        #
        # and the person's affils get _added to_ according
        # to the program affiliations.
        # make a quick lookup table of the person's affil ids.
        #
        my %cur_affils = map { $_->id => 1 }
                         $p->affils;
        for my $pr_affil_id (map { $_->id } $pr->affils) {
            if (! exists $cur_affils{$pr_affil_id}) {
                model($c, 'AffilPerson')->create({
                    a_id => $pr_affil_id,
                    p_id => $person_id,
                });
            }
        }
    }
    $c->stash->{person} = $p;
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
    # life member or current sponsor?
    # with nights left?
    #
    if (my $mem = $p->member) {
        my $cat = $mem->category;
        my $nights = $mem->sponsor_nights;
        if ($cat eq 'Life'
            || ($cat eq 'Sponsor' && $mem->date_sponsor >= $today)
        ) {
            $c->stash->{category} = $cat;   # they always get a 30%
                                            # tuition discount.
            if ($nights > 0) {
                $c->stash->{nights} = $nights;
            }
        }
    }

    $c->stash->{ceu_license} = $hash{ceu_license};

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

    for my $how (qw/ ad web brochure flyer /) {
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
    $c->stash->{deposit} = $hash{amount};

    # sdate/edate (in the hash from the online file)
    # are normally empty - except for personal retreats
    # or when the person is coming earlier or staying later
    if ($hash{sdate} || $hash{edate}) {
        $c->stash->{date_start} = date($hash{sdate} || $pr->sdate);
        $c->stash->{date_end  } = date($hash{edate} || $pr->edate);
    }

    # the housing select list.
    # default is the first housing choice.
    # lots of names for the house type... :(
    # these are also the
    my %h_type = qw(
        com    commuting
        ov     own_van
        ot     own_tent
        ct     center_tent
        dorm   dormitory
        econ   economy
        quad   quad
        tpl    triple
        dbl    double
        dbl/ba double_bath
        sgl    single
        sgl/ba single_bath
    );
    # order is important:
    my $h_type_opts = "<option type=unknown>Unknown\n";
    Lookup->init($c);     # get %lookup ready.
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

        my $selected = $ht eq $hash{house1}? " selected": "";
        my $htdesc = $lookup{$htname};
        $htdesc =~ s{\(.*\)}{};              # registrar doesn't need this
        $htdesc =~ s{Mount Madonna }{};      # ... Center Tent
        $h_type_opts .= "<option value=$htname$selected>$htdesc\n";
    }
    $c->stash->{h_type_opts} = $h_type_opts;

    $c->stash->{template} = "registration/create.tt2";
}

# now we actually create the registration
# if from an online source there will be a filename
# in the hash which needs deleting.
sub create_do : Local {
    my ($self, $c) = @_;

    my %hash = %{ $c->request->params() };
    my $pr = model($c, 'Program')->find($hash{program_id});
    my @dates = ();
    my @mess = ();
    if ($hash{date_start}) {
        # what about personal retreats???
        Date::Simple->relative_date(date($pr->sdate));
        my $d = date($hash{date_start});
        if ($d) {
            push @dates, date_start => $d->as_d8();
        }
        else {
            push @mess, "Illegal date: $hash{date_start}";
        }
    }
    if ($hash{date_end}) {
        Date::Simple->relative_date(date($pr->edate));
        my $d = date($hash{date_end});
        if ($d) {
            push @dates, date_end => $d->as_d8();
        }
        else {
            push @mess, "Illegal date: $hash{date_end}";
        }
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>", @mess;
        $c->stash->{template} = "registration/error.tt2";
        return;
    }
    my $r = model($c, 'Registration')->create({
        person_id     => $hash{person_id},
        program_id    => $hash{program_id},
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
        confnote      => $hash{confnote},
        @dates,         # optionally
    });
    my $reg_id = $r->id();

    #
    # who is doing this?
    # can't do $c->user->id for some unknown reason??? so...
    #
    my $username = $c->user->username();
    my ($u) = model($c, 'User')->search({
        username => $username,
    });
    my $user_id = $u->id;

    # also get the user id of the 'web user'
    my ($wu) = model($c, 'User')->search({
        username => 'web_user',
    });
    my $web_user_id = $wu->id();

    my $now_date = today()->as_d8();
    my ($hour, $min) = (localtime())[2, 1];
    my $now_time = sprintf "%02d:%02d", $hour, $min;

    # history records
    # first, we have some PAST history
    model($c, 'RegHistory')->create({
        reg_id   => $reg_id,
        user_id  => $web_user_id,
        the_date => $hash{date_postmark},
        time     => $hash{time_postmark},
        what     => 'Online Registration',       # other name???
                                        # to not confuse with 'Registration'???
    });
    my @common = (
        reg_id   => $reg_id,
        user_id  => $user_id,
        the_date => $now_date,
        time     => $now_time,
    );
    model($c, 'RegHistory')->create({
        @common,
        what    => 'Registration Created',
    });

    # financial records
    model($c, 'RegPayment')->create({
        @common,
        amount  => $hash{deposit},
        type    => 'Online',        # what else if not from online???
        what    => 'Deposit',
    });

    # tuition
    my $tuition = $pr->tuition;
    model($c, 'RegCharge')->create({
        @common,
        amount  => $tuition,
        what    => 'Tuition',
    });
    # sponsor/life members get a 30% discount on tuition
    if ($hash{category}) {
        model($c, 'RegCharge')->create({
            @common,
            amount  => -(0.30*$tuition),
            what    => "30% Tuition discount for $hash{category} member",
        });
        
    }

    # assuming we have decided on their housing at this point...
    # figure housing cost
    my $housecost = $pr->housecost;
    my $sdate = date($r->date_start || $pr->sdate);
    my $edate = date($r->date_end   || $pr->edate);
    my $ndays = ($edate - $sdate) || 1; # personal retreat exception

    my $h_type = $hash{h_type};           # what housing type was assigned?
    my $h_cost = $housecost->$h_type;      # column name is correct, yes?
    my ($tot_h_cost, $what);
	if ($housecost->type eq "Perday") {
		$tot_h_cost = $ndays*$h_cost;
        $what = "$ndays days Lodging at \$$h_cost per day";
    }
    else {
        $tot_h_cost = $h_cost;
        $what = "Lodging - Total Cost";
    }
    model($c, 'RegCharge')->create({
        @common,
        amount  => $tot_h_cost,
        what    => $what,
    });
	if ($housecost->type eq "Perday") {
        if ($ndays >= 7) {      # Strings??? 7, 30, .10, .10
            model($c, 'RegCharge')->create({
                @common,
                amount  => -(int(0.10*$tot_h_cost)),
                what    => '10% Lodging Discount for programs >= 7 days',
            });
        }
        if ($ndays >= 30) {     # Strings???
            model($c, 'RegCharge')->create({
                @common,
                amount  => -(int(0.10*$tot_h_cost)),
                what    => '10% further Lodging Discount for programs >= 30 days',
            });
        }
	}
    #
    # sponsor/life members get free nights
    # what about programs that have a Total Cost housing cost type???
    # right - we shouldn't pop up the Sponsor dialog then, eh???
    #
    # do people take free nights only when they can get a single?
    # Hanuman Fellowship membership benefit brochure
    # says something about not including meals...???
    #
    # if taken when the program is > 7 days the
    # sponsor member could actually get a credit.
    # not right somehow???
    #
	my $nights_avail = $hash{nights} || 0;
	if ($nights_avail && $housecost->type eq "Perday") {
        # ??? probably a cleaner way of doing this...
        my $nights_used;
        my $nights_left;
        if ($nights_avail > $ndays) {
            # can't take more than the length of the program...
            $nights_used = $ndays;
            $nights_left = $nights_avail - $ndays;
        }
        else {
            $nights_used = $nights_avail;
            $nights_left = 0;
        }
        my $plural = ($nights_used == 1)? "": "s";
        model($c, 'RegCharge')->create({
            @common,
            amount  => -($h_cost * $nights_used),
            what    => "$nights_used free night$plural lodging for $hash{category} member",
        });
        #
        # deduct these nights from the person's member record.
        #
        my $p = model($c, 'Person')->find($hash{person_id});
        my $m = $p->member;
        $m->update({
            sponsor_nights => $nights_left,
        });
    }
   
    if ($hash{work_study}) {
        if ($pr->retreat) {
            model($c, 'RegCharge')->create({
                @common,
                amount  => -(int($pr->tuition()/3)),
                what    => '1/3 Tuition discount for work study during retreat',
            });
            model($c, 'RegCharge')->create({
                @common,
                amount  => -(int($tot_h_cost/3)),
                what    => '1/3 Lodging discount for work study during retreat',
                    # String for the 1/3???
            });
        }
        else {
            my $ws_disc = 24; # ??? String for the 24?
            model($c, 'RegCharge')->create({
                @common,
                amount  => -($ndays*$ws_disc),
                what    => "Discount for work study of \$$ws_disc a day"
                         . " for $ndays days",
            });
        }
    }
    # ??? is there a minimum of $15 per day for lodging???
    # ??? String for that?
    if ($hash{kids}) {
        my $min_age = 2;         # Strings???
        my $max_age = 12;
        my @ages = $hash{kids} =~ m{(\d+)}g;
        @ages = grep { $min_age <= $_ && $_ <= $max_age } @ages;
        my $nkids = @ages;
        my $plural = ($nkids == 1)? "": "s";
        if ($nkids) {
            model($c, 'RegCharge')->create({
                @common,
                amount  => int($nkids * ($tot_h_cost/2)),
                what    => "$nkids kid$plural aged $min_age-$max_age"
                         . " - half cost for lodging",
            });
        }
    }
    if ($hash{ceu_license}) {
        model($c, 'RegCharge')->create({
            @common,
            amount  => 10,      # String???
            what    => "CEU License fee",
        });
    }

    # calculate the balance, update the reg record
    my $balance = 0;
    for my $ch ($r->charges) {
        $balance += $ch->amount;
    }
    for my $py ($r->payments) {
        $balance -= $py->amount;
    }
    $r->update({
        balance => $balance,
    });


    #
    # IF we have assigned housing, send a confirmation letter.
    # ??? don't send if no housing ???
    # fill in a template and send it off.
    #
    # use the template toolkit outside of the Catalyst mechanism
    #
    my $tt = Template->new({
        INCLUDE_PATH => 'root/static/templates/letter',
        EVAL_PERL    => 0,
    });
    my $person = $r->person;
    my $user   = $c->user;
    my $stash = {
        user     => $user,
        person   => $person,
        reg      => $r,
        program  => $pr,
    };
    my $html = "";
    $tt->process(
        $pr->cl_template . ".tt2",      # input
        $stash,
        \$html,
    );
    #
    # send the letter to $r->person->email
    #
    my $mail = Mail::SendEasy->new(
        smtp => 'mail.logicalpoetry.com:50',
        user => 'jon@logicalpoetry.com',
        pass => 'hello!',
    );
    my $status = $mail->send(
        subject => "Confirmation of Registration for " . $pr->title,
        to      => $person->email,
        from    => $user->email,
        msg     => "hi there",      # ??? need two version???
        html    => $html,
    );
    if (! $status) {
        # what to do about this???
        $c->log->info('mail error: ' . $mail->error);
    }
    model($c, 'RegHistory')->create({
        @common,
        what    => 'Confirmation Letter Sent',
    });

    # if this registration was from an online file
    # move it aside.  we have finished processing it at this point.
    if ($hash{fname}) {
        rename "root/static/online/$hash{fname}",
               "root/static/online_done/$hash{fname}";
    }

    $c->response->redirect($c->uri_for("/registration/view/$reg_id"));
}

sub view : Local {
    my ($self, $c, $id) = @_;

    my $r = model($c, 'Registration')->find($id);
    $c->stash->{reg} = $r;
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
    # not $c->user->id; # ???
    my $username = $c->user->username();
    my ($u) = model($c, 'User')->search({
        username => $username,
    });
    my $user_id = $u->id;

    my $now_date = today()->as_d8();
    my ($hour, $min) = (localtime())[2, 1];
    my $now_time = sprintf "%02d:%02d", $hour, $min;

    my @common = (
        reg_id => $id,
        user_id  => $user_id,
        the_date => $now_date,
        time     => $now_time,
    );
    model($c, 'RegPayment')->create({
        @common,
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
            @common,
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
    my @regs = map {
                   $_->[2]
               }
               sort {
                   $a->[0] cmp $b->[0] or
                   $a->[1] cmp $b->[1]
               }
               grep {
                   $_->[0] =~ m{^$pref_last}i  and
                   $_->[1] =~ m{^$pref_first}i
               }
               map {
                   my $p = $_->person;
                   [ $p->last, $p->first, $_ ]
               }
               $pr->registrations;
    Lookup->init($c);
    $c->res->output(_reg_table(\@regs));
}

#
# if only one - make it larger - for fun.
#
sub _reg_table {
    my ($reg_aref, $postmark) = @_;
    my $size = 12;
    my $color = "black";
    if (scalar(@$reg_aref) == 1) {
        $size = 18;
        $color = "red";
    }
    my $posthead = "";
    if ($postmark) {
        $posthead = <<"EOH";
<th align=center>Postmark</th>
EOH
    }
    my $heading = <<"EOH";
<tr>
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
        my $house = $reg->h_name;
        my $date = date($reg->date_postmark);
        my $time = $reg->time_postmark;
        my $postrow = "";
        if ($postmark) {
            $postrow = <<"EOH";
<td>
<span class=rname>$date&nbsp;&nbsp;$time</span>
</td>
EOH
        }
        $body .= <<"EOH";
<tr>

<td>    <!-- width??? -->
<a href='/registration/view/$id'><span class=rname>$name</span></a>
</td>

<td>
<a href='/registration/pay_balance/$id/list_reg_name'><span class=rname>$balance</span></a>
</td>

<td>
<span class=rname>$type</span>
</td>

<td>
<span class=rname>$house</span>
</td>

$postrow

</tr>
EOH
    }
    $body ||= "";
<<"EOH";        # returning a bare string constant???
<style>
.rname {
    font-size: ${size}pt;
    color: $color;
}
</style>
<table cellpadding=4>
$heading
$body
</table>
EOH
}

1;
