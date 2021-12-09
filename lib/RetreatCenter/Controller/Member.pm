#
# TODO: the online member payments need to be
# verified on akash.
#
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
    stash
/;
use Date::Simple qw/
    date
    days_in_month
    today
    ymd
/;
use Time::Simple qw/
    get_time
/;
use File::stat;
use Global qw/
    %string
    %system_affil_id_for
    @hfs_affil_ids
/;
use Template;
use LWP::Simple 'get';
use Net::FTP;

my $omp_dir = '/var/Reg/omp';

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('list');
}

# to root/static file and then load that file in the browser.
sub membership_list : Local {
    my ($self, $c, $no_money) = @_;
    
    my %stash;
    for my $cat (qw/ gene spon life found resident /) {
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
            grep { ! $_->lapsed }
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
    ) or die $tt->error;
    $c->res->output($html);
}

# to root/static file and then load that file in the browser.
sub voter_list : Local {
    my ($self, $c) = @_;
    
    open my $list, ">", "/var/Reg/report/voter_list.csv"
        or die "cannot create voter_list.csv: $!\n";
    print {$list} "Last, First, Sanskrit, Voter, Email, Telephone, Address, Category\n";
    for my $m (
        map {
            $_->[1]
        }
        sort {
            $a->[0] cmp $b->[0]
        }
        map {
            [ $_->person->last . ' ' . $_->person->first, $_ ]
        }
        grep { ! $_->lapsed }
        model($c, 'Member')->search({
            category => { -not_like => 'Inactive' },
        })
    ) {
        my $p = $m->person;
        print {$list} join ', ',
                      $p->last,
                      $p->first,
                      $p->sanskrit,
                      $m->voter,
                      $p->email,
                      $p->fone,
                      $p->snail,
                      $m->category,
                      ;
        print {$list} "\n";
    }
    close $list;
    $c->response->redirect($c->uri_for("/report/show_report_file/voter_list.csv"));
}

sub voter_ok : Local {
    my ($self, $c, $id) = @_;
    my $m = model($c, 'Member')->find($id);
    $m->update({
        voter => 'yes',
    });
    $c->response->redirect($c->uri_for("/member/view/$id"));
}

