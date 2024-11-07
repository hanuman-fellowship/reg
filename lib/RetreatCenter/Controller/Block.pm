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
    stash
    check_makeup_new
    check_makeup_vacate
    get_now
    too_far
    other_reserved_cids
    read_only
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
    %house_name_of
/;
use HLog;

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('list');
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
    my $ev = 0;
    my $type = "indoors";
    if ($block->rental_id()) {
        $ev = $block->rental();
    }
    elsif ($block->program_id()) {
        $ev = $block->program();
        if ($ev->category->name() ne 'Normal') {
            $type = "resident";
        }
    }
    elsif ($block->event_id()) {
        $ev = $block->event();
    }
    my $ev_type = $ev? ucfirst $ev->event_type(): "";
    my $ev_link = $ev?         $ev->link()      : "";
    my $ev_name = $ev?         $ev->name()      : "";
    stash($c,
        pg_title => 'Block',
        block    => $block,
        ev_type  => $ev_type,
        ev_link  => $ev_link,
        ev_name  => $ev_name,
        template => "block/view.tt2",
        daily_pic_date => "$type/" . $block->sdate(),
        cluster_date   => $block->sdate(),
    );
}

sub delete : Local {
    my ($self, $c, $block_id) = @_;

    if (read_only($c) == 1) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
    my $block = model($c, 'Block')->find($block_id);

    my $redirect = "/block/list";
    TYPE:
    for my $t (qw/
        event
        program
        rental
    /) {
        my $method = "$t\_id";
        if ($block->$method()) {
            $redirect = "/$t/view/" . $block->$method();
            last TYPE;
        }
    }

    _vacate($c, $block);
    $block->delete();
    $c->response->redirect($c->uri_for($redirect));
}

