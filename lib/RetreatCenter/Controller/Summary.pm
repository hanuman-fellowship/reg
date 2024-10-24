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
    error
    email_letter
    put_string
    get_string
    read_only
/;
use Global qw/
    %string
/;
use Template;

my @sections;

sub calc_sections {
    my ($summary) = @_;
    @sections = map {
        my ($name, $title) = split /[|]/;
        $title =~ s{_}{ }xmsg;
        my $text = $summary->$name();
        {
            name  => $name,
            title => $title,
            text  => highlight($text),
            rows  => lines($text) + 5,
        }
    }
    qw!
    internal_comm|Internal_Communications
    leader_housing|Leader_Housing
    signage|Signage
    flowers|Registration_Info
    field_staff_std_setup|Tea_Bar
    field_staff_setup|Meeting_Space_Setup
    sound_setup|A/V_Setup
    snack|Snack
    food_service|Food_Service
    workshop_schedule|Workshop_Schedule
    workshop_description|Workshop_Description
    check_list|Check_List
    miscellaneous|Miscellaneous
    breakdown|Breakdown
    feedback|Feedback
    !;
}

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
        staff_arrival
        staff_departure
        converted_spaces
    /) {
        $c->stash->{$f} = highlight($summary->$f());
    }
    if (my $s = get_string($c, 'sum_copy_id')) {
        my ($timestamp, $paste_id, $paste_name)
            = $s =~ m{^ (\d+) \s+ (\d+) \s+ (.*) \z}xms;
        if ($timestamp < time() - 5*60) {
            #
            # more than 5 minutes have passed since the copy
            # so expire the copy id.
            #
            put_string($c, 'sum_copy_id', '');
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
    calc_sections($summary);
    stash($c,
        sections  => \@sections,
        type      => $type,
        Type      => ucfirst $type,
        happening => $happening,
        @opt,
        sum       => $summary,
        email_class => $summary->needs_emailing? 'bold_red': 'normal',
        cal_param => "$sdate/$nmonths",
        template  => "summary/view.tt2",
    );
}

sub copy : Local {
    my ($self, $c, $type, $id) = @_;

    my $hap = model($c, $type)->find($id);
    my $name = $hap->name();
    my $s = time() . " " . $hap->summary_id() . " $name";
    put_string($c, 'sum_copy_id', $s);
    stash($c,
        name     => $name,
        template => "summary/copied.tt2",
    );
}

sub update : Local {
    my ($self, $c, $type, $sum_id) = @_;
 
    if (read_only()) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
    my $sum = model($c, 'Summary')->find($sum_id);
    my $happening = $sum->$type();
    calc_sections($sum);
    stash($c,
        sections  => \@sections,
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
        time_updated => get_time()->t24(),
    });
    $c->response->redirect($c->uri_for("/summary/view/$type/$sum_id"));
}

sub update_sect : Local {
    my ($self, $c, $section, $type, $sum_id) = @_;
 
    if (read_only()) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
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
    $s =~ s{_}{ }g;
    $s =~ s{std}{standard};
    $s =~ s{comm}{communication};
    $s =~ s{breakdown}{breakdown notes};
    $s =~ s{sound}{A/V};
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
        time_updated => get_time()->t24(),
    });
    $c->response->redirect($c->uri_for("/summary/view/$type/$sum_id#$section"));
}

sub update_top : Local {
    my ($self, $c, $type, $sum_id) = @_;
 
    if (read_only()) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
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
        time_updated => get_time()->t24(),
    });
    $c->response->redirect($c->uri_for("/summary/view/$type/$sum_id"));
}

