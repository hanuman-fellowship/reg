use strict;
use warnings;
package RetreatCenter::Controller::House;
use base 'Catalyst::Controller';

use lib '../..';
use Util qw/
    empty
    model
    trim
    stash
/;
use Date::Simple qw/
    today
/;
use Global qw/%string/;

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c, $resident) = @_;

    $resident = $resident? 'yes'
                :          q{};
    my ($tcb) = model($c, 'House')->search({ name => 'TCB 10' });
    stash($c,
        resident => $resident,
        rooms => [ model($c, 'House')->search(
            {
                tent     => '',
                resident => $resident,
            },
            { order_by => 'name' }
        ) ],
        tents => [ model($c, 'House')->search(
            {
                tent     => 'yes',
                resident => $resident,
            },
            { order_by => 'name' }
        ) ],
        hdr          => $resident? 'Resident': 'By Name',
        tcb_activate => ($tcb->inactive())? "Activate": "Inactivate",
        other_sort   => "<a href=/house/by_type_priority>By Type/Priority</a>",
        template     => "house/list.tt2",
    );
}

sub by_type_priority : Local {
    my ($self, $c) = @_;
    
    my ($tcb1) = model($c, 'House')->search({ name => 'TCB 1' });
    stash($c,
        rooms => [ model($c, 'House')->search(
            {
                tent     => '',
                resident => '',
            },
            { order_by => 'inactive, max, bath desc, cabin desc, priority' }
        ) ],
        tents => [ model($c, 'House')->search(
            {
                tent     => 'yes',
                resident => '',
            },
            { order_by => 'inactive, center desc, priority' }
        ) ],
        hdr          => "By Type/Priority",
        other_sort   => "<a href=/house/list>By Name</a>",
        tcb_activate => ($tcb1->inactive())? "Activate": "Inactivate",
        template     => "house/list.tt2",
    );
}

my %hash;
my @mess;
sub _get_data {
    my ($c) = @_;

    %hash = %{ $c->request->params() };
    # since unchecked checkboxes are not sent...
    for my $f (qw/
        bath
        tent
        center
        cabin
        resident
        cat_abode
        inactive
        key_card
    /) {
        $hash{$f} = "" unless exists $hash{$f};
    }
    if ($hash{center}) {
        # center implies tent
        $hash{tent} = "yes";
    }
    if ($hash{tent}) {
        # if tent can't be a cabin
        $hash{cabin} = "";
    }
    @mess = ();
    if (empty($hash{name})) {
        push @mess, "Name cannot be blank.";
    }
    for my $f (qw/
        max
        x
        y
        priority
        cluster_order
    /) {
        $hash{$f} = trim($hash{$f}) || '';
        if ($hash{$f} !~ m{^\d+$}) {
            push @mess, "Illegal \u$f: $hash{$f}";
        }
    }
    my ($mp) = model($c, 'MeetingPlace')->search({
                   abbr => $hash{name},
               });
    if ($mp && ! $mp->sleep_too()) {
        push @mess, "The Meeting Place whose abbreviation is '$hash{name}' must have 'For Sleeping'.";
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "house/error.tt2";
    }
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $h = model($c, 'House')->find($id);
    stash($c,
        house     => $h,
        bath      => $h->bath()     ? "checked": "",
        tent      => $h->tent()     ? "checked": "",
        center    => $h->center()   ? "checked": "",
        cabin     => $h->cabin()    ? "checked": "",
        resident  => $h->resident() ? "checked": "",
        cat_abode => $h->cat_abode()? "checked": "",
        inactive  => $h->inactive() ? "checked": "",
        key_card  => $h->key_card() ? "checked": "",
        cluster_opts => [ model($c, 'Cluster')->search(
                              undef,
                              { order_by => 'name' },
                          )
                        ],
        form_action => "update_do/$id",
        template    => "house/create_edit.tt2",
    );
}

