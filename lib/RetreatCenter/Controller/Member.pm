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
    tt_today
    slurp
/;
use Date::Simple qw/
    date
    days_in_month
/;
use Global qw/%string/;
use Template;

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('list');
}

# to root/static file and then load that file in the browser.
sub membership_list : Local {
    my ($self, $c, $no_money) = @_;
    
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
    $stash{no_money} = $no_money;
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
    my ($self, $c, $all) = @_;

    # sort by sanskrit or first
    my $cond = ($all)? undef
               :        {
                            -or => [
                                category => 'General',
                                category => 'Sponsor',
                            ],
                        }
               ;
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
        model($c, 'Member')->search($cond);
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
        inactive
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
        push @mess, "You must select General, Sponsor, Life or Inactive";
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

    return 
        user_id  => $c->user->obj->id,
        the_date => tt_today($c)->as_d8(),
        time     => sprintf "%02d:%02d", (localtime())[2, 1];
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
    for my $p (model($c, 'SponsHist')->search({
                   member_id => $id,
                   general => { "!=", "yes" },
               })
    ) {
        $total += $p->amount;
    }
    $hash{total_paid} = $total;

    # update the member record
    my $pay_date = $hash{mkpay_date};
    my $amount   = $hash{mkpay_amount};
    delete $hash{mkpay_date};
    delete $hash{mkpay_amount};
    $member->update(\%hash);

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
    if (!$amount) {
        $c->response->redirect($c->uri_for("/member/view/$id"));
        return;
    }

    Global->init($c);
    my $html = acknowledge($c, $member, $amount, $pay_date);
    if (my $email = $member->person->email()) {
        email_letter($c,
            subject    => "Hanuman Fellowship Membership Payment",
            to         => $email,
            from       => $string{mem_email},
            from_title => "HFS Membership",
            html       => $html,
        );
        $c->response->redirect($c->uri_for("/member/view/$id/1"));
    }
    else {
        $c->res->output(no_here($html) . js_print());
    }
}

sub no_here {
    my ($html) = @_;
    $html =~ s{<a.*>here</a>.\n<p>}{ on the HFS website:<ul>www.hanumanfellowship.org</ul>};
    $html;
}

sub js_print {
    "<script type='text/javascript'>window.print()</script>";
}

sub acknowledge {
    my ($c, $member, $amount, $pay_date) = @_;

    my $tt = Template->new({
        INCLUDE_PATH => 'root/static/templates/letter',
        EVAL_PERL    => 0,
    });
    my $html     = "";
    my $person   = $member->person;
    my $category = $member->category;
    my $benefits = ($category eq 'Sponsor'
                    && date($member->date_sponsor) > tt_today($c));
    my $message = "";
    if ( ! $person->email) {
        my $name = $person->first . " " . $person->last;
        my $addr = $person->addr1 . "<br>\n";
        if (my $addr2 = $person->addr2) {
            $addr .= $addr2 . "<br>\n";
        }
        $addr .= $person->city . ", "
               . $person->st_prov . " "
               . $person->zip_post;
        $message = <<"EOA";
<style>
body {
    margin-left: .5in;
}
#addr {
    margin-top: 2in;
    margin-bottom: .5in;
}
</style>
<div id=addr>
$name<br>
$addr
<p>
</div>
EOA
    }
    my $stash = {
        sanskrit    => ($person->sanskrit || $person->first),
        amount      => $amount,
        pay_date    => date($pay_date),
        expire_date => date($member->date_general),
        due_date    => ($benefits? six_prior(date($member->date_sponsor))
                        :          month_after(date($pay_date))
                       ),
        total_paid  => $member->total_paid,
        string      => \%string,
        message     => $message,
        category    => $category,
    };
    $tt->process(
        # template file:
        "ack_"
            . ($category eq 'General'? 'gen': 'spons')
            . (($category eq 'Sponsor' && ! $benefits)? "_pre": "")
            . ".tt2",
        $stash,                         # variables
        \$html,                         # output
    );
    $html;
}

sub six_prior {
    my ($dt) = @_;

    my $day   = $dt->day;
    my $month = $dt->month;
    my $year  = $dt->year;
    $month -= 6;
    if ($month < 1) {
        $month += 12;
        --$year;
    }
    my $dim = days_in_month($year, $month);
    if ($day > $dim) {
        $day = $dim;
    }
    return date($year, $month, $day);
}

