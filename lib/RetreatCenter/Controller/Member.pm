use strict;
use warnings;
package RetreatCenter::Controller::Member;
use base 'Catalyst::Controller';

use Mail::SendEasy;

use lib '../../';       # so you can do a perl -c here.
use Util qw/
    empty
    trim
    model
    email_letter
/;
use Date::Simple qw/date today/;
use Lookup;

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('list');
}

# to root/static file and then load that file in the browser.
sub membership_list : Local {
    my ($self, $c) = @_;
    
    my %stash;
    for my $cat (qw/ general sponsor life /) {
        $stash{lc $cat} = [
            map {
                $_->[1]
            }
            sort {
                $a->[0] cmp $b->[0]
            }
            map {
                [ $_->person->last . ' ' . $_->person->first, $_ ]
            }
            model($c, 'Member')->search(
                { category => ucfirst $cat },
            )
        ];
        $stash{"n$cat"} = scalar(@{$stash{$cat}});
    }
    my $html = "";
    my $tt = Template->new({
        INCLUDE_PATH => 'root/src/member',
        EVAL_PERL    => 0,
    });
    $tt->process(
        "by_category.tt2",# template
        \%stash,          # variables
        \$html,           # output
    );
    $c->res->output($html);
}

sub list : Local {
    my ($self, $c) = @_;

    # sort by sanskrit or first
    my @members =
        map {
            $_->[1]
        }
        sort {
            $a->[0] cmp $b->[0]
        }
        map {
            [ $_->person->last . ' ' . $_->person->first, $_ ]
        }
        model($c, 'Member')->all();
    $c->stash->{members} = \@members;
    $c->stash->{template} = "member/list.tt2";
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $m = $c->stash->{member} = model($c, 'Member')->find($id);
    for my $w (qw/
        general
        sponsor
        life
    /) {
        $c->stash->{"category_$w"} = ($m->category eq ucfirst($w))? "checked": "";
    }
    $c->stash->{free_prog_checked} = ($m->free_prog_taken)? "checked": "";

    $c->stash->{person}      = $m->person();
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "member/create_edit.tt2";
}

my %hash;
my @mess;
sub _get_data {
    my ($c) = @_;

    %hash = %{ $c->request->params() };
    @mess = ();
    if (! $hash{category}) {
        push @mess, "You must select General, Sponsor or Life";
    }
    # dates are either blank or converted to d8 format
    for my $f (keys %hash) {
        next unless $f =~ m{date};
        next unless $hash{$f} =~ m{\S};
        # ??? what about " " for a date?
        my $dt = date($hash{$f});
        if (! $dt) {
            # tell them which date field is wrong???
            push @mess, "Invalid date: $hash{$f}";
            next;
        }
        $hash{$f} = $dt->as_d8();
    }
    if ($hash{mkpay_amount} || $hash{mkpay_date}) {
        if ($hash{mkpay_amount} !~ m{^\s*-?\d+\s*$}) {
            push @mess, "No payment amount";
        }
        if (! $hash{mkpay_date}) {
            push @mess, "No payment date";
        }
    }
    if ($hash{category} eq 'General' && ! $hash{date_general}) {
        push @mess, "Missing General date";
    }
    if ($hash{category} eq 'Sponsor' && ! $hash{date_sponsor}) {
        push @mess, "Missing Sponsor date";
    }
    if ($hash{category} eq 'General') {
        $hash{sponsor_nights} = 0;
        $hash{free_prog_taken} = '';
    }
    else {
        $hash{sponsor_nights} = trim($hash{sponsor_nights});
        if ($hash{sponsor_nights} !~ m{^\d*$}) {
            push @mess, "Invalid Nights Left: $hash{sponsor_nights}";
        }
    }
    if (! exists $hash{free_prog_taken}) {
        $hash{free_prog_taken} = '';        # an unchecked field would not
                                            # be sent if I didn't do this...
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "member/error.tt2";
    }
}

sub get_now {
    my ($c) = @_;

    my ($hour, $min) = (localtime())[2, 1];
    my $now_time = sprintf "%02d:%02d", $hour, $min;
    my $username = $c->user->username();
    my ($u) = model($c, 'User')->search({
        username => $username,
    });
    return 
        user_id  => $u->id,
        the_date => today->as_d8(),
        time     => $now_time,
}