#
# currently there's no way to know which fields changed
# so assume they all did.
#
# ??? What if they change the max value of a house?
# we do not update the Config records!
#
# check for dups???
#
sub update_do : Local {
    my ($self, $c, $id) = @_;

    _get_data($c);
    return if @mess;
    my ($h) = model($c, 'House')->find($id);
    my $old_name = $h->name();
    my ($mp) = model($c, 'MeetingPlace')->search({
                   abbr => $old_name,
               });
    if ($mp && $old_name ne $hash{name}) {
        $c->stash->{mess} = "Cannot change the name '$old_name' because there is a Meeting Place with that name!";
        $c->stash->{template} = "house/error.tt2";
        return;
    }
    my $old_max = $h->max();
    $h->update(\%hash);
    if ($old_max != $hash{max}) {
        # need to change the future config records
        # to reflect the new max.
        # what about those records which have a non-zero 'cur'?
        # I'd say just leave them alone ... yes.
        system('add_config ' . $h->id() . ' ' . $h->max());
    }
    Global->init($c, 1);
    $c->response->redirect($c->uri_for('/house/list'));
}

sub create : Local {
    my ($self, $c) = @_;

    $c->stash->{cluster_opts} =
        [ model($c, 'Cluster')->search(
            undef,
            { order_by => 'name' },
        ) ];
    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "house/create_edit.tt2";
}

#
# check for dups???
#
sub create_do : Local {
    my ($self, $c) = @_;

    _get_data($c);
    return if @mess;
    my $house = model($c, 'House')->create({
        %hash,
        inactive => 'yes',
    });
    #
    # we need to add config records for this house
    # all the way into the future.  this will take a while.
    # we'll do it in the background and when it is complete
    # we will set the house to be not 'inactive'.
    #
    system('add_config ' . $house->id);
    $c->response->redirect($c->uri_for('/house/list'));
}

sub view : Local {
    my ($self, $c, $id) = @_;

    my ($makeup) = model($c, 'MakeUp')->search({
                         house_id => $id,
                   });
    stash($c,
        on_makeup => $makeup,
        house     => model($c, 'House')->find($id),
        template  => "house/view.tt2",
    );
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

sub toggleTCB : Local {
    my ($self, $c) = @_; 
    
    my ($tcb1) = model($c, 'House')->search({ name => "TCB 1" });
    my $new_val = ($tcb1->inactive())? "": "yes";
    model($c, 'House')->search({ name => { 'like', "TCB %" }})
        ->update({ inactive => $new_val });
    model($c, 'Annotation')->search({ label => { 'like', "%Terrace%" }})
        ->update({ inactive => $new_val });
    $c->response->redirect($c->uri_for('/house/list'));
    Global->init($c, 1);    # force a reload
}

sub makeup : Local {
    my ($self, $c, $id) = @_;

    my $today = today()->as_d8(),

    # the tricky part is knowing when the house
    # is next needed - by a registrant, rental or block
    #
    my $needed = '29991231';        # way out there
    my @items = ();
    my ($reg) = model($c, 'Registration')->search(
                {
                    house_id => $id,
                    date_end => { '>' => $today },
                },
                {
                    order_by => 'date_start',
                    rows     => 1,
                });
    if ($reg) {
        $needed = $reg->date_start();
    }
    my ($rental) = model($c, 'RentalBooking')->search(
                   {
                      house_id => $id,
                      date_end => { '>' => $today },
                   },
                   {
                       order_by => 'date_start',
                       rows     => 1,
                   });
    if ($rental && $rental->date_end() < $needed) {
        $needed = $rental->date_start();
    }
    my ($block) = model($c, 'Block')->search(
                  {
                      house_id => $id,
                      edate    => { '>' => $today },
                  },
                  {
                      order_by => 'sdate',
                      rows     => 1,
                  });
    if ($block && $block->sdate() < $needed) {
        $needed = $block->sdate();
    }
    $needed = '' if $needed == '29991231';
    model($c, 'MakeUp')->create({
        house_id     => $id,
        date_vacated => $today,
        date_needed  => $needed,
        refresh      => '',
    });
    stash($c,
        on_makeup => 1,
        house     => model($c, 'House')->find($id),
        template  => "house/view.tt2",
    );
}

1;
