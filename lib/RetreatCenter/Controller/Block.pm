use strict;
use warnings;
package RetreatCenter::Controller::Block;
use base 'Catalyst::Controller';

use lib '../..';
use Util qw/
    empty
    model
    trim
    error
    tt_today
    stash
/;
use Date::Simple qw/
    date
    today
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
# who is doing this?  and what's the current date/time?
#
sub _get_now {
    my ($c) = @_;

    return
        user_id  => $c->user->obj->id,
        the_date => tt_today($c)->as_d8(),
        time     => get_time()->t24()
        ;
    # we return an array of 6 values perfect
    # for passing to a DBI insert/update.
}
#
# show future blocks
#
sub list : Local {
    my ($self, $c) = @_;

    stash($c,
        pg_title => "Blocks",
        blocks => [ model($c, 'Block')->search(
            {
                sdate => { '>=' => today()->as_d8() },
            },
            {
                order_by => 'sdate'
            }
        ) ],
        template => "block/list.tt2",
    );
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    # vacate first - config

    model($c, 'Block')->find($id)->delete();
    Global->init($c, 1);
    $c->response->redirect($c->uri_for('/block/list'));
}

my %P;
my @mess;
my $edate1;
sub _get_data {
    my ($c) = @_;

    %P = %{ $c->request->params() };
    @mess = ();
    if (empty($P{h_name})) {
        push @mess, "Missing House Name";
    }
    else {
        my ($house) = model($c, 'House')->search({
            name => $P{h_name},
        });
        if (! $house) {
            push @mess, "Invalid House Name: $P{h_name}";
        }
        else {
            delete $P{h_name};
            $P{house_id} = $house->id();
        }
    }
    if (empty($P{sdate})) {
        push @mess, "Missing Start Date";
    }
    else {
        my $dt = date($P{sdate});
        if ($dt) {
            $P{sdate} = $dt->as_d8();
        }
        else {
            push @mess, "Invalid Start Date: $P{sdate}";
        }
    }
    if (empty($P{edate})) {
        push @mess, "Missing End Date";
    }
    else {
        Date::Simple->relative_date(date($P{sdate}));
        my $dt = date($P{edate});
        Date::Simple->relative_date();
        if ($dt) {
            $P{edate} = $dt->as_d8();
            $edate1 = ($dt-1)->as_d8();
        }
        else {
            push @mess, "Invalid End Date: $P{edate}";
        }
    }
    if (! @mess && $P{sdate} > $P{edate}) {
        push @mess, "Start date must be before the End date";
    }
    if ($P{nbeds} !~ m{^\d+$} && $P{nbeds} > 0) {
        push @mess, "Invalid Number of Beds: $P{nbeds}";
    }
    if (empty($P{reason})) {
        push @mess, "Missing Reason";
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "block/error.tt2";
    }
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $block = $c->stash->{block} = model($c, 'Block')->find($id);
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "block/create_edit.tt2";
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    _get_data($c);
    return if @mess;
    my $block = model($c, 'Block')->find($id);

    # if nothing changed - do nothing
    # see if new space is available.
    # vacate old, reconfig new
    # else give error

    $block->update({
        %P,
        _get_now($c),
    });
    Global->init($c, 1);
    $c->response->redirect($c->uri_for("/block/list"));
}

sub create : Local {
    my ($self, $c) = @_;

    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "block/create_edit.tt2";
}

sub create_do : Local {
    my ($self, $c) = @_;

    _get_data($c);
    return if @mess;
    #
    # is the space actually available?
    # search for exceptions
    #
    my $s = "< cur + $P{nbeds}";
    my @config = model($c, 'Config')->search({
        house_id => $P{house_id},
        the_date => { -between => [ $P{sdate}, $edate1 ] },
        curmax   => \$s,
    });
    if (@config) {
        error($c,
            'That space is not entirely free.',
            'gen_error.tt2',    
        );
        return;
    }
    
    model($c, 'Block')->create({
        %P,
        _get_now($c),
    });

    my $t = "cur + $P{nbeds}";
    model($c, 'Config')->search({
        house_id => $P{house_id},
        the_date => { -between => [ $P{sdate}, $edate1 ] },
    })->update({
        cur => \$t,
        sex => 'B', #???
    });
    # sex attr???  B or leave as is?
    #
    $c->response->redirect($c->uri_for("/block/list/"));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

sub search : Local {
    my ($self, $c) = @_;
    
    my @cond = (); 
    my $start = $c->request->param('start');
    $start = date($start);
    if ($start) {
        push @cond, pickup_date => { '>=' => $start->as_d8() };
    }
    my $end = $c->request->param('end');
    $end = date($end);
    if ($end) {
        push @cond, pickup_date => { '<=' => $end->as_d8() };
    }
    my $name = $c->request->param('name');
    if (! @cond) {
        # same as list
        #
        push @cond, -or => [
                        pickup_date => { '>=' => today()->as_d8() },
                        paid_date   => '',
                    ];
    }
    stash($c,
        pg_title => "Block",
        blocks    => [ model($c, 'Block')->search(
            {
                @cond,
            },
            {
                order_by => 'pickup_date, airport, flight_time',
                join     => [qw/ blockr /],
                prefetch => [qw/ blockr /],   
            }
        ) ],
        template => "block/list.tt2",
    );
}

1;