sub use_template : Local {
    my ($self, $c, $type, $happening_id, $sum_id) = @_;

    if (read_only()) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
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
            check_list            => $template_sum->check_list(),
            field_staff_std_setup => $template_sum->field_staff_std_setup(),
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

sub email : Local {
    my ($self, $c, $sum_id) = @_;

    my $summary = model($c, 'Summary')->find($sum_id);
    my $type = $summary->program()? 'program': 'rental';
    my $happening = $summary->$type();
    my %people;
    if ($type eq 'rental') {
        my $i = 1;
        for my $n (qw/ coordinator contract_signer /) {
            my $p = $happening->$n;
            if ($p) {
                $people{"person$i"} = $p;
                ++$i;
            }
        }
    }
    else {
        my @leaders = $happening->leaders();
        $people{person1} = $leaders[0]->person() if @leaders >= 1;
        $people{person2} = $leaders[1]->person() if @leaders >= 2;
    }
    my $to = join ' and ', map { $people{$_}->first } sort keys %people;
    $to =~ s{(\w+)\s+and\s+\1}{$1}xms;  # if coordinator = contract signer
    my $user_first = $c->user->obj->first;
    stash($c,
        happening => $happening,
        subject   => "$string{sum_email_subject} " . $happening->name,
        %people,
        intro    => <<"EOF",
Hi $to,
<p>
$string{sum_intro}
<p>
$user_first
EOF
        template => "summary/email.tt2",
    );
}

sub email_do : Local {
    my ($self, $c, $sum_id) = @_;
    my $summary = model($c, 'Summary')->find($sum_id);
    my $type = $summary->program()? 'program': 'rental';
    my $intro = $c->request->params->{intro};
    my $subject = $c->request->params->{subject};
    my (@to, @cc);
    if (my $email1 = $c->request->params->{email1}) {
        push @to, $email1;
    }
    if (my $email2 = $c->request->params->{email2}) {
        push @to, $email2;
    }
    if ($c->request->params->{cc}) {
        @cc = split m{[\s,]+}, $c->request->params->{cc};
    }
    if (! @to && @cc) {
        @to = @cc;
        @cc = ();
    }
    if (! @to) {
        error($c,
            'Need at least one email address!',
            "summary/error.tt2",
        );
        return;
    }
    # use the template toolkit outside of the Catalyst mechanism
    my $tt = Template->new({
        INTERPOLATE  => 1,
        EVAL_PERL    => 0,
        INCLUDE_PATH => 'root/src/summary',
    });
    my $stash = {};
    for my $f (qw/
        gate_code
        alongside
        registration_location
        orientation
        wind_up
        alongside
        back_to_back
        leader_name
        staff_arrival
        staff_departure
        converted_spaces
    /) {
        $stash->{$f} = highlight($summary->$f());
    }
    my $happening = $summary->$type();
    my $sdate = $happening->sdate();
    my $nmonths = date($happening->edate())->month()
                - date($sdate)->month()
                + 1;
    if ($type eq 'program') {
        my $extra = $happening->extradays();
        if ($extra) {
            my $edate2 = $happening->edate_obj() + $extra;
            $stash->{plus} = "<b>Plus</b> $extra day"
                      . ($extra > 1? "s": "")
                      . " <b>To</b> " . $edate2
                      . " <span class=dow>"
                      . $edate2->format("%a")
                      . "</span>"
        }
    }
    $stash->{type}      = $type;
    $stash->{Type}      = ucfirst $type;
    $stash->{happening} = $happening;
    $stash->{sum}       = $summary;
    calc_sections($summary);
    $stash->{sections} = \@sections;
    my $html;
    $tt->process(
        "view.tt2", 
         $stash,
         \$html,
    ) or die "error in processing template: ";
    $html =~ s{<a\s+class=aa[^>]*>}{<span class=xy>}xmsg;
    $html =~ s{<a[^>]*>}{<span>}xmsg;
    $html =~ s{</a[^>]*>}{</span>}xmsg;
    $html =~ s{<b>Internal\s+Communications.*?</div>}{}xms;
    $html =~ s{Updated.*}{}xms;
    $html =~ s{<table cellpadding=5>\s*<tr>\s*<td>}{}xms;
    $html =~ s{<span>Email.*To\s+Bottom</span>}{}xms;
    $html =~ s{\A}{
        <style>
        body { margin: .5in; }
        .larger { font-size: 18pt; font-weight: bold; color: darkgreen; }
        .dow { color: red; }
        .xy { font-size: 18pt; color: blue; font-weight: bold; }
        </style>
        $intro
    }xms;
    my $user = $c->user->obj;
    email_letter($c,
        from    => $user->first . ' ' . $user->last
                 . '<' . $user->email . '>',
        to      => \@to,
        cc      => \@cc,
        subject => $subject,
        html    => $html,
    );
    $summary->update({
        date_sent => tt_today($c)->as_d8(),
        who_sent  => $c->user->obj->id,
        time_sent => get_time()->t24(),
    });
    $c->response->redirect($c->uri_for("/summary/view/$type/$sum_id"));
}

sub touch_sent : Local {
    my ($self, $c, $type, $sum_id) = @_;

    if (read_only()) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
    my $summary = model($c, 'Summary')->find($sum_id);
    $summary->update({
        date_sent => tt_today($c)->as_d8(),
        who_sent  => $c->user->obj->id,
        time_sent => get_time()->t24(),
    });
    $c->response->redirect($c->uri_for("/summary/view/$type/$sum_id"));
}

1;
