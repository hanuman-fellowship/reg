use strict;
use warnings;
package RetreatCenter::Controller::Registration;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.
use Date::Simple qw/date today/;
use Util qw/nsquish digits model/;

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('program/list');    # ???
}

sub list_online : Local {
    my ($self, $c) = @_;

    my @online_regs;
    for my $f (<root/static/online_reg/*>) {
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
        (my $fname = $f) =~ s{root/static/online_reg/}{};
        push @online_regs, {
            first => $first,
            last  => $last,
            pname => $pname,
            date  => $date,
            time  => $time,
            fname => $fname,
        };
    }
    $c->stash->{online} = \@online_regs;
    $c->stash->{template} = "registration/list_online.tt2";
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
    open my $in, "<", "root/static/online_reg/$fname"
        or die "cannot open root/static/online_reg/$fname: $!";
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

    # verify that we have a pid, first, and last.

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
    if (@ppl == 0) {
        #
        # no match so create a new person
        # check for misspellings first???
        # do an akey search, pop up list???
        # or cell phone search???
        #
        my $today = today()->as_d8();
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
        if ($hash{new_addr}) {
            # update that person's address
            # ???
        }
    }
    $c->stash->{person} = $p;

    #
    # next, find the program
    # without it we can do nothing!
    #
    my ($pr) = model($c, 'Program')->find($hash{pid});
    if (! $pr) {
        # ??? error screen
    }
    $c->stash->{pr_sdate} = date($pr->sdate);
    $c->stash->{pr_edate} = date($pr->edate);

    $c->stash->{program} = $pr;

    $c->stash->{ceu_license} = $hash{ceu_license};

    # comments
    $c->stash->{comment} = <<"EOC";
1-$hash{house1}  2-$hash{house2}  $hash{cabinRoom}  $hash{time}  online
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

    my $date = date($hash{date});
    $c->stash->{date_postmark} = $date->as_d8();

    # normally empty - except for personal retreats
    # or when the person is coming earlier or staying later
    if ($hash{sdate} || $hash{edate}) {
        $c->stash->{date_start} = date($hash{sdate} || $pr->sdate);
        $c->stash->{date_end  } = date($hash{edate} || $pr->edate);
    }

    $c->stash->{template} = "registration/create.tt2";
}

# now we actually create the registration
sub create_do : Local {
    my ($self, $c) = @_;

    my %hash = %{ $c->request->params() };
    my @dates = ();
    if ($hash{sdate}) {
        @dates = (
            date_start => date($hash{sdate})->as_d8(),
            date_end   => date($hash{edate})->as_d8(),
        );
    }
    my $username = $c->user->username();
    # can't do $c->user_id for some unknown reason??? so...
    my ($u) = model($c, 'User')->search({
        username => $username,
    });
    my $r = model($c, 'Registration')->create({
        person_id     => $hash{person_id},
        program_id    => $hash{program_id},
        date_postmark => $hash{date_postmark},
        ceu_license   => $hash{ceu_license},
        referral      => $hash{referral},
        adsource      => $hash{adsource},
        carpool       => $hash{carpool},
        hascar        => $hash{hascar},
        comment       => $hash{comment},
        @dates,
    });
    # make payment record with -deposit-???
    # history record - added

    $c->stash->{registration} = $r;
    $c->stash->{template} = "registration/view.tt2";
}

sub view : Local {
    my ($self, $c, $id) = @_;

    my $r = model($c, 'Registration')->find($id);
    $c->stash->{registration} = $r;
    $c->stash->{template} = "registration/view.tt2";
}

1;
