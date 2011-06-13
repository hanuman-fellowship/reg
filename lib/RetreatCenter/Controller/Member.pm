use strict;
use warnings;
package RetreatCenter::Controller::Member;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.
use Util qw/
    empty
    trim
    model
    email_letter
    tt_today
    slurp
    stash
/;
use Date::Simple qw/
    date
    days_in_month
    today
/;
use Time::Simple qw/
    get_time
/;
use Global qw/
    %string
    $guru_purnima
/;
use Template;

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('list');
}

# to root/static file and then load that file in the browser.
sub membership_list : Local {
    my ($self, $c, $no_money) = @_;
    
    my %stash;
    for my $cat (qw/ gene cont spon life inac /) {
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
            model($c, 'Member')->search({
                category => { -like => "$cat%" },
            })
        ];
        $stash{"n$cat"} = scalar(@{$stash{$cat}});  # fancy!
    }
    $stash{no_money} = $no_money;
    my $html = "";
    my $tt = Template->new({
        INTERPOLATE  => 1,
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

    my $pat = trim($c->request->params->{pat});
    my @members = ();
    if ($pat) {
        $pat =~ s{\*}{%}g;
        $pat = { like => "%$pat%" };
        @members = 
            model($c, 'Member')->search({
                -or => [
                    'person.last'     => $pat,
                    'person.first'    => $pat,
                    'person.sanskrit' => $pat,
                ],
            },
            {
                join     => ['person'],
                prefetch => ['person'],
                order_by => ['person.last', 'person.first' ],
            }
        );
    }
    $c->stash->{members} = \@members;
    $c->stash->{template} = "member/list.tt2";
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $m = $c->stash->{member} = model($c, 'Member')->find($id);
    for my $w (qw/
        general
        contributing_sponsor
        sponsor
        life
        inactive
    /) {
        my $cat = lc $m->category();
        $c->stash->{"category_$w"} =
            (substr($cat, 0, 3) eq substr($w, 0, 3))? "checked"
            :                                         ""
            ;
    }
    $c->stash->{free_prog_checked} = ($m->free_prog_taken)? "checked"
                                     :                      ""
                                     ;

    $c->stash->{person}      = $m->person();
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "member/create_edit.tt2";
}

my %P;
my @mess;
sub _get_data {
    my ($c) = @_;

    %P = %{ $c->request->params() };
    @mess = ();
    if (! $P{category}) {
        push @mess, "You must select General, Contributing Sponsor, Sponsor, Life or Inactive";
    }
    # dates are either blank or converted to d8 format
    for my $f (keys %P) {
        next unless $f =~ m{date|valid};
        next unless $P{$f} =~ m{\S};
        # ??? what about " " for a date?
        my $dt = date($P{$f});
        if (! $dt) {
            # tell them which date field is wrong???
            push @mess, "Invalid date: $P{$f}";
            next;
        }
        $P{$f} = $dt->as_d8();
    }
    if ($P{mkpay_amount} || $P{mkpay_date}) {
        if ($P{mkpay_amount} !~ m{^\s*-?\d+\s*$}) {
            push @mess, "No payment amount";
        }
        if (! $P{mkpay_date}) {
            push @mess, "No payment date";
        }
        if (! $P{valid_from}) {
            push @mess, "No valid from date";
        }
        if (! $P{valid_to}) {
            push @mess, "No valid to date";
        }
    }
    if ($P{category} eq 'General'
        && ! $P{date_general}
        && ! $P{valid_to}
    ) {
        push @mess, "Missing General date";
    }
    if ($P{category} eq 'Sponsor'
        && ! $P{date_sponsor}
        && ! $P{valid_to}
    ) {
        push @mess, "Missing Sponsor date";
    }
    if ($P{category} eq 'General') {
        $P{sponsor_nights} = 0;
        $P{free_prog_taken} = '';
    }
    else {
        $P{sponsor_nights} = trim($P{sponsor_nights});
        if ($P{sponsor_nights} !~ m{^\d*$}) {
            push @mess, "Invalid Nights Left: $P{sponsor_nights}";
        }
    }
    if (! exists $P{free_prog_taken}) {
        $P{free_prog_taken} = '';        # an unchecked field would not
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
        time     => get_time()->t24(),
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

    my $pay_date   = $P{mkpay_date};
    my $amount     = $P{mkpay_amount};
    my $valid_from = $P{valid_from};
    my $valid_to   = $P{valid_to};

    delete $P{mkpay_date};
    delete $P{mkpay_amount};
    delete $P{valid_from};
    delete $P{valid_to};

    my $member = model($c, 'Member')->find($id);
    my @who_now = get_now($c);

    if ($pay_date) {
        # put payment in history, reset last paid

        model($c, 'SponsHist')->create({
            member_id    => $id,
            date_payment => $pay_date,
            valid_from   => $valid_from,
            valid_to     => $valid_to,
            amount       => $amount,
            general      => $P{category} eq 'General' 
                            && $amount <= $string{mem_gen_amt}? 'yes': '',
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
    $P{total_paid} = $total;

    if ($member->sponsor_nights() != $P{sponsor_nights}) {
        # add NightHist record to reflect the change
        model($c, 'NightHist')->create({
            member_id  => $id,
            reg_id     => 0,
            num_nights => $P{sponsor_nights},
            action     => 1,    # set nights
            @who_now,
        });
    }
    if ($member->free_prog_taken ne $P{free_prog_taken}) {
        # add NightHist record to reflect the change
        model($c, 'NightHist')->create({
            member_id  => $id,
            reg_id     => 0,
            num_nights => 0,
            action     => ($P{free_prog_taken})? 5: 3, 
                # set/clear free program
            @who_now,
        });
    }

    # if a payment was made...
    # fill in the general expiry/sponsor date_due dates based
    # on the valid_to date - unless they have
    # changed these dates directly.
    # 
    if ($valid_to) {
        if ($P{category} eq 'General'
            && $P{date_general} == $member->date_general()
        ) {
            $P{date_general} = $valid_to;
        }
        if ($P{category} eq 'Sponsor'
            && $P{date_sponsor} == $member->date_sponsor()
        ) {
            $P{date_sponsor} = $valid_to;
        }
    }

    if ($P{category} eq 'Life' && $member->category() ne 'Life') {
        # a new Life member
        # clear the free program taken
        #
        model($c, 'NightHist')->create({
            member_id  => $id,
            reg_id     => 0,
            num_nights => 0,
            action     => 3, # clear free program
            @who_now,
        });
    }

    # finally, update the member record
    $member->update(\%P);

    if (!$amount) {
        $c->response->redirect($c->uri_for("/member/view/$id"));
        return;
    }

    Global->init($c);
    my $html = acknowledge($c, $member, $amount, $pay_date);
    my $pers = $member->person();
    if ($pers->email()) {
        email_letter($c,
            to      => $pers->name_email(),
            from    => "HFS Membership <$string{mem_email}>",
            subject => "Hanuman Fellowship Membership Payment",
            html    => $html,
        );
        $c->response->redirect($c->uri_for("/member/view/$id/1"));
    }
    else {
        $c->res->output(_no_here($html) . js_print());
    }
}

sub _no_here {
    my ($html) = @_;
    $html =~ s{<a[^>]*>here</a>[.]\n<p>}{ on the HFS website:<ul>www.hanumanfellowship.org</ul>};
    $html;
}

sub js_print {
    "<script type='text/javascript'>window.print()</script>";
}

sub acknowledge {
    my ($c, $member, $amount, $pay_date) = @_;

    my $person   = $member->person;
    my $category = $member->category;
    my $benefits = ($category eq 'Sponsor'
                    && date($member->date_sponsor()) > tt_today($c));
    my $message = "";
    if ( ! $person->email) {
        my $name = $person->name();
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
        sanskrit     => ($person->sanskrit || $person->first),
        amount       => $amount,
        pay_date     => date($pay_date),
        expire_date  => date($member->date_general),
        due_date     => date($member->date_sponsor()),
        toward_spons => $category eq 'General'
                        && $amount > $string{mem_gen_amt},
        total_paid   => $member->total_paid(),
        string       => \%string,
        message      => $message,
        category     => $category,
    };
    my $html = "";

    my $tt = Template->new({
        INTERPOLATE  => 1,
        INCLUDE_PATH => 'root/static/templates/letter',
        EVAL_PERL    => 0,
    }) or $c->log->info("NO TEMPLATE NEW $Template::ERROR");
    my $file = 
        "ack_"
            . ($category eq 'General'? 'gen': 'spons')
            . ".tt2";
    $tt->process(
        $file,          # template file
        $stash,         # variables
        \$html,         # output
    ) or $c->log->info("NO PROCESS $Template::ERROR");
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

    my $mkpay_date = $P{mkpay_date};
    my $amount     = $P{mkpay_amount};
    my $valid_from = $P{valid_from};
    my $valid_to   = $P{valid_to};

    delete $P{mkpay_date};
    delete $P{mkpay_amount};
    delete $P{valid_from};
    delete $P{valid_to};

    if ($P{category} eq 'General' && ! $P{date_general}) {
        $P{date_general} = $valid_to;
    }
    if ($P{category} eq 'Sponsor' && ! $P{date_sponsor}) {
        $P{date_sponsor} = $valid_to;
    }

    $P{total_paid} = $amount;

    my $member = model($c, 'Member')->create({
        person_id    => $person_id,
        %P,
    });

    #
    # add the Guru Purnima affiliation to the Person
    # if it is not already there.
    #
    my @affils = model($c, 'AffilPerson')->search({
        a_id => $guru_purnima,
        p_id => $person_id,
    });
    if (! @affils) {
        model($c, 'AffilPerson')->create({
            a_id => $guru_purnima,
            p_id => $person_id,
        });
    }

    my $id = $member->id();
    my @who_now = get_now($c);

    # put any payment in history
    if ($mkpay_date) {
        model($c, 'SponsHist')->create({
            member_id    => $id,
            date_payment => $mkpay_date,
            valid_from   => $valid_from,
            valid_to     => $valid_to,
            amount       => $amount,
            general      => $P{category} eq 'General'? 'yes': '',
            @who_now,
        });
    }

    # NightHist records
    if ($P{category} ne 'General') {
        model($c, 'NightHist')->create({
            @who_now,
            member_id  => $id,
            reg_id     => 0,
            num_nights => $P{sponsor_nights} || 0,
            action     => 1,
        });
    }
    if ($P{category} eq 'Life') {
        model($c, 'NightHist')->create({
            @who_now,
            member_id  => $id,
            reg_id     => 0,
            num_nights => 0,
            action     => 3,
        });
    }

    if (!$amount) {
        $c->response->redirect($c->uri_for("/member/view/$id"));
        return;
    }

    Global->init($c);
    my $html = acknowledge($c, $member, $amount, $mkpay_date);
    
    my $pers = $member->person();
    if ($pers->email()) {
        email_letter($c,
            to      => $pers->name_email(),
            from    => "HFS Membership <$string{mem_email}>",
            subject => "Hanuman Fellowship Membership Payment",
            html    => $html,
        );
        $c->response->redirect($c->uri_for("/member/view/$id/1"));
    }
    else {
        $c->res->output(_no_here($html) . js_print());
    }
}

sub _lapsed_members {
    my ($c) = @_;
    my $today = tt_today($c)->as_d8();
    return [
        model($c, 'Member')->search(
            {
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
            },
            {
                join     => ['person'],
                prefetch => ['person'],
                order_by => ['person.last', 'person.first' ],
            }
        )
    ];
}
sub _soon_to_lapse_members {
    my ($c) = @_;

    my $today = tt_today($c);
    my $month = $today + 30;
    $today = $today->as_d8();
    $month = $month->as_d8();

    return [
        model($c, 'Member')->search(
            {
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
            },
            {
                join     => ['person'],
                prefetch => ['person'],
                order_by => ['person.last', 'person.first' ],
            }
        )
    ];
}

sub _checked_members {
    my ($c) = @_;

    my @ids = ();
    for my $p ($c->request->param()) {
        if ($p =~ m{id(\d+)}) {
            push @ids, $1;
        }
    }
    model($c, 'Member')->search(
        {
            'me.id' => { in => \@ids },
        },
        {
            join     => ['person'],
            prefetch => ['person'],
            order_by => ['person.last', 'person.first' ],
        }
    );
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

    my $to_you = $c->request->params->{to_you};
    my @no_email;
    my $nsent = 0;
    my $mem_admin = $c->user->name();
    Global->init($c);
    MEMBER:
    for my $m (_checked_members($c)) {
        my $per = $m->person();
        my $email = $per->email();
        if (! $email) {
            push @no_email, $m;
            next MEMBER;
        }
        my $exp_date = date($m->category eq 'General'? $m->date_general()
                            :                          $m->date_sponsor());

        my @payments = $m->payments();
        my $last_amount  = (@payments)? $payments[0]->amount: 0 ;
        my $last_paid    = (@payments)? $payments[0]->date_payment_obj: 0;
        my $type = $m->category;

        my $html = "";
        my $tt = Template->new({
            INTERPOLATE   => 1,
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
            to      => (($to_you)? $c->user->email(): $per->name_email()),
            from    => "HFS Membership <$string{mem_email}>",
            subject => "Hanuman Fellowship Membership Status",
            html    => $html,
        );
        ++$nsent;
    }

    stash($c,
        msg    => "$nsent email reminder letter"
                  . (($nsent == 1)? " was sent."
                     :              "s were sent."),
        status       => "expired",
        num_no_email => (@no_email == 1)? "was 1 member"
                        :                 "were "
                                          . scalar(@no_email)
                                          . " members",
        no_email => \@no_email,
        soon     => "0",
        template => "member/sent.tt2",
    );
}

sub email_lapse_soon : Local {
    my ($self, $c) = @_;

    my $to_you = $c->request->params->{to_you};
    my @no_email;
    my $nsent = 0;
    my $mem_admin = $c->user->name();
    Global->init($c);
    MEMBER:
    for my $m (_checked_members($c)) {
        my $per = $m->person;
        my $name = $per->name();
        my $email = $per->email;
        if (! $email) {
            push @no_email, $m;
            next MEMBER;
        }
        my $exp_date = date($m->category eq 'General'? $m->date_general()
                            :                          $m->date_sponsor());
        my $type = $m->category;

        my @payments = $m->payments();
        my $last_amount  = (@payments)? $payments[0]->amount: 0 ;
        my $last_paid    = (@payments)? $payments[0]->date_payment_obj: 0;
        my $html = "";
        my $tt = Template->new({
            INTERPOLATE  => 1,
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
            to      => (($to_you)? $c->user->email(): $per->name_email()),
            from    => "HFS Membership <$string{mem_email}>",
            subject => "Hanuman Fellowship Membership Status",
            html    => $html,
        );
        ++$nsent;
    }

    stash($c,
        status => "will expire",
        msg    => "$nsent email reminder letter"
                          . (($nsent == 1)? " was sent."
                             :              "s were sent."),
        num_no_email => (@no_email == 1)? "was 1 member":
                                          "were "
                                          . scalar(@no_email)
                                          . " members",
        no_email => \@no_email,
        soon     => "1",
        template => "member/sent.tt2",
    );
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

    stash($c,
        general_checked => "checked",
        sponsor_checked => "checked",
        life_checked    => "checked",
        include_checked => "",
        exclude_checked => "checked",
        only_checked    => "",
        email_checked   => "",
        snail_checked   => "checked",
        template => "member/bulk.tt2",
    );
}

#
# would an sql 'join' come in handy here???
# yes.
#
sub bulk_do : Local {
    my ($self, $c) = @_;

    my @memtypes;
    my ($general, $sponsor, $life);
    if ($c->request->params->{general}) {
        push @memtypes, 'General';
        $general = 1;
    }
    if ($c->request->params->{sponsor}) {
        push @memtypes, 'Sponsor';
        $sponsor = 1;
    }
    if ($c->request->params->{life}) {
        push @memtypes, 'Life';
        $life = 1;
    }
    my $count = $c->request->params->{count};
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
        my $p = $m->person;
        if ($p->akey eq '44595076SUM') {
            next if $mmc eq 'exclude';
        }
        else {
            next if $mmc eq 'only';
        }
        if ($email) {
            my $em = $p->email;
            if (! empty($em)) {
                print {$list} $p->email . "\n";
                ++$n;
            }
        }
        else {
            push @people, $p;
        }
    }
    if (! $email) {
        # we need to join partners in @people and then print.
        # and sort it by zip.
        # we postpone determining $n until after this is done.
        # very complicated!
        # similar to Report running - but no collapsing.
        #
        my %partner = map { $_->id => $_ } @people;
        for my $p (@people) {
            if (my $sps = $partner{$p->id_sps}) {
                if ($sps->last eq $p->last) {
                    $sps->{name} = $sps->first
                             . " & "
                             . $p->name()
                             ;
                }
                else {
                    $sps->{name} = $sps->name()
                                 . " & "
                                 . $p->name()
                                 ;
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
                  ($p->{name} || ($p->name())) . "|"
                  . $p->addrs . "|"
                  . $p->city . "|"
                  . $p->st_prov . "|"
                  . $p->zip_post . "|"
                  . $p->country
                  . "\n";
            ++$n;
        }
    }
    if ($n == 0) {
        # can't redirect to an empty root/static/ file. :(
        print {$list} "\n";
    }
    close $list;
    if ($count) {
        stash($c,
            template => "member/bulk.tt2",
            message         => "Count = $n",

            general_checked => ($general)? "checked": "",
            sponsor_checked => ($sponsor)? "checked": "",
            life_checked    => ($life   )? "checked": "",
            include_checked => ($mmc eq 'include')? "checked": "",
            exclude_checked => ($mmc eq 'exclude')? "checked": "",
            only_checked    => ($mmc eq 'only'   )? "checked": "",
            email_checked   => ($email  )? "checked": "",
            snail_checked   => (! $email)? "checked": "",
        );
    }
    else {
        $c->response->redirect($c->uri_for("/static/memlist.txt"));
    }
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
        INTERPOLATE  => 1,
        INCLUDE_PATH => 'root/static/templates/letter',
        EVAL_PERL    => 0,
    });
    my $name = $per->name();
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
    $c->res->output(_no_here($html) . js_print());
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
    my %dates;
    for my $f (qw/date_payment valid_from valid_to/) {
        my $v = $c->request->params->{$f};
        my $dt = date($v);
        if (!$dt) {
            push @mess, "Invalid date: $v";
        }
        $dates{$f} = $dt;
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
        date_payment => $dates{date_payment}->as_d8(),
        valid_from   => $dates{valid_from  }->as_d8(),
        valid_to     => $dates{valid_to    }->as_d8(),
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
        INTERPOLATE  => 1,
        INCLUDE_PATH => 'root/static/templates/letter',
        EVAL_PERL    => 0,
    });
    my @no_email;
    for my $m (@sponsors) {
        my $pers = $m->person();
        if (empty($pers->email())) {
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
            to      => $pers->name_email(),
            from    => "HFS Membership <$string{mem_email}>",
            subject => "HFS Sponsor Memberships - New Guidelines",
            html    => $html, 
        );
    }
    my $html = "";
    for my $m (@no_email) {
        $html .= $m->person->name() . "<br>"
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