sub list : Local {
    my ($self, $c, $exclude_lapsed) = @_;

    my $pat = trim($c->request->params->{pat});
    my @members = ();
    if ($pat) {
        my $sqlpat = $pat;
        $sqlpat =~ s{\*}{%}g;
        $sqlpat = { like => "%$sqlpat%" };
        @members = model($c, 'Member')->search(
            {
                -or => [
                    'person.last'     => $sqlpat,
                    'person.first'    => $sqlpat,
                    'person.sanskrit' => $sqlpat,
                ],
            },
            {
                join     => ['person'],
                prefetch => ['person'],
                order_by => ['person.last', 'person.first' ],
            }
            # ??? the above join/prefetch could be put everywhere
            # there is a search for multiple members.
            # it is currently 12/31/11 not done this way.
        );
    }
    else {
        @members = model($c, 'Member')->search(
            {
                category => { '!=' => 'Inactive' },
            },
            {
                join     => ['person'],
                prefetch => ['person'],
                order_by => ['person.last', 'person.first' ],
            }
        );
        if ($exclude_lapsed) {
            @members = grep { ! $_->lapsed() } @members;
        }
    }
    my @files = <$omp_dir/*>;
    stash($c,
        pat      => $pat,
        excluded => $exclude_lapsed,
        online   => scalar(@files),
        members  => \@members,
        template => "member/list.tt2",
    );
}

# show the current online files
# get the Member's name, category of payment, etc
sub list_online : Local {
    my ($self, $c) = @_;

    my @files = <$omp_dir/*>;
    my @payments;
    for my $f (@files) {
        my $g = $f;
        $g =~ s{$omp_dir/}{}xms;
        my ($id, $amount, $trans_id) = split '_', $g;
        my $m = model($c, 'Member')->find($id);
        if ($m) {
            my $p = $m->person;
            if ($p) {
                my $name = $p->first . ' ' . $p->last;
                push @payments, {
                    name     => $name,
                    file     => $g,
                    amount   => $amount,
                    category => $m->category,
                };
            }
        }
    }
    stash($c,
        payments => \@payments,
        template => "member/online.tt2",
    );
}

sub get_online : Local {
    my ($self, $c, $file) = @_;

    my ($id, $amount, $trans_id) = split '_', $file;
    __PACKAGE__->update($c, $id, $amount, $file);
    return;
}

sub update : Local {
    my ($self, $c, $id, $amount, $file) = @_;

    $amount ||= '';
    $file ||= '';

    my $m = model($c, 'Member')->find($id);
    for my $w (qw/
        general
        sponsor
        life
        founding_life
        resident
        inactive
    /) {
        my $cat = lc $m->category();
        $c->stash->{"category_$w"} =
            (substr($cat, 0, 3) eq substr($w, 0, 3))? "checked"
            :                                         ""
            ;
    }
    my $type_opts = "";
    for my $t (qw/ D C S O /) {
        $type_opts .= "<option value=$t"
                   .  (($t eq 'O' && $file)? " selected": "")
                   .  ">"
                   .  $string{"payment_$t"}
                   .  "\n";
                   ;
    }
    my $today = tt_today($c);
    my $offset = $today->month <= 11? 0: 1;
    my $payment_date = 't';
    if ($file) {
        my $sb = stat("$omp_dir/$file");       # see File::stat
        my ($day, $month, $year) = (localtime $sb->mtime)[3..5];
        ++$month;
        $year += 1900;
        $payment_date = sprintf("%d/%d/%d", $month, $day, $year);
    }
    stash($c,
        type_opts         => $type_opts,
        amount            => $amount,
        payment_date      => $payment_date,
        file              => $file,
        member            => $m,
        year              => ($today->year + $offset) % 100,
        free_prog_checked => (($m->free_prog_taken)? "checked": ''),
        person            => $m->person(),
        voter_checked     => $m->voter()? "checked": '',
        form_action       => "update_do/$id",
        template          => "member/create_edit.tt2",
    );
}

my %P;
my @mess;
sub _get_data {
    my ($c) = @_;

    %P = %{ $c->request->params() };
    $P{voter} = "" unless exists $P{voter};
    @mess = ();
    if (! $P{category}) {
        push @mess, "You must select General, Sponsor, Life, Founding Life, Resident, or Inactive";
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
    if ($P{mkpay_amount} && $P{mkpay_date}) {
        if ($P{mkpay_amount} !~ m{^\s*-?\d+\s*$}) {
            push @mess, "Invalid payment amount";
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
    if ($P{category} && $P{category} eq 'General'
        && ! $P{date_general}
        && ! $P{valid_to}
    ) {
        push @mess, "Missing General date";
    }
    if ($P{category} && $P{category} eq 'Sponsor'
        && ! $P{date_sponsor}
        && ! $P{valid_to}
    ) {
        push @mess, "Missing Sponsor date";
    }
    if ($P{category} && $P{category} =~ m{\A(General|Resident)\z}xms ) {
        $P{sponsor_nights} = 0;
        $P{free_prog_taken} = '';
    }
    else {
        $P{sponsor_nights} = trim($P{sponsor_nights});
        if ($P{sponsor_nights} !~ m{^\d+$}) {
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
# and the amount will keep changing - now (12/1/13) it is $12,000
#
sub update_do : Local {
    my ($self, $c, $id) = @_;

    _get_data($c);
    return if @mess;

    my $pay_date   = $P{mkpay_date};
    my $pay_type   = $P{mkpay_type};
    my $amount     = $P{mkpay_amount};
    my $valid_from = $P{valid_from};
    my $valid_to   = $P{valid_to};
    my $transaction_id = '';
    if ($P{file}) {
        ($transaction_id) = (split '_', $P{file})[2];
        rename "$omp_dir/$P{file}", "${omp_dir}_done/$P{file}";
    }

    if (! $amount) {
        $valid_to = undef;
            # no payment was made
            # don't use the default valid_to date...
        delete $P{date_general};
        delete $P{date_sponsor};
    }

    delete $P{file};
    delete $P{mkpay_date};
    delete $P{mkpay_type};
    delete $P{mkpay_amount};
    delete $P{valid_from};
    delete $P{valid_to};

    my $member = model($c, 'Member')->find($id);
    my @who_now = get_now($c);

    if ($amount && $pay_date) {
        # put payment in history, reset last paid

        model($c, 'SponsHist')->create({
            member_id    => $id,
            date_payment => $pay_date,
            valid_from   => $valid_from,
            valid_to     => $valid_to,
            amount       => $amount,
            type         => $pay_type,
            general      => $P{category} eq 'General' 
                            && $amount <= $string{mem_gen_amt}? 'yes': '',
            transaction_id => $transaction_id,
            @who_now,
        });
        _xaccount_mem_pay($c, $member->person_id,
                          $amount, $pay_date, $P{category}, $pay_type);
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

    if ($P{sponsor_nights}
        && $member->sponsor_nights() != $P{sponsor_nights}
    ) {
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
            && (!$P{date_general}
                || $P{date_general} == $member->date_general())
        ) {
            $P{date_general} = $valid_to;
        }
        if ($P{category} eq 'Sponsor'
            && (!$P{date_sponsor}
                || $P{date_sponsor} == $member->date_sponsor())
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

    #
    # make sure the HFS Member affils are correct
    #
    _adjust_affils($c, $member);

    if (!$amount) {
        $c->response->redirect($c->uri_for("/member/view/$id"));
        return;
    }

    Global->init($c);
    my $html = acknowledge($c, $member, $amount, $pay_date, 0);
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

sub _adjust_affils {
    my ($c, $member) = @_;

    #
    # clear all HFS Member affils for the person
    #
    my $p_id = $member->person_id;
    model($c, 'AffilPerson')->search({
        p_id => $p_id,
        a_id => { -in => \@hfs_affil_ids },
    })->delete();

    # add the correct ones
    my @a_ids;
    if ($member->voter()) {
        push @a_ids, $system_affil_id_for{"HFS Member Voter"};
    }
    if ($member->lapsed()) {
        push @a_ids, $system_affil_id_for{'HFS Member Lapsed'};
    }
    else {
        push @a_ids, $system_affil_id_for{"HFS Member " . $member->category()};
    }
    for my $a_id (@a_ids) {
        model($c, 'AffilPerson')->create({
            a_id => $a_id,
            p_id => $p_id,
        });
    }
}

sub _no_here {
    my ($html) = @_;
    $html =~ s{<a[^>]*>here</a>[.]}{ on the HFS website:<ul>www.hanumanfellowship.org</ul>};
    $html;
}

sub js_print {
    "<script type='text/javascript'>window.print()</script>";
}

sub acknowledge {
    my ($c, $member, $amount, $pay_date, $new_member) = @_;

    my $person   = $member->person;
    my $category = $member->category;
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
        new_member   => $new_member,
        sanskrit     => ($person->sanskrit || $person->first),
        amount       => $amount,
        pay_date     => date($pay_date),
        due_date     => date($P{date_sponsor}),     # not needed for General
        next         => $amount,
        year         => $category eq 'General'? date($P{date_general})->year()
                        :                       date($P{date_sponsor})->year(),
        subtot       => $member->total_paid(),
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
    $m->nighthist()->delete();
    $m->delete();
    $c->response->redirect($c->uri_for('/member/list'));
}

sub create : Local {
    my ($self, $c, $person_id) = @_;

    my $type_opts = "";
    for my $t (qw/ D C S O /) {
        $type_opts .= "<option value=$t>"
                   .  $string{"payment_$t"}
                   .  "\n";
                   ;
    }
    stash($c,
        year          => (tt_today($c)->year) % 100,
        person        => model($c, 'Person')->find($person_id),
        form_action   => "create_do/$person_id",
        voter_checked => '',
        type_opts     => $type_opts,
        template      => "member/create_edit.tt2",
    );
}

sub create_do : Local {
    my ($self, $c, $person_id) = @_;

    _get_data($c);
    return if @mess;

    my $mkpay_date = $P{mkpay_date};
    my $pay_type = $P{mkpay_type};
    my $amount     = $P{mkpay_amount};
    my $valid_from = $P{valid_from};
    my $valid_to   = $P{valid_to};

    delete $P{mkpay_date};
    delete $P{mkpay_type};
    delete $P{mkpay_amount};
    delete $P{valid_from};
    delete $P{valid_to};
    delete $P{file};        # from the hidden field - used for online payments

    if ($P{category} eq 'General' && ! $P{date_general}) {
        $P{date_general} = $valid_to;
    }
    if ($P{category} eq 'Sponsor' && ! $P{date_sponsor}) {
        $P{date_sponsor} = $valid_to;
    }

    $P{total_paid} = $amount || 0;

    my $member = model($c, 'Member')->create({
        person_id    => $person_id,
        %P,
    });

    #
    # add the Guru Purnima affiliation to the Person
    # if it is not already there.
    # it was renamed to 'MMC Annual Yoga Retreats'
    #
    my @affils = model($c, 'AffilPerson')->search({
        a_id => $system_affil_id_for{'MMC Annual Yoga Retreats'},
        p_id => $person_id,
    });
    if (! @affils) {
        model($c, 'AffilPerson')->create({
            a_id => $system_affil_id_for{'MMC Annual Yoga Retreats'},
            p_id => $person_id,
        });
    }

    #
    # make sure the HFS Member affils are correct
    #
    _adjust_affils($c, $member);

    my $id = $member->id();
    my @who_now = get_now($c);

    # put any payment in history
    if ($amount && $mkpay_date) {
        model($c, 'SponsHist')->create({
            member_id    => $id,
            date_payment => $mkpay_date,
            valid_from   => $valid_from,
            valid_to     => $valid_to,
            amount       => $amount,
            type         => $pay_type,
            general      => $P{category} eq 'General'? 'yes': '',
            transaction_id => '',
            @who_now,
        });
        _xaccount_mem_pay($c, $person_id,
                          $amount, $mkpay_date, $P{category}, $pay_type);
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
    if ($P{category} eq 'Life' || $P{category} eq 'Founding Life') {
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
    my $html = acknowledge($c, $member, $amount, $mkpay_date, 1);
    
    my $pers = $member->person();
    if ($pers->email()) {
        email_letter($c,
            to      => $pers->name_email(),
            from    => "HFS Membership <$string{mem_email}>",
            subject => "Hanuman Fellowship Membership Payment",
            html    => $html,
            which   => "Membership Payment for " . $pers->name,
        );
        $c->response->redirect($c->uri_for("/member/view/$id/1"));
    }
    else {
        $c->res->output(_no_here($html) . js_print());
    }
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
        include_lapsed_checked => 'checked',
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
        push @memtypes, 'Life', 'Founding Life';
        $life = 1;
    }
    my $count = $c->request->params->{count};
    my $mmc = $c->request->params->{mmc};
    my $email = $c->request->params->{type} eq 'email';
    my $include_lapsed = $c->request->params->{include_lapsed};
    open my $list, ">", "/var/Reg/report/memlist.txt"
        or die "cannot create memlist.txt: $!\n";
    my @people;
    my $n = 0;
    MEMBER:
    for my $m (model($c, 'Member')->search({
                   category => { 'in', \@memtypes },
               })
    ) {
        if (! $include_lapsed && $m->lapsed) {
            next MEMBER;
        }
        my $p = $m->person;
        if ($p->akey eq '44595076SUM') {
            next MEMBER if $mmc eq 'exclude';
        }
        else {
            next  MEMBER if $mmc eq 'only';
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
        PERSON:
        for my $p (@people) {
            next PERSON if ! $p->id_sps || ! exists $partner{$p->id_sps};
            my $sps = $partner{$p->id_sps};
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
            include_lapsed_checked => ($include_lapsed)? 'checked': '',
            exclude_checked => ($mmc eq 'exclude')? "checked": "",
            only_checked    => ($mmc eq 'only'   )? "checked": "",
            email_checked   => ($email  )? "checked": "",
            snail_checked   => (! $email)? "checked": "",
        );
    }
    else {
        $c->response->redirect($c->uri_for("/report/show_report_file/memlist.txt"));
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
            category => { '!=' => 'Founding Life' },
            category => { '!=' => 'Inactive' }
        })
    ];
    $c->stash->{template} = "member/non_email.tt2";
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
    my $type_opts = "";
    for my $t (qw/ D C S O /) {
        $type_opts .= "<option value=$t"
                   .  (($pmt->type() eq $t)? " selected": "")
                   .  ">"
                   .  $string{"payment_$t"}
                   .  "\n";
                   ;
    }
    stash($c,
        type_opts => $type_opts,
        payment   => $pmt,
        template  => "member/payment_edit.tt2",
    );
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
    my $type = $c->request->params->{type};
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
        type         => $type,
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

sub _xaccount_mem_pay {
    my ($c, $person_id, $amount, $pay_date, $category, $pay_type) = @_;

    my ($xacct) = model($c, 'XAccount')->search({
        descr => "Membership",
    });
    # The above will work, right?
    # Too much trouble to return an error.
    #
    model($c, 'XAccountPayment')->create({
        xaccount_id => $xacct->id,
        person_id   => $person_id,
        amount      => $amount,
        type        => $pay_type,
        what        => "$category Membership",

        user_id     => $c->user->obj->id,
        the_date    => today()->as_d8(),
        time        => get_time()->t24(),
    });
}

sub auto_mailings : Local {
    my ($self, $c) = @_;
    stash($c,
        template  => "member/auto_mailings.tt2",
    );
}

sub dec10gen : Local {
    my ($self, $c) = @_;
    my $tt = Template->new({
        INTERPOLATE  => 1,
        INCLUDE_PATH => 'root/static/templates/letter',
        EVAL_PERL    => 0,
    });
    my $exp_year = (localtime)[5] + 1900;
    my $html;
    $tt->process(
        "lapse_gen_soon.tt2",# template
        {
            sanskrit => 'Sanskrit',
            string   => \%string,
            exp_year => $exp_year,
            has_email => 1,
            secure_code => 'xxxx',
        },
        \$html,           # output
    ) or die $tt->error;
    $c->res->output($html);
}

sub dec10spons : Local {
    my ($self, $c) = @_;
    my $tt = Template->new({
        INTERPOLATE  => 1,
        INCLUDE_PATH => 'root/static/templates/letter',
        EVAL_PERL    => 0,
    });
    my $exp_year = (localtime)[5] + 1900;
    my $html;
    $tt->process(
        "lapse_spons_soon.tt2",# template
        {
            sanskrit => 'Sanskrit',
            string   => \%string,
            exp_year => $exp_year,
            has_email => 1,
            secure_code => 'xxxx',
        },
        \$html,           # output
    ) or die $tt->error;
    $c->res->output($html);
}

sub dec20 : Local {
    my ($self, $c) = @_;
    my $tt = Template->new({
        INTERPOLATE  => 1,
        INCLUDE_PATH => 'root/static/templates/letter',
        EVAL_PERL    => 0,
    });
    my $html;
    $tt->process(
        "lapse.tt2",# template
        {
            sanskrit => 'Sanskrit',
            string   => \%string,
        },
        \$html,           # output
    ) or die $tt->error;
    $c->res->output($html);
}

1;
