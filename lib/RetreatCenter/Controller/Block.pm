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
                edate => { '>=' => today()->as_d8() },
            },
            {
                order_by => 'sdate',
                join     => [qw/ house /],
                prefetch => [qw/ house /],   
            }
        ) ],
        template => "block/list.tt2",
    );
}

sub view : Local {
    my ($self, $c, $block_id) = @_;

    my $block = model($c, 'Block')->find($block_id);
    stash($c,
        pg_title => 'Block',
        block    => $block,
        template => "block/view.tt2",
        daily_pic_date => $block->sdate,
    );
}

sub delete : Local {
    my ($self, $c, $block_id) = @_;

    my $block = model($c, 'Block')->find($block_id);
    _vacate($c, $block);
    $block->delete();
    $c->response->redirect($c->uri_for('/block/list'));
}

sub _vacate {
    my ($c, $block) = @_;

    my $hmax = $block->house->max();
    my $edate1 = ($block->edate_obj() -1)->as_d8();
    for my $cf (model($c, 'Config')->search({
                    house_id => $block->house_id(),
                    the_date => { -between => [ $block->sdate(), $edate1 ] },
                })
    ) {
        my $nleft = $cf->cur() - $block->nbeds();
        my @opts = ();
        if ($nleft == 0) {
            @opts = (
                curmax     => $hmax,
                sex        => 'U',
                program_id => 0,
            );

        }
        $cf->update({
            cur => $nleft,
            @opts,
        });
    }
}

my %P;
my @mess;
my $edate1;
sub _get_data {
    my ($c) = @_;

    %P = %{ $c->request->params() };
    for my $k (keys %P) {
        $P{$k} = trim($P{$k});
    }
    @mess = ();
    my $house;
    if (empty($P{h_name})) {
        push @mess, "Missing House Name";
    }
    else {
        ($house) = model($c, 'House')->search({
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
    my $hmax = $house->max();
    if (empty($P{nbeds})) {
        $P{nbeds} = $hmax;
    }
    elsif (! ($P{nbeds} =~ m{^\d+$} && $P{nbeds} > 0)) {
        push @mess, "Invalid # of Beds: $P{nbeds}";
    }
    elsif ($P{nbeds} > $hmax) {
        push @mess, "There are not $P{nbeds} beds in " . $house->name();
    }
    if (empty($P{npeople})) {
        $P{npeople} = 0;
    }
    elsif (! ($P{npeople} =~ m{^\d$} && $P{npeople} <= $P{nbeds})) {
        push @mess, "Invalid # of People: $P{npeople}";
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

    # we first vacate the old house - assuming it is allocated.
    # If we don't vacate first it is too tricky to
    # move a block of 4 days up by one day, yes?
    # because there would be an overlap with itself.
    #
    _vacate($c, $block) if $block->allocated();

    if (_available($c)) {
        $block->update({
            %P,
            allocated => 'yes',
            _get_now($c),
        });
        $c->response->redirect($c->uri_for("/block/list"));
    }
    else {
        # some error occurred.  space not available.
        # an error will be reported when this subroutine returns.
        # restore the block as it was before we vacated it
        # just in case the person abandons the edit.
        #
        $P{house_id} = $block->house_id();
        $P{sdate}    = $block->sdate();
        $edate1      = ($block->edate_obj() - 1)->as_d8();
        $P{nbeds}    = $block->nbeds();

        if (_available($c)) {
            # housing restored
        }
        else {
            # something happened in the split second
            # between vacating and re-occupying
            # very rare - but COULD happen, I guess.
            #
            $block->update({
                allocated => '',
            });
        }
    }
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
    if (_available($c)) {
        model($c, 'Block')->create({
            %P,
            allocated => 'yes',
            _get_now($c),
        });
        $c->response->redirect($c->uri_for("/block/list/"));
    }
}

#
# is the space actually available?
# consult %P and $edate1 for the specifics
#
# search for exceptions
#
# if it is available actually reserve it by modifying
# the config records.
#
sub _available {
    my ($c) = @_;

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
        return 0;
    }
    for my $cf (model($c, 'Config')->search({
                    house_id => $P{house_id},
                    the_date => { -between => [ $P{sdate}, $edate1 ] },
                })
    ) {
        my @opt = ();
        if ($cf->cur() == 0) {
            @opt = (sex => 'B');
        }
        else {
            # leave sex at M or F or X.
        }
        $cf->update({
            cur => $cf->cur() + $P{nbeds},
            @opt,
        });
    }
    return 1;
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
        push @cond, sdate => { '>=' => $start->as_d8() };
    }
    if (! @cond) {
        # same as list
        #
        $c->response->redirect($c->uri_for('/block/list'));
        return;
    }
    stash($c,
        pg_title => "Blocks",
        blocks    => [ model($c, 'Block')->search(
            {
                @cond,
            },
            {
                order_by => 'sdate',
                join     => [qw/ house /],
                prefetch => [qw/ house /],   
                rows     => 10,
            }
        ) ],
        template => "block/list.tt2",
    );
}

1;
