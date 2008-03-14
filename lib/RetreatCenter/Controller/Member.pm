use strict;
use warnings;
package RetreatCenter::Controller::Member;
use base 'Catalyst::Controller';

use Mail::SendEasy;

use lib '../../';       # so you can do a perl -c here.
use Util qw/trim model/;
use Date::Simple qw/date today/;

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('list');
}

# to root/static file and then load that file in the browser.
sub membership_list : Local {
    my ($self, $c) = @_;
    
    # ??? must be a way to collapse this repetitive code.
    # for my $c (qw/ General Sponsor Life Lapsed /) { ...
    my @general =
        map {
            $_->[1]
        }
        sort {
            $a->[0] cmp $b->[0]
        }
        map {
            [ $_->person->sanskrit || $_->person->first, $_ ]
        }
        model($c, 'Member')->search(
            { category => 'General', },
        );
    my $ngeneral = @general;
    my @sponsor =
        map {
            $_->[1]
        }
        sort {
            $a->[0] cmp $b->[0]
        }
        map {
            [ $_->person->sanskrit || $_->person->first, $_ ]
        }
        model($c, 'Member')->search(
            { category => 'Sponsor', },
        );
    my $nsponsor = @sponsor;
    my @life =
        map {
            $_->[1]
        }
        sort {
            $a->[0] cmp $b->[0]
        }
        map {
            [ $_->person->sanskrit || $_->person->first, $_ ]
        }
        model($c, 'Member')->search(
            { category => 'Life', },
        );
    my $nlife = @life;
    open my $list, ">", "root/static/memlist.html"
        or die "cannot create memlist.html";
    print {$list} <<EOH;
<h2>Hanuman Fellowship Membership List</h2>
<h3>Counts</h3>
<table cellpadding=3>
<tr><td>General</td><td>$ngeneral</td></tr>
<tr><td>Sponsor</td><td>$nsponsor</td></tr>
<tr><td>Life</td><td>$nlife</td></tr>
</table>
<h3>General</h3>
<table cellpadding=3>
<tr>
<th align=left>Sanskrit</th>
<th align=left>Name</th>
<th>Expires</th>
</tr>
EOH
    for my $m (@general) {
        my $p = $m->person;
        print {$list} "<tr>";
        print {$list} "<td>", $p->sanskrit || $p->first, "</td>";
        print {$list} "<td>" . $p->last . ", " . $p->first . "</td>";
        print {$list} "<td>" . date($m->date_general) . "</td>";
        print {$list} "</tr>\n";
    }
    print {$list} <<EOH;
</table>
<h3>Sponsor</h3>
<table cellpadding=3>
<tr>
<th align=left>Sanskrit</th>
<th align=left>Name</th>
<th align=center>Last Paid</th>
<th align=right>Total</th>
</tr>
EOH
    for my $m (@sponsor) {
        my $p = $m->person;
        print {$list} "<tr>";
        print {$list} "<td>", $p->sanskrit || $p->first, "</td>";
        print {$list} "<td>" . $p->last . ", " . $p->first . "</td>";
        print {$list} "<td align=center>" . date($m->date_sponsor) . "</td>";
        print {$list} "<td align=right>" . $m->total_paid . "</td>";
        print {$list} "</tr>\n";
    }
    print {$list} <<EOH;
</table>
<h3>Life</h3>
<table cellpadding=3>
<tr>
<th align=left>Sanskrit</th>
<th align=left>Name</th>
<th>As Of</th>
</tr>
EOH
    for my $m (@life) {
        my $p = $m->person;
        print {$list} "<tr>";
        print {$list} "<td>", $p->sanskrit || $p->first, "</td>";
        print {$list} "<td>" . $p->last . ", " . $p->first . "</td>";
        print {$list} "<td>" . date($m->date_life) . "</td>";
        print {$list} "</tr>\n";
    }
    print {$list} <<EOH;
</table>
EOH
    close $list;
    $c->response->redirect($c->uri_for("/static/memlist.html"));
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
            [ $_->person->sanskrit || $_->person->first, $_ ]
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
        if ($hash{sponsor_nights} !~ m{^\d+$}) {
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
    # can't get id directly???
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
# this is a perfect example of how software engineers
# need to take care of all the weird cases - no matter how rare.
#
# Life members also have sponsor_nights :( ???
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

    $c->response->redirect($c->uri_for("/member/list"));
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
            action     => 3,
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
    $c->response->redirect($c->uri_for("/member/list"));
}

sub email_all : Local {
    my ($self, $c) = @_;

    my $mail = Mail::SendEasy->new(
        smtp => 'mail.logicalpoetry.com:50',
        user => 'jon@logicalpoetry.com',
        pass => 'hello!',
    );

    my $today = today();
    my $month2 = $today + 60;
    my @sponsor =
        model($c, 'Member')->search({
            date_sponsor => { '<', $month2->as_d8() },
        });
    for my $sp (@sponsor) {
        my $per = $sp->person;
        my $name = $per->first . ' ' . $per->last;
        my $email = $per->email;
        my $sp_date = date($sp->date_sponsor);

        my $verb = ($sp_date < $today)? "expired": "will expire";
        my @payments = $sp->payments();
        my $last_amount  = $payments[0]->amount;
        my $last_paid = date($payments[0]->date_payment);
        my $mem_admin = $c->user->first . ' ' . $c->user->last;
        # Strings???
        my $status = $mail->send(
            subject => "Sponsor Membership in the Hanuman Fellowship",
            #to => 'Jonny <jon@suecenter.org>',
            to => $email,
            from => $c->user->email,
            msg => <<"EOM",
Dear $name,

Your sponsor membership $verb on $sp_date.
You last paid \$$last_amount on $last_paid.

Sincerely,
$mem_admin
Membership Administrator
EOM
        );

        if (! $status) {
            $c->log->info('mail error: ' . $mail->error);
        }
    }

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
    model($c, 'Member')->search({
        category => { 'in' => [ 'Sponsor', 'Life' ] },
    })->update({
        sponsor_nights  => 12,      # String???
        free_prog_taken => '',
    });
    $c->response->redirect($c->uri_for("/member/list"));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
