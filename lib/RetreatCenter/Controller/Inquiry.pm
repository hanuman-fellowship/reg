use strict;
use warnings;
package RetreatCenter::Controller::Inquiry;
use base 'Catalyst::Controller';

use lib '../..';
use Util qw/
    model
    stash
    housing_types
/;
use Date::Simple qw/
    date
/;
use Time::Simple qw/
    get_time
/;
use Global qw/
    %string
/;

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('list');
}

#
# order is date (default), leader, status, how_many
#
sub list : Local {
    my ($self, $c, $order) = @_;
    $order ||= 'status';

    my @inq = model($c, 'Inquiry')->all();
    if ($order eq 'leader') {
        @inq = sort { $a->leader_name cmp $b->leader_name } @inq;
    }
    elsif ($order eq 'date') {
        @inq = sort { $b->the_date <=> $a->the_date } @inq;
    }
    elsif ($order eq 'how_many') {
        @inq = map {
                   $_->[1]
               }
               sort {
                   $b->[0] <=> $a->[0];
               }
               map {
                   [ $_->how_many =~ m{\A (\d+)}xms, $_ ] 
               }
               @inq
               ;
    }
    elsif ($order eq 'status') {
        no warnings;
        my %status_order = qw/
            0 0   # new
            1 5   # contacted
            2 3   # engaged
            3 7   # denied by Host
            4 8   # denied by MMC
            5 4   # tentative
            6 6   # rental
            7 2   # priority
            8 1   # dates proposed
        /;
        @inq = map {
                   $_->[0]
               }
               sort {
                   $a->[1] <=> $b->[1]
                   ||
                   $b->[2] <=> $a->[2]
                   ||
                   $b->[3] <=> $a->[3]
               }
               map {
                   [
                       $_,
                       $status_order{$_->status},
                       $_->how_many =~ m{\A (\d+)}xms,
                       $_->the_date,
                   ]
               }
               @inq;
    }
    stash($c,
        st        => { $order => "style='color: green'" },
        order     => $order,
        inquiries => \@inq,
        template  => "inquiry/list.tt2",
    );
    $c->stash->{inquiries} = \@inq;
    $c->stash->{template} = "inquiry/list.tt2";
}

sub view : Local {
    my ($self, $c, $inq_id) = @_;
    my $inq = model($c, 'Inquiry')->find($inq_id);
    my $notes = $inq->notes();

    # not needed?
    # $notes =~ s{\n}{<br>\n}xmsg;

    stash($c,
        inquiry  => $inq,
        notes    => $notes,
        template => 'inquiry/view.tt2',
    );
}

sub notes : Local {
    my ($self, $c, $inq_id) = @_;
    my $inq = model($c, 'Inquiry')->find($inq_id);
    my $notes = $inq->notes();
    my $nrows = $notes? $notes =~ tr/\n//: 0;
    stash($c,
        inquiry  => $inq,
        nrows    => $nrows + 3,
        template => 'inquiry/notes_view.tt2',
    );
}

sub notes_do : Local {
    my ($self, $c, $inq_id) = @_;
    my $inq = model($c, 'Inquiry')->find($inq_id);
    my $notes = $c->request->params->{notes};
    my $s = $notes;
    $s =~ s{<[^>]*>}{}xmsg;
    if ($s =~ m{\A \s* duplicate}xmsi) {
        $inq->delete();
        $c->response->redirect($c->uri_for("/inquiry/list/date"));
    }
    else {
        $inq->update({
            notes => $c->request->params->{notes},
        });
        $c->response->redirect($c->uri_for("/inquiry/view/$inq_id"));
    }
}

sub change_status : Local {
    my ($self, $c, $inq_id) = @_;
    my $inq = model($c, 'Inquiry')->find($inq_id);
    my @statuses = $inq->statuses(); 
    my $status_opts = '';
    for my $i (0 .. $#statuses) {
        my $selected = $i == $inq->status? ' selected': '';
        $status_opts .= "<option value=$i$selected>$statuses[$i]</option>\n";
    }
    stash($c,
        inquiry  => $inq,
        nstatus => scalar(@statuses),
        status_opts => $status_opts,
        template => 'inquiry/change_status_view.tt2',
    );
}

sub change_status_do : Local {
    my ($self, $c, $inq_id) = @_;
    my $inq = model($c, 'Inquiry')->find($inq_id);
    $inq->update({
        status => $c->request->params->{new_status},
    });
    $c->response->redirect($c->uri_for("/inquiry/list/status"));
}

sub export : Local {
    my ($self, $c) = @_;
    open my $out, '>', "/var/Reg/report/inquiry.csv";
    print {$out} join "\t", map { my $s = $_; $s =~ s{_}{ }xmsg; $s; } qw/
        Date Time Leader Phone Email
        Notes Status
        Group_Name Dates Description
        How_Many Vegetarian Retreat_Type
        Needs How_Learn What_Else
    /;
    print {$out} "\n";
    for my $inq (model($c, 'Inquiry')->search(
                     {},
                     { order_by => 'the_date, the_time' },
                 )
    ) {
        print {$out} $inq->csv, "\n";
    }
    close $out;
    $c->response->redirect($c->uri_for("/report/show_report_file/inquiry.csv"));
}

#
# copied/modified from Proposal->approve
#
sub mkrental : Local {
    my ($self, $c, $id) = @_;

    my $inquiry = model($c, 'Inquiry')->find($id);

    # fill in the stash in preparation for
    # the creation of a rental.  code copied from Rental->create().
    stash($c,
        dup_message => " - <span style='color: red'>From Inquiry</span>",
            # see comment in Program.pm
        check_linked    => "",
        check_tentative => "checked",
        housecost_opts  =>
            [ model($c, 'HouseCost')->search(
                undef,
                { order_by => 'name' },
            ) ],
        rental => {     # double faked object
            housecost => { name => "Default" },
            name           => $inquiry->group_name(),
            coordinator_id => $inquiry->person_id,
            cs_person_id   => $inquiry->person_id,
                # not sure how the following works...
            start_hour_obj => get_time("4:00 pm"),  # ???
            end_hour_obj   => get_time("12:00 pm"),
            title          => $inquiry->group_name,
            badge_title    => $inquiry->group_name,
            balance        => 0,
        },
        check_mp_deposit     => 'checked',
        check_new_contract   => 'checked',
        h_types     => [ housing_types(1) ],
        string      => \%string,
        section     => 1,   # web
        template    => "rental/create_edit.tt2",
        form_action => "create_from_inquiry/$id",
    );
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