#
# don't even try to move Sponsor to Life
# when they exceed $5000 or $8000.
# it will be a rare ocurrence.
#
sub update_do : Local {
    my ($self, $c, $id) = @_;

    _get_data($c);
    return if @mess;

    my $member = model($c, 'Member')->find($id);
    my @who_now = get_now($c);

    if ($hash{mkpay_date}) {
        # put payment in history, reset last paid

        model($c, 'SponsHist')->create({
            member_id    => $id,
            date_payment => $hash{mkpay_date},
            amount       => $hash{mkpay_amount},
            general      => $hash{category} eq 'General'? 'yes': '',
            @who_now,
        });
    }

    # recompute the total
    my $total = 0;
    PAYMENT:
    for my $p (model($c, 'SponsHist')->search({
                   member_id => $id,
                   general => { "!=", "yes" },
               })
    ) {
        $total += $p->amount;
    }
    $hash{total_paid} = $total;

    # update the member record
    delete $hash{mkpay_date};
    delete $hash{mkpay_amount};
    if ($member->sponsor_nights != $hash{sponsor_nights}) {
        # add NightHist record to reflect the change
        model($c, 'NightHist')->create({
            member_id => $id,
            reg_id => 0,
            num_nights => $hash{sponsor_nights},
            action => 1,    # set nights
            @who_now,
        });
    }
    if ($member->free_prog_taken ne $hash{free_prog_taken}) {
        # add NightHist record to reflect the change
        model($c, 'NightHist')->create({
            member_id => $id,
            reg_id => 0,
            num_nights => 0,
            action => ($hash{free_prog_taken})? 5: 3,  # set/clear free program
            @who_now,
        });
    }
    $member->update(\%hash);

    $c->response->redirect($c->uri_for("/member/view/$id"));
}

#
# only the super admin can do this.
#
sub delete : Local {
    my ($self, $c, $id) = @_;

    my $m = model($c, 'Member')->find($id);
    $m->payments()->delete();
    $m->delete();
    $c->response->redirect($c->uri_for('/member/list'));
}

sub create : Local {
    my ($self, $c, $person_id) = @_;

    $c->stash->{person} = model($c, 'Person')->find($person_id);
    $c->stash->{form_action} = "create_do/$person_id";
    $c->stash->{template}    = "member/create_edit.tt2";
}

sub create_do : Local {
    my ($self, $c, $person_id) = @_;

    _get_data($c);
    return if @mess;

    my $date = $hash{mkpay_date};
    my $amnt = $hash{mkpay_amount};
    delete $hash{mkpay_date};
    delete $hash{mkpay_amount};
    $hash{total_paid} = $amnt;

    my $member = model($c, 'Member')->create({
        person_id    => $person_id,
        %hash,
    });
    my $id = $member->id();
    my @who_now = get_now($c);

    # put any payment in history
    if ($date) {
        model($c, 'SponsHist')->create({
            member_id    => $id,
            date_payment => $date,
            amount       => $amnt,
            general      => $hash{category} eq 'General'? 'yes': '',
            @who_now,
        });
    }
    # NightHist records
    if ($hash{category} ne 'General') {
        model($c, 'NightHist')->create({
            @who_now,
            member_id  => $id,
            reg_id     => 0,
            num_nights => $hash{sponsor_nights},
            action     => 1,
        });
    }
    if ($hash{category} eq 'Life') {
        model($c, 'NightHist')->create({
            @who_now,
            member_id  => $id,
            reg_id     => 0,
            num_nights => 0,
            action     => ($hash{free_prog_taken})? 5: 3,
        });
    }
    $c->response->redirect($c->uri_for("/member/view/$id"));
}

sub _lapsed_members {
    my ($c) = @_;
    my $today = today()->as_d8();
    return [
        model($c, 'Member')->search({
            -or => [
                -and => [
                    category => 'General',
                    date_general => { '<', $today },
                ],
                -and => [
                    category => 'Sponsor',
                    date_sponsor => { '<', $today },
                ],
            ],
        })
    ];
}
sub _soon_to_lapse_members {
    my ($c) = @_;

    my $today = today();
    my $month = $today + 30;
    $today = $today->as_d8();
    $month = $month->as_d8();

    return [
        model($c, 'Member')->search({
            -or => [
                -and => [
                    category => 'General',
                    date_general => { between => [ $today, $month ] },
                ],
                -and => [
                    category => 'Sponsor',
                    date_sponsor => { between => [ $today, $month ] },
                ],
            ],
        })
    ];
}

sub lapsed : Local {
    my ($self, $c) = @_;

    $c->stash->{members} = _lapsed_members($c);
    $c->stash->{template} = "member/lapsed.tt2";
}

sub lapse_soon : Local {
    my ($self, $c) = @_;
    
    $c->stash->{members} = _soon_to_lapse_members($c);
    $c->stash->{template} = "member/lapse_soon.tt2";
}

