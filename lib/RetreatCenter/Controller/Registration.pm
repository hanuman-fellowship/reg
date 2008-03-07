use strict;
use warnings;
package RetreatCenter::Controller::Registration;
use base 'Catalyst::Controller';

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
    empty
/;
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
        # what if not found???
        (my $fname = $f) =~ s{root/static/online/}{};
        push @online, {
            first => $first,
            last  => $last,
            pname => $pr->name,
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

    Lookup->init($c);
    my $ftp = Net::FTP->new($lookup{ftp_site}, Passive => $lookup{ftp_passive})
        or die "cannot connect to $lookup{ftp_site}";    # not die???
    $ftp->login($lookup{ftp_login}, $lookup{ftp_password})
        or die "cannot login ", $ftp->message; # not die???
    $ftp->cwd($lookup{ftp_transactions})
        or die "cannot cwd to $lookup{ftp_transactions} ", $ftp->message;
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
        if ($dt <= today()->as_d8()
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
    # life member or current sponsor?  with nights left?
    # they must be in good standing if sponsor
    # and can't take free nights if the housing cost is not a Perday type.
    #
    if (my $mem = $p->member) {
        my $cat = $mem->category;
        my $nights = $mem->sponsor_nights;
        if ($cat eq 'Life'
            || ($cat eq 'Sponsor' && $mem->date_sponsor >= $today)
                                    # member in good standing
        ) {
            $c->stash->{status} = $cat;   # they always get a 30%
                                          # tuition discount.
            if ($pr->housecost->type eq 'Perday' && $nights > 0) {
                $c->stash->{nights} = $nights;
            }
            else {
                $c->stash->{nights} = 0;
            }
            $c->stash->{free_prog_taken}
                = ($cat eq 'Life' && ! $mem->free_prog_taken)? "yes": "no";
                        # sort of backwards... but okay.
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
        $c->stash->{ceu_license} = $hash{ceu_license};
    }

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
    $c->stash->{deposit} = int($hash{amount});

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

my @mess;
my %hash;
my @dates;
my $taken;
sub _get_data {
    my ($c) = @_;

    %hash = %{ $c->request->params() };
    my $pr = model($c, 'Program')->find($hash{program_id});
    @dates = ();
    @mess = ();
    my $date_start;
    if ($hash{date_start}) {
        # what about personal retreats???
        Date::Simple->relative_date(date($pr->sdate));
        $date_start = date($hash{date_start});
        Date::Simple->relative_date();
        if ($date_start) {
            push @dates, date_start => $date_start->as_d8();
        }
        else {
            push @mess, "Illegal date: $hash{date_start}";
        }
    }
    my $date_end;
    if ($hash{date_end}) {
        Date::Simple->relative_date(date($pr->edate));
        $date_end = date($hash{date_end});
        Date::Simple->relative_date();
        if ($date_end) {
            push @dates, date_end => $date_end->as_d8();
        }
        else {
            push @mess, "Illegal date: $hash{date_end}";
        }
    }
    my $sdate = $date_start || date($pr->sdate);
    my $edate = $date_end   || date($pr->edate);
    my $ndays = ($edate - $sdate) || 1; # personal retreat exception

    $taken = 0;
    if ($hash{nights_taken} && ! empty($hash{nights_taken})) {
        $taken = trim($hash{nights_taken});
        if ($taken !~ m{^\d+$}) {
            push @mess, "Illegal free nights taken: $taken.";
        }
        elsif ($taken > $hash{max_nights}) {
            push @mess, "Cannot take more than $hash{max_nights} free nights.";
        }
        elsif ($taken && $hash{free_prog_taken}) {
            push @mess, "Cannot take a free program AND free nights.";
        }
        elsif ($taken > $ndays) {
            push @mess, "Only staying $ndays nights so can't take $taken of them free!";
        }
    }
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
    my $reg = model($c, 'Registration')->create({
        person_id     => $hash{person_id},
        program_id    => $hash{program_id},
        date_postmark => $hash{date_postmark},
        time_postmark => $hash{time_postmark},
        ceu_license   => $hash{ceu_license},
        referral      => $hash{referral},
        adsource      => $hash{adsource},
        carpool       => $hash{carpool},
        hascar        => $hash{hascar},
        comment       => trim($hash{comment}),
        h_type        => $hash{h_type},
        h_name        => $hash{h_name},
        kids          => $hash{kids},
        confnote      => trim($hash{confnote}),
        status        => $hash{status},
        nights_taken  => $taken,
        free_prog_taken => $hash{free_prog_taken},
        @dates,         # optionally
    });
    my $reg_id = $reg->id();

    # prepare for history records
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

    my $today = today();
    my $now_date = $today->as_d8();
    my ($hour, $min) = (localtime())[2, 1];
    my $now_time = sprintf "%02d:%02d", $hour, $min;
    my @common = (
        reg_id   => $reg_id,
        user_id  => $user_id,
        the_date => $now_date,
        time     => $now_time,
    );

    # first, we have some PAST history
    model($c, 'RegHistory')->create({
        reg_id   => $reg_id,
        user_id  => $web_user_id,
        the_date => $hash{date_postmark},
        time     => $hash{time_postmark},
        what     => 'Online Registration',       # other name???
                                        # to not confuse with 'Registration'???
    });

    # now current history
    model($c, 'RegHistory')->create({
        @common,
        what    => 'Registration Created',
    });

    # credit, if any
    if ($hash{credit_id}) {
        my $cr = model($c, 'Credit')->find($hash{credit_id});
        my $amount = $cr->amount();
        my $pr_g = $cr->reg_given->program;
        model($c, 'RegCharge')->create({
            @common,
            automatic => '',        # NOT automatic
            amount  => -1*$amount,
            what    => 'Credit from the '
                       . $pr_g->name . ' program in '
                       . $pr_g->sdate_obj->format("%B %Y"),
        });
        # and mark the credit as taken
        $cr->update({
            date_used   => $now_date,
            used_reg_id => $reg_id,
        });
    }
    # the payment (deposit)
    model($c, 'RegPayment')->create({
        @common,
        amount  => $hash{deposit},
        type    => 'Online',        # what else if not from online???
        what    => 'Deposit',
    });

    # add the automatic charges
    _compute($c, $reg, @common);

    # if this registration was from an online file
    # move it aside.  we have finished processing it at this point.
    if ($hash{fname}) {
        rename "root/static/online/$hash{fname}",
               "root/static/online_done/$hash{fname}";
    }
    $c->response->redirect($c->uri_for("/registration/view/$reg_id"));
}

#
# automatic charges - computed from the contents
# of the registration record.
#
sub _compute {
    my ($c, $reg, @common) = @_;

    Lookup->init($c);
    my $pr  = $reg->program;
    my $mem = $reg->person->member;

    my $sdate = date($reg->date_start || $pr->sdate);
    my $edate = date($reg->date_end   || $pr->edate);
    my $ndays = ($edate - $sdate) || 1; # personal retreat exception

    # tuition
    my $tuition = $pr->tuition;
    model($c, 'RegCharge')->create({
        @common,
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
                @common,
                automatic => 'yes',
                amount    => -1*$tuition,
                what      => "Life member - free program - tuition waived.",
            });
        }
        else {
            my $amount = ($lookup{spons_tuit_disc}/100)*$tuition;
            my $maxed = "";
            if ($amount > $lookup{max_tuit_disc}) {
                $amount = $lookup{max_tuit_disc};
                $maxed = " - to a max of \$$lookup{max_tuit_disc}";
            }
            model($c, 'RegCharge')->create({
                @common,
                automatic => 'yes',
                amount    => -1*$amount,
                what      => "$lookup{spons_tuit_disc}% Tuition discount for "
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
		$tot_h_cost = $ndays*$h_cost;
        $what = "$ndays days Lodging at \$$h_cost per day";
    }
    else {
        $tot_h_cost = $h_cost;
        $what = "Lodging - Total Cost";
    }
    model($c, 'RegCharge')->create({
        @common,
        automatic => 'yes',
        amount    => $tot_h_cost,
        what      => $what,
    });
    my $life_free = 0;
    if ($reg->free_prog_taken) {
        model($c, 'RegCharge')->create({
            @common,
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
            reg_id     => $reg->id,
            @common,
        });
    }
	if (!$life_free && $housecost->type eq "Perday") {
        if ($ndays >= $lookup{disc1days}) {
            model($c, 'RegCharge')->create({
                @common,
                automatic => 'yes',
                amount    => -1*(int(($lookup{disc1pct}/100)*$tot_h_cost)),
                what      => "$lookup{disc1pct}% Lodging Discount for programs >= $lookup{disc1days} days",
            });
        }
        if ($ndays >= $lookup{disc2days}) {
            model($c, 'RegCharge')->create({
                @common,
                automatic => 'yes',
                amount    => -1*(int(($lookup{disc2pct}/100)*$tot_h_cost)),
                what      => "$lookup{disc2pct}% Lodging Discount for programs >= $lookup{disc2days} days",
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
	if (my $n = $reg->nights_taken) {
        my $plural = ($n == 1)? "": "s";
        model($c, 'RegCharge')->create({
            @common,
            automatic => 'yes',
            amount    => -1*($h_cost * $n),
            what      => "$n free night$plural lodging for "
                        . $reg->status_str . " member",
        });
        #
        # deduct these nights from the person's member record.
        #
        $mem->update({
            sponsor_nights => $mem->sponsor_nights - $n,     # cool, eh?
        });
        #
        # and add a NightHist record to specify what happened
        #
        model($c, 'NightHist')->create({
            @common,
            member_id  => $mem->id,
            num_nights => $n,
            action     => 2,    # take nights
        });
    }
   
    #
    # is there a minimum of $15 per day for lodging???
    # figure the kids cost from the initial UNdiscounted rate.
    # bringing your kids during your free program - they still pay.
    #
    if (my $kids = $reg->kids) {
        my $min_age = $lookup{min_kid_age};
        my $max_age = $lookup{max_kid_age};
        my @ages = $kids =~ m{(\d+)}g;
        @ages = grep { $min_age <= $_ && $_ <= $max_age } @ages;
        my $nkids = @ages;
        my $plural = ($nkids == 1)? "": "s";
        if ($nkids) {
            model($c, 'RegCharge')->create({
                @common,
                automatic => 'yes',
                amount    => int($nkids * (($lookup{kid_disc}/100)*$tot_h_cost)),
                what      => "$nkids kid$plural aged $min_age-$max_age"
                           . " - $lookup{kid_disc}% for lodging",
            });
        }
    }
    if ($reg->ceu_license) {
        model($c, 'RegCharge')->create({
            @common,
            automatic => 'yes',
            amount    => $lookup{ceu_lic_fee},
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
#
sub send_conf : Local {
    my ($self, $c, $id) = @_;

    my $reg = model($c, 'Registration')->find($id);
    my $pr = $reg->program;
    Lookup->init($c);
    my $htdesc = $lookup{$reg->h_type};
    $htdesc =~ s{\s*\(.*\)}{};           # don't need this
    $htdesc =~ s{Mount Madonna }{};      # ... Center Tent
    my $personal_retreat = $pr->title =~ m{personal\s*retreat}i;
    my $start = ($reg->date_start)? $reg->date_start_obj: $pr->sdate_obj;
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
    _email($c,
           html    => $html, 
           subject => "Confirmation of Registration for " . $pr->title,
           to      => $reg->person->email,
           from    => $lookup{from},
           from_title => $lookup{from_title},
    );
    $c->response->redirect($c->uri_for("/registration/view/$id"));
}

sub _email {
    my ($c, %args) = @_;

    # check args for keys letter, subject, to, from

    #
    # convert the HTML letter to text with lynx
    # ??? any way to do this without creating a tmp text file?
    # keeping it all in memory?
    #
    open my $lynx_dump, "|lynx -stdin -dump -width=95>/tmp/$$"
        or die "cannot open |lynx: $!\n";
    print {$lynx_dump} $args{html};
    close $lynx_dump;
    open my $text_in, "<", "/tmp/$$"
        or die "cannot open /tmp/$$: $!\n";
    my $text;
    {
        local $/;
        $text = <$text_in>;
        close $text_in;
        unlink "/tmp/$$";
    }
    my $mail = Mail::SendEasy->new(
        smtp => $lookup{smtp_server},
        user => $lookup{smtp_user},
        pass => $lookup{smtp_pass},
    );
    my $status = $mail->send(
        %args,
        msg => $text,
    );
    if (! $status) {
        # what to do about this???
        $c->log->info('mail error: ' . $mail->error);
    }
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

sub cancel : Local {
    my ($self, $c, $id) = @_;

    my $reg = model($c, 'Registration')->find($id);
    $c->stash->{reg} = $reg;
    my $today = today();
    $c->stash->{today} = $today;
    $c->stash->{ndays} = $reg->program->sdate_obj - $today;
    Lookup->init($c);
    $c->stash->{amount} = $lookup{credit_amount};
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
        });
    }
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
        _email($c,
               html    => $html, 
               subject => "Cancellation of Registration for "
                          . $reg->program->title,
               to      => $reg->person->email,
               from    => $lookup{from},
               from_title => $lookup{from_title},
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

sub uncancel : Local {
    my ($self, $c, $id) = @_;

    my $reg = model($c, 'Registration')->find($id);
    $reg->update({
        cancelled => '',
    });

    # delete any credit that might have been given for this registration.
    model($c, 'Credit')->search({
        reg_id    => $id,
    })->delete();

    # note this event in reg history
    _reg_hist($c, $id, "Registration UNcancelled");

    $c->response->redirect($c->uri_for("/registration/view/$id"));
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

    # also get the user id of the 'web user'
    my ($wu) = model($c, 'User')->search({
        username => 'web_user',
    });
    my $web_user_id = $wu->id();

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
        my $house = $reg->h_name;
        my $date = date($reg->date_postmark);
        my $time = $reg->time_postmark;
        my $mark =            (!$house)? 'H'
                  :(!$reg->letter_sent)? 'L'
                  :   ($reg->cancelled)? 'X'
                  :                      '&nbsp;';
        if (length($mark) == 1) {
            $mark = "<span class=required>$mark</span>";
        }
        my $postrow = "";
        if ($postmark) {
            $postrow = <<"EOH";
<td>
<span class=rname>$date&nbsp;&nbsp;$time</span>
</td>
EOH
        }
        my $pay_balance = $balance;
        if (! $reg->cancelled) {
            $pay_balance = "<a href='/registration/pay_balance/$id/list_reg_name'><span class=rname>$pay_balance</span></a>";
        }
        $body .= <<"EOH";
<tr>

<td>$mark</td>

<td>    <!-- width??? -->
<a href='/registration/view/$id'><span class=rname>$name</span></a>
</td>

<td>
$pay_balance
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
<<"EOH";        # returning a bare string heredoc constant?  sure.
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

sub update_confnote : Local {
    my ($self, $c, $id) = @_;

    $c->stash->{reg} = model($c, 'Registration')->find($id);
    $c->stash->{template} = "registration/confnote.tt2";
}
sub update_confnote_do : Local{
    my ($self, $c, $id) = @_;

    my $reg = model($c, 'Registration')->find($id);
    my $confnote = trim($c->request->params->{confnote});
    $reg->update({
        confnote => $confnote,
    });
    $c->response->redirect($c->uri_for("/registration/view/$id"));
}
sub update_comment : Local {
    my ($self, $c, $id) = @_;

    $c->stash->{reg} = model($c, 'Registration')->find($id);
    $c->stash->{template} = "registration/comment.tt2";
}
sub update_comment_do : Local{
    my ($self, $c, $id) = @_;

    my $reg = model($c, 'Registration')->find($id);
    my $comment = trim($c->request->params->{comment});
    $reg->update({
        comment => $comment,
    });
    $c->response->redirect($c->uri_for("/registration/view/$id"));
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $reg = model($c, 'Registration')->find($id);
    $c->stash->{reg} = $reg;
    $c->stash->{person} = $reg->person;
    my $pr = $c->stash->{program} = $reg->program;
    for my $ref (qw/ad web brochure flyer/) {
        $c->stash->{"$ref\_selected"} = ($reg->referral eq $ref)? "selected": "";
    }
    if ($pr->footnotes =~ m{[*]}) {
        $c->stash->{ceu} = 1;
    }
    my $h_type_opts = "<option type=unknown>Unknown\n";
    Lookup->init($c);     # get %lookup ready.
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
        double
        double_bath
        single
        single_bath
    )) {
        next HTYPE if $htname eq "single_bath" && ! $pr->sbath;
        next HTYPE if $htname eq "quad"        && ! $pr->quad;
        next HTYPE if $htname eq "economy"     && ! $pr->economy;
        next HTYPE if $pr->housecost->$htname == 0;     # wow!

        my $selected = ($htname eq $reg->h_type)? " selected": "";
        my $htdesc = $lookup{$htname};
        $htdesc =~ s{\(.*\)}{};              # registrar doesn't need this
        $htdesc =~ s{Mount Madonna }{};      # ... Center Tent
        $h_type_opts .= "<option value=$htname$selected>$htdesc\n";
    }
    $c->stash->{h_type_opts} = $h_type_opts;
    $c->stash->{template} = "registration/edit.tt2";
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    my $reg = model($c, 'Registration')->find($id);

    # check validity of the fields
    # clear all automatic charges
    # look carefully at any _changes_ in nights taken or free program
    #   and adjust the member record in advance of the recomputation.
    # recompute charges
    # update the reg record

    $c->response->redirect($c->uri_for("/registration/view/$id"));
}

1;