sub _vacate {
    my ($c, $block) = @_;

    my $h_id   = $block->house_id();
    my $hname  = $house_name_of{$h_id};
    my $reason = $block->reason();

    my $hmax = $block->house->max();
    my $sdate = $block->sdate();
    my $edate1 = ($block->edate_obj() -1)->as_d8();

    for my $cf (model($c, 'Config')->search({
                    house_id => $h_id,
                    the_date => { -between => [ $sdate, $edate1 ] },
                })
    ) {
        my $nleft = $cf->cur() - $block->nbeds();
        my @opts = ();
        if ($nleft == 0) {
            @opts = (
                curmax     => $hmax,
                sex        => 'U',
                program_id => 0,
                rental_id  => 0,
            );

        }
        $cf->update({
            cur => $nleft,
            program_id => 0,
            rental_id  => 0,
            @opts,
        });
        if ($string{housing_log}) {
            hlog($c,
                 $hname, $cf->the_date(),
                 "block_del",
                 $h_id, $cf->curmax(), $nleft, $cf->sex(),
                 0, 0,
                 $reason,
            );
        }
    }
    check_makeup_vacate($c, $h_id, $sdate);
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
    if (! @mess && (my $mess = too_far($c, $P{edate}))) {
        push @mess, $mess;
    }
    if ($house) {
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
    }
    # npeople is only used in the meal count
    if (empty($P{npeople})) {
        $P{npeople} = 0;
    }
    elsif (! ($P{npeople} =~ m{^\d+$} && $P{npeople} <= $P{nbeds})) {
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

sub create : Local {
    my ($self, $c) = @_;

    if (read_only($c) == 1) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "block/create_edit.tt2";
}

sub bound_create : Local {
    my ($self, $c, $hap_type, $hap_id) = @_;

    if (read_only($c) == 1) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
    my $hap = model($c, ucfirst $hap_type)->find($hap_id);
    stash($c,
        hap         => $hap,
        block       => {
            sdate_obj => date($hap->sdate()),
            edate_obj => date($hap->edate()),
        },
        form_action => "create_do",
        template    => "block/create_edit.tt2",
    );
}

#
# offer to create multiple blocks at once.
# just for the date range of the event (program or rental)
# nbeds all in house, npeople 0
# exclude RAM houses
#
sub create_many : Local {
    my ($self, $c, $type, $id) = @_;

    if (read_only($c) == 1) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
    my $event = model($c, ucfirst $type)->find($id);
    my $sdate = $event->sdate();
    my $edate1 = ($event->edate_obj() - 1)->as_d8();
    my %or_cids = other_reserved_cids($c, $event);
    my @or_cids = keys %or_cids;
    my @opt = ();
    if (@or_cids) {
        push @opt, cluster_id => { -not_in => \@or_cids };
    }
    my ($center_tent, $own_tent, $single, $single_bath,
        $double, $double_bath, $triple, $dorm, $economy) = ('' x 8);
    my $checks = '';
    HOUSE:
    for my $h (model($c, 'House')->search({
                   inactive => '',
                   resident => '',
                   @opt,
               },
               { order_by => 'name' }
              ) 
    ) {
        my $h_id = $h->id;
        #
        # is this house _completely_ available from sdate to edate1?
        # needs a thorough testing!
        #
        my @cf = model($c, 'Config')->search({
            house_id => $h_id,
            the_date => { between => [ $sdate, $edate1 ] },
            cur      => { '>', 0 },
        });
        next HOUSE if @cf;        # nope
        my $check .= "<label><input type=checkbox name=h$h_id value=$h_id> "
              . $h->name()
              . "</label><br>\n"
              ;
        if ($h->tent()) {
            if ($h->center()) {
                $center_tent .= $check;
            }
            else {
                $own_tent .= $check;
            }
        }
        elsif ($h->max() == 1) {
            if ($h->bath()) {
                $single_bath .= $check;
            }
            else {
                $single .= $check;
            }
        }
        elsif ($h->max() == 2) {
            if ($h->bath()) {
                $double_bath .= $check;
            }
            else {
                $double .= $check;
            }
        }
        elsif ($h->max() == 3) {
            $triple .= $check;
        }
        elsif ($h->max() <= 7) {
            $dorm .= $check;
        }
        else {
            $economy .= $check;
        }
    }
    stash($c,
        type        => $type,
        event       => $event,
        id          => $id,
        center_tent => $center_tent,
        own_tent    => $own_tent,
        single      => $single,
        single_bath => $single_bath,
        double      => $double,
        double_bath => $double_bath,
        triple      => $triple,
        dorm        => $dorm,
        economy     => $economy,
        daily_pic_date => "indoors/$sdate",
        cluster_date   => $sdate,
        pg_title    => "Blocks for " . $event->name(),
        template    => 'block/many_block.tt2',
    );
}

sub create_many_do : Local {
    my ($self, $c, $type, $id) = @_;
    my $event = model($c, ucfirst $type)->find($id);
    my $sdate = $event->sdate();
    my $edate = $event->edate();
    my $edate1 = ($event->edate_obj() - 1)->as_d8();
    my @chosen_house_ids = values %{$c->request->params()};
    if (! @chosen_house_ids) {
        $c->response->redirect($c->uri_for("/type/view/$id/1"));
        return;
    }
    my @opt = (
        program_id => $type eq 'program'? $id: 0,
        rental_id  => $type eq 'rental' ? $id: 0,
    );
    for my $h_id (@chosen_house_ids) {
        my $h = model($c, 'House')->find($h_id);
        my $hname = $h->name();
        model($c, 'Block')->create({
            house_id   => $h_id,
            sdate      => $sdate,
            edate      => $edate,
            nbeds      => $h->max(),
            npeople    => 0,
            reason     => $event->name(),
            comment    => 'added by Many Blocks',
            event_id   => 0,
            @opt,
            allocated => 'yes',
            get_now($c),
        });
        # and update the config records
        for my $cf (model($c, 'Config')->search({
                        house_id => $h_id,
                        the_date => { -between => [ $sdate, $edate1 ] },
                    })
        ) {
            $cf->update({
                cur => $h->max(),
                @opt,
                sex => 'B',
            });
            # housing log
            if ($string{housing_log}) {
                hlog($c,
                     $hname, $cf->the_date(),
                     "many_block_create",
                     $h_id, $cf->curmax(), $cf->cur(), $cf->sex(),
                     0, 0,
                     'Many Block',
                );
            }
        }
    }
    $c->response->redirect($c->uri_for("/$type/view/$id/1"));
}

sub delete_many : Local {
    my ($self, $c, $type, $id) = @_;

    if (read_only($c) == 1) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
    my $event = model($c, ucfirst $type)->find($id);
    stash($c,
        type     => $type,
        Type     => ucfirst $type,
        event    => $event,
        blocks   => [ $event->blocks() ],
        template => 'block/delete_many.tt2',
    );
}

sub delete_many_do : Local {
    my ($self, $c, $type, $id) = @_;

    %P = %{ $c->request->params() };
    for my $block_id (keys %P) {
        my $block = model($c, 'Block')->find($block_id);
        _vacate($c, $block);    # deal with the config table
        $block->delete();
    }
    $c->response->redirect($c->uri_for("/$type/view/$id/1"));
}

sub create_do : Local {
    my ($self, $c) = @_;

    _get_data($c);
    return if @mess;
    my @opt = ();
    if ($P{hap_type}) {
        @opt = ("$P{hap_type}_id" => $P{hap_id});
        delete $P{hap_type};
        delete $P{hap_id};
    }
    if (_available($c, @opt)) {
        model($c, 'Block')->create({
            %P,

            event_id   => 0,
            program_id => 0,
            rental_id  => 0,
            @opt,           # overrides above 3

            allocated => 'yes',
            get_now($c),
        });
        if (@opt) {
            $opt[0] =~ s{_id}{};
            $c->response->redirect($c->uri_for("/$opt[0]/view/$opt[1]"));
        }
        else {
            $c->response->redirect($c->uri_for("/block/list/"));
        }
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
    my ($c, $type, $id) = @_;

    my @type_opt = ();
    if ($type && $type ne "event_id") {
        @type_opt = ($type => $id);
    }
    my $s = "< cur + $P{nbeds}";
    my $h_id = $P{house_id};
    my $hname = $house_name_of{$h_id};
    my @config = model($c, 'Config')->search({
        house_id => $h_id,
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
                    house_id => $h_id,
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
            program_id => 0,
            rental_id  => 0,
            @type_opt,
            @opt,
        });
        if ($string{housing_log}) {
            hlog($c,
                 $hname, $cf->the_date(),
                 "block_create",
                 $h_id, $cf->curmax(), $cf->cur(), $cf->sex(),
                 0, 0,
                 $P{reason},
            );
        }
    }
    check_makeup_new($c, $h_id, $P{sdate});
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
                rows     => 10,     # limit it on purpose
                                    # otherwise too many ...
            }
        ) ],
        template => "block/list.tt2",
    );
}

1;