sub email_lapsed : Local {
    my ($self, $c) = @_;

    my @no_email;
    my $nsent = 0;
    my $mem_admin = $c->user->first . ' ' . $c->user->last;
    MEMBER:
    for my $m (@{_lapsed_members($c)}) {
        my $per = $m->person;
        my $name = $per->first . ' ' . $per->last;
        my $email = $per->email;
        if (! $email) {
            push @no_email, $m;
            next MEMBER;
        }
        my $exp_date = date($m->category eq 'General'? $m->date_general
                            :                          $m->date_sponsor);

        my @payments = $m->payments();
        my $last_amount  = $payments[0]->amount;
        my $last_paid = date($payments[0]->date_payment);
        my $type = $m->category;

        my $html = "";
        my $tt = Template->new({
            INCLUDE_PATH => 'root/static/templates/letter',
            EVAL_PERL    => 0,
        });
        my $stash = {
            name        => $name,
            type        => $type,
            exp_date    => $exp_date,
            last_amount => $last_amount,
            last_paid   => $last_paid,
            mem_admin   => $mem_admin,
        };
        $tt->process(
            "lapse.tt2",      # template
            $stash,           # variables
            \$html,           # output
        );
        email_letter($c,
            subject    => "Hanuman Fellowship Membership Status",
            to         => $email,
            from       => $c->user->email,
            from_title => $mem_admin,
            html       => $html,
        );
        ++$nsent;
    }

    $c->stash->{msg} = "$nsent letter" . (($nsent == 1)? " was sent."
                                          :              "s were sent.");
    $c->stash->{no_email} = \@no_email;
    $c->stash->{template} = "member/sent.tt2";
}

sub email_lapse_soon : Local {
    my ($self, $c) = @_;

    my @no_email;
    my $nsent = 0;
    my $mem_admin = $c->user->first . ' ' . $c->user->last;
    MEMBER:
    for my $m (@{_soon_to_lapse_members($c)}) {
        my $per = $m->person;
        my $name = $per->first . ' ' . $per->last;
        my $email = $per->email;
        if (! $email) {
            push @no_email, $m;
            next MEMBER;
        }
        my $exp_date = date($m->category eq 'General'? $m->date_general
                            :                          $m->date_sponsor);
        my $type = $m->category;

        my @payments = $m->payments();
        my $last_amount  = $payments[0]->amount;
        my $last_paid = date($payments[0]->date_payment);
        my $html = "";
        my $tt = Template->new({
            INCLUDE_PATH => 'root/static/templates/letter',
            EVAL_PERL    => 0,
        });
        my $stash = {
            name        => $name,
            type        => $type,
            exp_date    => $exp_date,
            last_amount => $last_amount,
            last_paid   => $last_paid,
            mem_admin   => $mem_admin,
        };
        $tt->process(
            "lapse_soon.tt2", # template
            $stash,           # variables
            \$html,           # output
        );
        email_letter($c,
            subject    => "Hanuman Fellowship Membership Status",
            to         => $email,
            from       => $c->user->email,
            from_title => $mem_admin,
            html       => $html,
        );
        ++$nsent;
    }

    $c->stash->{msg} = "$nsent letter" . (($nsent == 1)? " was sent."
                                          :              "s were sent.");
    $c->stash->{no_email} = \@no_email;
    $c->stash->{template} = "member/sent.tt2";
}

sub reset : Local {
    my ($self, $c) = @_;
    $c->stash->{template} = "member/reset_confirm.tt2";
}

sub reset_do : Local {
    my ($self, $c) = @_;

    if ($c->request->params->{no}) {
        $c->response->redirect($c->uri_for("/member/list"));
        return;
    }
    if ($c->request->params->{password} ne "sita") {
        $c->stash->{mess} = "Incorrect password";
        $c->stash->{template} = "member/error.tt2";
        return;
    }
    Lookup->init($c);
    model($c, 'Member')->search({
        category => { 'in' => [ 'Sponsor', 'Life' ] },
    })->update({
        sponsor_nights  => $lookup{sponsor_nights},
        free_prog_taken => '',
    });
    $c->response->redirect($c->uri_for("/member/list"));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

sub view : Local {
    my ($self, $c, $id) = @_;

    $c->stash->{member}   = model($c, 'Member')->find($id);
    $c->stash->{template} = "member/view.tt2";
}

sub bulk : Local {
    my ($self, $c) = @_;

    $c->stash->{template} = "member/bulk.tt2";
}

sub bulk_do : Local {
    my ($self, $c) = @_;

    my @memtypes;
    if ($c->request->params->{general}) {
        push @memtypes, 'General';
    }
    if ($c->request->params->{sponsor}) {
        push @memtypes, 'Sponsor';
    }
    if ($c->request->params->{life}) {
        push @memtypes, 'Life';
    }
    my $email = $c->request->params->{type} eq 'email';
    open my $list, ">", "root/static/memlist.txt"
        or die "cannot create memlist.txt: $!\n";
    my $n = 0;
    for my $m (model($c, 'Member')->search({
                   category => { 'in', \@memtypes },
               })
    ) {
        ++$n;
        my $p = $m->person;
        if ($email) {
            my $em = $p->email;
            if (! empty($em)) {
                print {$list} $p->email . "\n";
            }
        }
        else {
            print {$list} 
                  $p->first . " " . $p->last . "|"
                  . $p->addrs . "|"
                  . $p->city . "|"
                  . $p->st_prov . "|"
                  . $p->zip_post
                  . "\n";

        }
    }
    if ($n == 0) {
        # can't redirect to an empty root/static/ file. :(
        print {$list} "\n";
    }
    close $list;
    $c->response->redirect($c->uri_for("/static/memlist.txt"));
}

1;
