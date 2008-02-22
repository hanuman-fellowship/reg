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
    my @lapsed =
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
            { category => 'Lapsed', },
        );
    my $nlapsed = @lapsed;
    open my $list, ">", "root/static/memlist.html"
        or die "cannot create memlist.html";
    print {$list} <<EOH;
<h2>Hanuman Fellowship Membership List</h2>
<h3>Counts</h3>
<table cellpadding=3>
<tr><td>General</td><td>$ngeneral</td></tr>
<tr><td>Sponsor</td><td>$nsponsor</td></tr>
<tr><td>Life</td><td>$nlife</td></tr>
<tr><td>Lapsed</td><td>$nlapsed</td></tr>
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
<h3>Lapsed</h3>
<table cellpadding=3>
<tr>
<th align=left>Sanskrit</th>
<th align=left>Name</th>
<th>On</th>
</tr>
EOH
    for my $m (@lapsed) {
        my $p = $m->person;
        print {$list} "<tr>";
        print {$list} "<td>", $p->sanskrit || $p->first, "</td>";
        print {$list} "<td>" . $p->last . ", " . $p->first . "</td>";
        print {$list} "<td>" . date($m->date_lapsed) . "</td>";
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

    #
    # before getting the list, look for lapsed people.
    #
    my $today = today()->as_d8();
    model($c, 'Member')->search({
        category     => 'General',
        date_general => { '<' => $today },
    })->update({
        category    => 'Lapsed',
        date_lapsed => $today,
    });
    model($c, 'Member')->search({
        category     => 'Sponsor',
        date_sponsor => { '<' => $today },
    })->update({
        category    => 'Lapsed',
        date_lapsed => $today,
    });
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

    my $m = $c->stash->{member} = 
        model($c, 'Member')->find($id);
    for my $w (qw/
        general
        sponsor
        life
        lapsed
    /) {
        $c->stash->{"category_$w"} = ($m->category eq ucfirst($w))? "checked": "";
    }
    $c->stash->{free_prog_checked} = ($m->free_prog_taken)? "checked": "";
    my @payments = $m->payments();
    if (@payments) {
        $c->stash->{payments} = \@payments;
    }

    $c->stash->{person} = $m->person();
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
        $hash{category} = 'General';    # strange to need to do this.
    }
    # dates are either blank or converted to d8 format
    if ($hash{category} eq 'General'
        && $hash{date_general}
        && $hash{date_general} !~ m{\S}
    ) {
        push @mess, "Missing general date";
    }
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
            push @mess, "No paid amount";
        }
        if (! $hash{mkpay_date}) {
            push @mess, "No paid date";
        }
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "member/error.tt2";
    }
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

    my $today = today()->as_d8();
    my $partnered = 0;
    my $id_sps;
    my $partner_member;
    my $partner_paid = 0;
    my @nowlife = ();
    if ($hash{mkpay_date}) {
        # put payment in history, reset last paid
        model($c, 'SponsHist')->create({
            member_id    => $id,
            date_payment => $hash{mkpay_date},
            amount       => $hash{mkpay_amount},
        });
        $hash{category} = 'Sponsor';
        if ($member->category() ne 'Sponsor') {
            $hash{sponsor_nights} = 12;     # String???
        }

        # recompute the total
        my $total = 0;
        for my $p (model($c, 'SponsHist')->search({
                       member_id => $id,
                   })
        ) {
            $total += $p->amount;
        }
        $hash{total_paid} = $total;
        # partner???
        if ($id_sps = $member->person->id_sps) {
            $partnered = 1;
            # is the partner a member?
            # if so, how much have they paid?
            ($partner_member) = model($c, 'Member')->search({
                                    person_id => $id_sps,
                                });
            if ($partner_member) {
                $partner_paid = $partner_member->total_paid;
            }
        }
        if ($hash{total_paid} >= 5000
            || $hash{total_paid} + $partner_paid >= 8000
        ) {
            $hash{category} = 'Life';
            $hash{date_life} = $today;
            push @nowlife, $member;
        }
    }

    # update the member record
    delete $hash{mkpay_date};
    delete $hash{mkpay_amount};
    $member->update(\%hash);
    # and the partner record if need be
    if ($partnered
        && $hash{total_paid} + $partner_paid >= 8000
    ) {
        if ($partner_member) {
            push @nowlife, $partner_member;
            if ($partner_member->category ne "Life") {
                $partner_member->update({
                    category => 'Life',
                    date_life => $hash{date_life},
                });
            }
        }
        else {
            # this person has paid everything >= 8000
            # make their partner a Life member.
            #
            $partner_member = model($c, 'Member')->create({
                person_id => $id_sps,
                category  => 'Life',
                date_life => $hash{date_life},
            });
            push @nowlife, $partner_member;
        }
    }
    if (@nowlife) {
        my $mess = join " and ",
                   map { $_->person->sanskrit || $_->person->first }
                   @nowlife;
        if (@nowlife == 1) {
            $mess .= " is now a Life member.";
        }
        else {
            $mess .= " are now Life members.";
        }
        $c->stash->{mess} = $mess;
        $c->stash->{template} = "member/nowlife.tt2";
        return;
    }
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

    $c->stash->{person}
        = model($c, 'Person')->find($person_id);
    $c->stash->{form_action} = "create_do/$person_id";
    $c->stash->{template}    = "member/create_edit.tt2";
}

