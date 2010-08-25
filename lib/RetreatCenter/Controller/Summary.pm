use strict;
use warnings;
package RetreatCenter::Controller::Summary;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.
use Date::Simple qw/
    date
/;
use Time::Simple qw/
    get_time
/;
use Util qw/
    model
    lines
    etrim
    tt_today
    highlight
    stash
    avail_pic_num
    resize
    error
/;
use Global qw/
    %string
/;

sub view : Local {
    my ($self, $c, $type, $id) = @_;

    my $summary = model($c, 'Summary')->find($id);
    for my $f (qw/
        gate_code
        alongside
        registration_location
        orientation
        wind_up
        alongside
        back_to_back
        leader_name
        leader_housing
        staff_arrival
        staff_departure
        converted_spaces
    /) {
        $c->stash->{$f} = highlight($summary->$f());
    }
    if ($string{sum_copy_id}) {
        my ($timestamp, $paste_id, $paste_name)
            = $string{sum_copy_id} =~ m{^(\d+)\s+(\d+)\s+(.*)};
        if ($timestamp < time() - 5*60) {
            #
            # more than 5 minutes have passed since the copy
            # so expire the copy id.
            #
            model($c, 'String')->find('sum_copy_id')->update({
                value => '',
            });
            $string{sum_copy_id} = '';      # update Global %string as well
        }
        else {
            stash($c,
                paste_id   => $paste_id,
                paste_name => $paste_name,
            );
        }
    }

    my $happening = $summary->$type();
    my $sdate = $happening->sdate();
    my $nmonths = date($happening->edate())->month()
                - date($sdate)->month()
                + 1;
    my @opt = ();
    if ($type eq 'program') {
        my $extra = $happening->extradays();
        if ($extra) {
            my $edate2 = $happening->edate_obj() + $extra;
            stash($c,
                plus => "<b>Plus</b> $extra day"
                      . ($extra > 1? "s": "")
                      . " <b>To</b> " . $edate2
                      . " <span class=dow>"
                      . $edate2->format("%a")
                      . "</span>"
            );
        }
    }

    stash($c,
        type      => $type,
        Type      => ucfirst $type,
        happening => $happening,
        @opt,
        sum       => $summary,
        cal_param => "$sdate/$nmonths",
        template  => "summary/view.tt2",
    );
}

sub copy : Local {
    my ($self, $c, $type, $id) = @_;

    my $hap = model($c, $type)->find($id);
    my $name = $hap->name();
    my $s = time() . " " . $hap->summary_id() . " $name";
    model($c, 'String')->find('sum_copy_id')->update({
        value => $s,
    });
    $string{sum_copy_id} = $s;      # update Global %string as well
    stash($c,
        name     => $name,
        template => "summary/copied.tt2",
    );
}

sub update : Local {
    my ($self, $c, $type, $sum_id) = @_;
 
    my $sum = model($c, 'Summary')->find($sum_id);
    my $happening = $sum->$type();
    for my $f (qw/
        leader_housing
        signage
        miscellaneous
        feedback
        food_service
        flowers
        field_staff_setup
        workshop_schedule
        sound_setup
        check_list
        converted_spaces
    /) {
        $c->stash->{"$f\_rows"} = lines($sum->$f()) + 5;    # 5 in strings?
    }
    stash($c,
        Type      => ucfirst $type,
        type      => lc $type,
        happening => $happening,
        sum       => $sum,
        template  => "summary/edit.tt2",
    );
}

sub update_do : Local {
    my ($self, $c, $type, $sum_id) = @_;
    my $sum = model($c, 'Summary')->find($sum_id);
    my %hash = %{ $c->request->params() };

    if (my $upload = $c->request->upload('newpic')) {
        my $n = avail_pic_num('s', $sum_id);
        $upload->copy_to("root/static/images/so-$sum_id-$n.jpg");
        Global->init($c);
        resize('s', "$sum_id-$n");
    }
    if (exists $hash{newpic}) {
        delete($hash{newpic});
    }

    for my $f (keys %hash) {
        $hash{$f} = etrim($hash{$f});
    }
    if ($hash{gate_code} && $hash{gate_code} !~ m{^\d\d\d\d$}) {
        error($c,
            'Gate Code must be 4 digits.',
            'gen_error.tt2',
        );
        return;
    }

    if (! exists $hash{needs_verification}) {
        $hash{needs_verification} = '';
    }
    # delete ones that have not changed???
    # warn about ones that are different? we don't know what it was before
    # do we?  nope.
    $sum->update({
        %hash,
        date_updated => tt_today($c)->as_d8(),
        who_updated  => $c->user->obj->id,
        time_updated => sprintf "%02d:%02d", (localtime())[2, 1],
    });
    $c->response->redirect($c->uri_for("/summary/view/$type/$sum_id"));
}

sub update_sect : Local {
    my ($self, $c, $section, $type, $sum_id) = @_;
 
    my $sum = model($c, 'Summary')->find($sum_id);
    my $happening = $sum->$type();
    stash($c,
        Type      => ucfirst $type,
        type      => $type,
        happening => $happening,
        sum       => $sum,
        section   => $section,
        section_disp   => _trans($section),
        section_data => $sum->$section(),
        rows      => lines($sum->$section()) + 5, 
        template  => "summary/edit_section.tt2",
    );
}

sub _trans {
    my ($s) = @_;
    $s =~ s{_}{ };
    $s =~ s{\b(\w)}{\u$1}g;
    if ($s =~ m{^Food}) {   # special case
        $s = "CB $s";
    }
    $s;
}