sub month_after {
    my ($dt) = @_;

    my $day   = $dt->day;
    my $month = $dt->month;
    my $year  = $dt->year;
    ++$month;
    if ($month > 12) {
        $month -= 12;
        ++$year;
    }
    my $dim = days_in_month($year, $month);
    if ($day > $dim) {
        $day = $dim;
    }
    return date($year, $month, $day);

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
    my $amount = $hash{mkpay_amount};

    delete $hash{mkpay_date};
    delete $hash{mkpay_amount};
    $hash{total_paid} = $amount;

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
            amount       => $amount,
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

    if (!$amount) {
        $c->response->redirect($c->uri_for("/member/view/$id"));
        return;
    }

    Global->init($c);
    my $html = acknowledge($c, $member, $amount, $date);
    
    if (my $email = $member->person->email()) {
        email_letter($c,
            subject    => "Hanuman Fellowship Membership Payment",
            to         => $email,
            from       => $string{mem_email},
            from_title => "HFS Membership",
            html       => $html,
        );
        $c->response->redirect($c->uri_for("/member/view/$id/1"));
    }
    else {
        $c->res->output(no_here($html) . js_print());
    }
}

sub _lapsed_members {
    my ($c) = @_;
    my $today = tt_today($c)->as_d8();
    return [
        map {
            $_->[1]
        }
        sort {
            $a->[0] cmp $b->[0]
        }
        map {
            my $per = $_->person();
            [ $per->last . $per->first, $_ ]
        }
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

    my $today = tt_today($c);
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
    my ($self, $c, $test) = @_;

    my @no_email;
    my $nsent = 0;
    my $mem_admin = $c->user->first . ' ' . $c->user->last;
    Global->init($c);
    MEMBER:
    for my $m (@{_lapsed_members($c)}) {
        my $per = $m->person;
        my $email = $per->email;
        if (! $email) {
            push @no_email, $m;
            next MEMBER;
        }
        my $exp_date = date($m->category eq 'General'? $m->date_general
                            :                          $m->date_sponsor);

        my @payments = $m->payments();
        my $last_amount  = (@payments)? $payments[0]->amount: 0 ;
        my $last_paid    = (@payments)? $payments[0]->date_payment_obj: 0;
        my $type = $m->category;

        my $html = "";
        my $tt = Template->new({
            INCLUDE_PATH => 'root/static/templates/letter',
            EVAL_PERL    => 0,
        });
        my $stash = {
            sanskrit    => ($per->sanskrit || $per->first),
            exp_date    => $exp_date,
            last_amount => $last_amount,
            last_paid   => $last_paid,
            string      => \%string,
        };
        $tt->process(
            # template
            "lapse_"
                . ($type eq 'General'? 'gen': 'spons')
                . ".tt2",
            $stash,           # variables
            \$html,           # output
        );
        email_letter($c,
            subject    => "Hanuman Fellowship Membership Status",
            to         => (($test)? $c->user->email: $email),
            from       => $string{mem_email},
            from_title => "HFS Membership",
            html       => $html,
        );
        ++$nsent;
    }

    $c->stash->{msg} = "$nsent email reminder letter"
                     . (($nsent == 1)? " was sent."
                        :              "s were sent.");
    $c->stash->{status} = "expired";

    $c->stash->{num_no_email} = (@no_email == 1)?
                                      "was 1 member":
                                      "were " . scalar(@no_email) . " members";
    $c->stash->{no_email} = \@no_email;
    $c->stash->{soon} = "0";
    $c->stash->{template} = "member/sent.tt2";
}

sub email_lapse_soon : Local {
    my ($self, $c, $test) = @_;

    my @no_email;
    my $nsent = 0;
    my $mem_admin = $c->user->first . ' ' . $c->user->last;
    Global->init($c);
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
        my $last_amount  = (@payments)? $payments[0]->amount: 0 ;
        my $last_paid    = (@payments)? $payments[0]->date_payment_obj: 0;
        my $html = "";
        my $tt = Template->new({
            INCLUDE_PATH => 'root/static/templates/letter',
            EVAL_PERL    => 0,
        });
        my $stash = {
            sanskrit    => ($per->sanskrit || $per->first),
            exp_date    => $exp_date,
            last_amount => $last_amount,
            last_paid   => $last_paid,
            string      => \%string,
        };
        $tt->process(
            "lapse_"
                . ($type eq 'General'? 'gen': 'spons')
                . "_soon.tt2", # template
            $stash,           # variables
            \$html,           # output
        );
        email_letter($c,
            subject    => "Hanuman Fellowship Membership Status",
            to         => (($test)? $c->user->email: $email),
            html       => $html,
            from       => $string{mem_email},
            from_title => "HFS Membership",
        );
        ++$nsent;
    }

    $c->stash->{status} = "will expire";
    $c->stash->{msg} = "$nsent email reminder letter"
                      . (($nsent == 1)? " was sent."
                         :              "s were sent.");
    $c->stash->{num_no_email} = (@no_email == 1)?
                                      "was 1 member":
                                      "were " . scalar(@no_email) . " members";
    $c->stash->{no_email} = \@no_email;
    $c->stash->{soon} = "1";
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
    Global->init($c);
    model($c, 'Member')->search({
        category => { 'in' => [ 'Sponsor', 'Life' ] },
    })->update({
        sponsor_nights  => $string{sponsor_nights},
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
    my ($self, $c, $id, $email) = @_;
    
    if ($email) {
        $c->stash->{message} = "Email acknowledgment of payment was sent.<p>";
    }
    $c->stash->{member}   = model($c, 'Member')->find($id);
    $c->stash->{template} = "member/view.tt2";
}

sub bulk : Local {
    my ($self, $c) = @_;

    $c->stash->{template} = "member/bulk.tt2";
}

#
# would a sql 'join' come in handy here???
# yes.
#
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
    my $mmc = $c->request->params->{mmc};
    my $email = $c->request->params->{type} eq 'email';
    open my $list, ">", "root/static/memlist.txt"
        or die "cannot create memlist.txt: $!\n";
    my @people;
    my $n = 0;
    for my $m (model($c, 'Member')->search({
                   category => { 'in', \@memtypes },
               })
    ) {
        ++$n;
        my $p = $m->person;
        if ($p->akey eq '44595076S') {
            next if $mmc eq 'exclude';
        }
        else {
            next if $mmc eq 'only';
        }
        if ($email) {
            my $em = $p->email;
            if (! empty($em)) {
                print {$list} $p->email . "\n";
            }
        }
        else {
            push @people, $p;
        }
    }
    if (! $email) {
        # we need to join partners in @people and then print.
        # and sort it by zip.
        # this is very complicated!
        #
        my %partner = map { $_->id => $_ } @people;
        for my $p (@people) {
            if (my $sps = $partner{$p->id_sps}) {
                if ($sps->last eq $p->last) {
                    $sps->{name} = $sps->first
                             . " & "
                             . $p->first   . " " . $p->last;
                }
                else {
                    $sps->{name} = $sps->first . " " . $sps->last
                                 . " & "
                                 . $p->first   . " " . $p->last;
                }
                delete $partner{$p->id};
                $p = 0;     # clobber this person
            }
        }
        for my $p (sort {
                       $a->zip_post cmp $b->zip_post
                   }
                   grep { $_ != 0 }
                   @people
        ) {
            print {$list} 
                  ($p->{name} || ($p->first . " " . $p->last)) . "|"
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

sub non_email : Local {
    my ($self, $c) = @_;
    $c->stash->{non_email} = [
        grep {
            ! $_->email
        }
        sort {
            $a->first cmp $b->first
        }
        map {
            $_->person
        }
        model($c, 'Member')->search({
            category => { '!=' => 'Life'     },
            category => { '!=' => 'Inactive' }
        })
    ];
    $c->stash->{template} = "member/non_email.tt2";
}

sub lapsed_letter : Local {
    my ($self, $c, $id, $soon) = @_;

    my $member = model($c, 'Member')->find($id);
    my $per = $member->person;
    my $category = $member->category;
    my $exp_date;
    if ($category eq 'General') {
        $exp_date = $member->date_general_obj;
    }
    else {
        $exp_date = $member->date_sponsor_obj;
    }
    my @payments = $member->payments;
    my ($last_amount, $last_paid) = (0, 0);
    if ($payments[0]) {
        $last_amount = $payments[0]->amount;
        $last_paid = $payments[0]->date_payment_obj;
    }
    my $html = "";
    my $tt = Template->new({
        INCLUDE_PATH => 'root/static/templates/letter',
        EVAL_PERL    => 0,
    });
    my $name = $per->first . " " . $per->last;
    my $addr = $per->addr1 . "<br>\n";
    if (my $addr2 = $per->addr2) {
        $addr .= $addr2 . "<br>\n";
    }
    $addr .= $per->city . ", "
           . $per->st_prov . " "
           . $per->zip_post;
    my $message = <<"EOA";
<style>
body {
    margin-left: .5in;
}
#addr {
    margin-top: 2in;
    margin-bottom: .5in;
}
</style>
<div id=addr>
$name<br>
$addr
<p>
</div>
EOA
    Global->init($c);
    my $stash = {
        sanskrit    => ($per->sanskrit || $per->first),
        exp_date    => $exp_date,
        last_amount => $last_amount,
        last_paid   => $last_paid,
        string      => \%string,
        message     => $message,
    };
    $tt->process(
        # template
        "lapse_"
            . ($category eq 'General'? 'gen': 'spons')
            . ($soon? "_soon": "")
            . ".tt2",
        $stash,           # variables
        \$html,           # output
    );
        $message = <<"EOA";
<style>
body {
    margin-left: .5in;
}
#addr {
    margin-top: 2in;
    margin-bottom: .5in;
}
</style>
<div id=addr.
$name<br>
$addr
<p>
</div>
EOA
    $c->res->output(no_here($html) . js_print());
}

sub payment_delete : Local {
    my ($self, $c, $payment_id) = @_;
    my $pmt = model($c, 'SponsHist')->find($payment_id);
    $pmt->delete();

    # recompute the total
    my $member_id = $pmt->member_id;
    my $total = 0;
    for my $p (model($c, 'SponsHist')->search({
                   member_id => $member_id,
                   general => { "!=", "yes" },
               })
    ) {
        $total += $p->amount;
    }
    $pmt->member->update({
        total_paid => $total,
    });
    $c->response->redirect($c->uri_for("/member/update/" . $pmt->member_id));
}

sub payment_update : Local {
    my ($self, $c, $payment_id) = @_;
    my $pmt = model($c, 'SponsHist')->find($payment_id);
    $c->stash->{payment} = $pmt;
    $c->stash->{template} = "member/payment_edit.tt2";
}

sub payment_update_do : Local {
    my ($self, $c, $payment_id) = @_;

    my @mess = ();
    my $date_payment = $c->request->params->{date_payment};
    my $dt = date($date_payment);
    if (!$dt) {
        push @mess, "Invalid date: $date_payment";
    }
    my $amount = trim($c->request->params->{amount});
    if ($amount !~ m{^\d+$}) {
        push @mess, "Invalid amount: $amount";
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "member/error.tt2";
        return;
    }
    my $pmt = model($c, 'SponsHist')->find($payment_id);
    $pmt->update({
        date_payment => $dt->as_d8(),
        amount       => $amount,
    });

    # recompute the total
    my $member_id = $pmt->member_id;
    my $total = 0;
    for my $p (model($c, 'SponsHist')->search({
                   member_id => $member_id,
                   general => { "!=", "yes" },
               })
    ) {
        $total += $p->amount;
    }
    $pmt->member->update({
        total_paid => $total,
    });
    $c->response->redirect($c->uri_for("/member/update/" . $pmt->member_id));
}

sub one_time : Local {
    my ($self, $c) = @_;

    my @sponsors = model($c, 'Member')->search({
        category => 'Sponsor',
    });
    my $tt = Template->new({
        INCLUDE_PATH => 'root/static/templates/letter',
        EVAL_PERL    => 0,
    });
    my @no_email;
    for my $m (@sponsors) {
        if (empty($m->person->email())) {
            push @no_email, $m;
            next;
        }
        my $html = "";
        $tt->process(
            "one_time.tt2",       # template
            { member => $m },     # variables
            \$html,               # output
        );
        email_letter($c,
               html       => $html, 
               subject    => "HFS Sponsor Memberships - New Guidelines",
               to         => $m->person->email(),
               from       => $string{mem_email},
               from_title => "HFS Membership",
        );
    }
    my $html = "";
    for my $m (@no_email) {
        $html .= $m->person->first . " " . $m->person->last . "<br>"
              .  $m->person->addr1 . "<br>"
              .  (empty($m->person->addr2)? "": ($m->person->addr2 . "<br>"))
              .  $m->person->city . ", "
              .  $m->person->st_prov . " "
              .  $m->person->zip_post . "<br>"
              .  (empty($m->person->country)? "": ($m->person->country."<br>"))
              .  $m->date_sponsor_obj->format("%D") . "<p>\n"
              ;
    }
    $c->res->output($html);
}

1;