sub create_do : Local {
    my ($self, $c, $person_id) = @_;

    _get_data($c);
    return if @mess;
    my @nowlife = ();
    my $today = today()->as_d8();
    if ($hash{mkpay_date}) {
        $hash{category} = 'Sponsor';

        $hash{total_paid} = $hash{mkpay_amount};;
        if ($hash{total_paid} >= 5000) {
            $hash{category} = 'Life';
            $hash{date_life} = $today;
        }
        # we are creating this person as a member now.
        # are they part of a partnership?
        # it is possible that their partner is already a
        # member.  we'll need to consider that partner's payments.
        # they both may have just become life members.
        # if only one of a partnership is paying, is the other
        # a current sponsoring member or not?
        my $person = model($c, 'Person')->find($person_id);
        my $partner_paid = 0;
        if (my $id_sps = $person->id_sps) {
            my $partner = model($c, 'Person')->find($id_sps);
            my ($partner_member) = model($c, 'Member')->search({
                                             person_id => $id_sps,
                                         });
            if ($partner_member) {
                $partner_paid = $partner_member->total_paid;
            }
            if ($hash{total_paid} + $partner_paid >= 8000) {
                # both are now Life members

                # this person: (created below)
                $hash{category} = 'Life';
                $hash{date_life} = $today;

                # and their partner:
                if ($partner_member) {
                    # they were a member before maybe even a life member.
                    if ($partner_member->category ne "Life") {
                        $partner_member->update({
                            category  => 'Life',
                            date_life => $today,
                        });
                    }
                }
                else {
                    # the partner is now a Life member
                    # they were not a member before.
                    $partner_member = model($c, 'Member')->create({
                        person_id => $id_sps,
                        category  => 'Life',
                        date_life => $today,
                    });
                }
                unshift @nowlife, $partner_member;
            }
        }
    }
    my $date = $hash{mkpay_date};
    my $amnt = $hash{mkpay_amount};
    delete $hash{mkpay_date};
    delete $hash{mkpay_amount};
    if ($hash{category} eq 'Sponsor') {
        $hash{sponsor_nights} = 12;     # ??? a String???
    }
    my $member = model($c, 'Member')->create({
        person_id    => $person_id,
        %hash,
    });
    if ($hash{category} eq 'Life') {
        unshift @nowlife, $member;
    }
    my $id = $member->id();
    # put payment in history
    if ($date) {
        model($c, 'SponsHist')->create({
            member_id    => $id,
            date_payment => $date,
            amount       => $amnt,
        });
    }
    if (@nowlife) {
        my $mess = join " and ",
                   map { $_->person->sanskrit || $_->person->first }
                   @nowlife;
        if (@nowlife == 1) {
            $mess .= " is now a Life member.";
        }
        else {
            $mess .= " are now Life members.";
        }
        $c->stash->{mess} = $mess;
        $c->stash->{template} = "member/nowlife.tt2";
        return;
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