sub update_section_do : Local {
    my ($self, $c, $section, $type, $sum_id) = @_;

    my $sum = model($c, 'Summary')->find($sum_id);
    my $section_data = etrim($c->request->params->{section});
    $sum->update({
        $section     => $section_data,
        date_updated => tt_today($c)->as_d8(),
        who_updated  => $c->user->obj->id,
        time_updated => sprintf "%02d:%02d", (localtime())[2, 1],
    });
    $c->response->redirect($c->uri_for("/summary/view/$type/$sum_id"));
}

sub update_top : Local {
    my ($self, $c, $type, $sum_id) = @_;
 
    my $sum = model($c, 'Summary')->find($sum_id);
    my $happening = $sum->$type();
    stash($c,
        Type      => ucfirst $type,
        type      => lc $type,
        happening => $happening,
        sum       => $sum,
        template  => "summary/edit_top.tt2",
    );
}

sub update_top_do : Local {
    my ($self, $c, $type, $sum_id) = @_;
    my $sum = model($c, 'Summary')->find($sum_id);
    my %hash = %{ $c->request->params() };

    for my $f (keys %hash) {
        $hash{$f} = etrim($hash{$f});
    }
    if ($hash{gate_code} && $hash{gate_code} !~ m{^\d\d\d\d$}) {
        error($c,
            'Gate Code must be 4 digits.',
            'gen_error.tt2',
        );
        return;
    }

    # delete ones that have not changed???
    # warn about ones that are different? we don't know what it was before
    # do we?  nope.
    $sum->update({
        %hash,
        date_updated => tt_today($c)->as_d8(),
        who_updated  => $c->user->obj->id,
        time_updated => sprintf "%02d:%02d", (localtime())[2, 1],
    });
    $c->response->redirect($c->uri_for("/summary/view/$type/$sum_id"));
}

sub use_template : Local {
    my ($self, $c, $type, $happening_id, $sum_id) = @_;

    # $type is Program or Rental
    # $happening_id is the id of the Program or Rental

    # use the summary from the right template
    #
    my $prefix = "MMC";
    if ($type eq 'Program') {
        my $prog = model($c, $type)->find($happening_id);
        if ($prog->school() != 0) {
            $prefix = "MMI";
        }
    }
    my @prog = model($c, 'Program')->search({
        name => "$prefix Template",
    });
    if (! @prog) {
        $c->stash->{mess} = "Could not find '$prefix Template' program";
        $c->stash->{template} = "gen_error.tt2";
        return;
    }
    my $template_sum = model($c, 'Summary')->find($prog[0]->summary_id());
    model($c, 'Summary')->find($sum_id)->update({
        $template_sum->get_columns(),

        # and then override the following:
        id           => $sum_id,
        date_updated => tt_today($c)->as_d8(),
        who_updated  => $c->user->obj->id,
        time_updated => get_time()->t24(),
        gate_code => '',
        needs_verification => "yes",
    });
    $type = lc $type;       # Program to program
    $c->response->redirect($c->uri_for("/summary/view/$type/$sum_id"));
}

sub paste : Local {
    my ($self, $c, $type, $id, $sum_copy_id) = @_;

    my $hap = model($c, $type)->find($id);
    my $hap_sum = $hap->summary();
    my $sum_id = $hap_sum->id();
    my $sum_to_copy = model($c, 'Summary')->find($sum_copy_id);
    $hap_sum->update({
        $sum_to_copy->get_columns(),             # copy all fields
        id           => $sum_id,                 # except id
        date_updated => tt_today($c)->as_d8(),   # and override
        who_updated  => $c->user->obj->id,       # update status info
        time_updated => get_time()->t24(),
        gate_code => '',
        needs_verification => "yes",
    });
    # now overwrite the Checklist with the one from the MMC Template
    #
    my @prog = model($c, 'Program')->search({
        name => "MMC Template",
    });
    if (@prog) {
        my $template_sum = model($c, 'Summary')->find($prog[0]->summary_id());
        $hap_sum->update({
            check_list => $template_sum->check_list(),
        });
    }

    # clear the string sum_copy_id
    #
    model($c, 'String')->find('sum_copy_id')->update({
        value => '',
    });
    $string{sum_copy_id} = '';      # update Global %string as well

    $type = lc $type;       # Program to program
    $c->response->redirect($c->uri_for("/summary/view/$type/$sum_id"));
}

sub del_pic : Local {
    my ($self, $c, $id, $n) = @_;
    my $sum = model($c, 'Summary')->find($id);
    unlink <root/static/images/s*-$id-$n*>;
    my $type = $sum->program()? "program"
               :                "rental"
               ;
    $c->response->redirect($c->uri_for("/summary/view/$type/$id"));
}

sub view_pic : Local {
    my ($self, $c, $id, $n, $which) = @_;
    my $sum = model($c, 'Summary')->find($id);
    my ($hap, $hap_type);
    if ($hap = $sum->program()) {
        $hap_type = 'program';
    }
    else {
        $hap = $sum->rental();
        $hap_type = 'rental';
    }
    my $type = $which? 'o': 'b';
    stash($c,
          template => 'summary/view_pic.tt2',
          id       => $id,
          n        => $n,
          which    => !$which,
          pic      => "/static/images/s$type-$id-$n.jpg",
          hap_type => $hap_type,
          Hap_type => ucfirst $hap_type,
          hap_id   => $hap->id(),
          hap_name => $hap->name(),
    );
}

1;
