use strict;
use warnings;
package RetreatCenter::Controller::Program;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.
use Util qw/
    leader_table
    affil_table
    housing_types
    sys_template
    compute_glnum
    model
    trim
    empty
    lunch_table
    valid_email
    tt_today
    ceu_license
    email_letter
    stash
    error
    lines
    other_reserved_cids
    reserved_clusters
    palette
    esc_dquote
    invalid_amount
    clear_lunch
    get_lunch
    avail_mps
    refresh_table
    ensure_mmyy
    cf_expand
    months_calc
    new_event_alert
    time_travel_class
    too_far
    add_activity
    check_alt_packet
    check_file_upload
/;
use Date::Simple qw/
    date
    ymd
    today
    days_in_month
/;
use Time::Simple qw/
    get_time
/;
use Global qw/
    %string
    @clusters
    $lunch_always_date
/;
use File::Copy;
use Data::Dumper;

my $export_dir = '/var/Reg/export';
my $or = ("&nbsp;" x 4) . 'OR' . ("&nbsp;" x 4);
    # I couldn't figure out to do this in the template itself :(

# for Category, School, and Level
sub _opts {
    my ($c, $type, $default) = @_;
    my $opts = '';
    for my $l (model($c, $type)->all()) {
        my $index = $l->id();
        $opts .= "<option value=$index "
              .  ($index == $default? "selected": '')
              .  ">"
              .  $l->name()
              . "\n"
              ;
    }
    return $opts;
}

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('list');
}

sub create : Local {
    my ($self, $c, $rental) = @_;
        # $rental is optional - see sub parallel().

    my @name = ();
    my @dates = ();
    my $rental_id = 0;
    my $summary_id = 0;
    if ($rental) {
        push @name, name => $rental->name();
        push @dates, 
            sdate => $rental->sdate_obj->format("%D"),
            edate => $rental->edate_obj->format("%D"),
        ;
        $rental_id = $rental->id();
        $summary_id = $rental->summary_id();
        stash($c,
            dup_message => " - <span style='color: red'>Parallel</span>",
        );
    }
    Global->init($c);
    # set defaults by putting them in the stash
    #
    stash($c,
        check_webready      => '',
        check_tuition_rolled => '',
        check_linked        => 'checked',
        check_allow_dup_regs => '',
        check_kayakalpa     => 'checked',
        check_children_welcome => 'checked',
        check_covid_vax => '',
        check_strangers_share => '',
        check_retreat       => '',
        check_sbath         => 'checked',
        check_single        => 'checked',
        check_req_pay       => 'checked',
        check_collect_total => 'checked',
        check_reg_by_day    => '',
        check_donation      => '',
        check_economy       => '',
        check_commuting     => 'checked',
        check_dncc          => '',
        check_not_on_calendar => '',
        check_tub_swim      => 'checked',
        program_leaders     => [],
        program_affils      => [],
        section             => 1,   # Web (a required field)
        program             => {
            tuition      => 0,
            tuition_name => '',
            extradays    => 0,
            full_tuition => 0,
            deposit      => 0,
            donation_minimum => 0,
            color        => '',
            max          => 0,
            canpol       => { name => "Default" },  # clever way to set default!
            ptemplate    => 'default',
            cl_template  => 'default',
            reg_start_obj    => $string{reg_start},
            reg_end_obj      => $string{reg_end},
            prog_start_obj   => $string{prog_start},
            prog_end_obj     => $string{prog_end},
                # for updates [% program.reg_start_obj %] in the template
                # will take the Program database object, make a method call
                # to get the reg_start field, then
                # objectify it, then stringify it for display.
                # here for creates reg_start_obj is just a hash reference
                # off of %program above.
                # tricky!
            rental_id   => $rental_id,
            summary_id  => $summary_id,
            percent_tuition => 0,
            @name,
        },
        canpol_opts => [ model($c, 'CanPol')->search(
            undef,
            { order_by => 'name' },
        ) ],
        housecost_opts => [ model($c, 'HouseCost')->search(
            {
                inactive => { '!=' => 'yes' },
            },
            { order_by => 'name' },
        ) ],
        template_opts => [
            grep { $_ eq "default" || ! sys_template($_) }
            map { s{^.*templates/web/(.*)[.]html$}{$1}; $_ }
            <root/static/templates/web/*.html>
        ],
        cl_template_opts => [
            map { s{^.*templates/letter/(.*)[.]tt2$}{$1}; $_ }
            <root/static/templates/letter/*.tt2>
        ],
        cat_opts       => _opts($c, 'Category', 1),
        school_opts    => _opts($c, 'School', 1),
        level_opts     => _opts($c, 'Level', 1),
        @dates,
        show_level  => "hidden",
        form_action => "create_do",
        ORS          => $or,
        template    => "program/create_edit.tt2",
    );
}

my %readable = (
    sdate   => 'Start Date',
    edate   => 'End Date',
    tuition => 'Tuition',
    deposit => 'Deposit',
    name    => 'Name',
    title   => 'Title',
    full_tuition => 'Full Tuition',
    extradays    => 'Extra Days',
    donation_minimum => "Donation Minimum",
);
my %P;
my @mess;
sub _get_data {
    my ($c) = @_;

    %P = %{ $c->request->params() };

    # defaults now - things have changed with MMI programs
    $P{category_id} = 1;        # Normal
    $P{school_id} = 1;          # MMC
    $P{footnotes} = '';
    $P{url} = '';
    $P{bank_account} = 'mmc';
    if (empty $P{percent_tuition}) {
        $P{percent_tution} = '0';
    }
    #
    if ($P{school_id} == 1) {
        # MMC
        $P{level_id} = 1;      # course
    }
    # since unchecked boxes are not sent...
    for my $f (qw/
        req_pay
        collect_total
        reg_by_day
        tuition_rolled
        donation
        allow_dup_regs
        kayakalpa
        children_welcome
        strangers_share
        sbath
        single
        retreat
        economy
        commuting
        webready
        linked
        do_not_compute_costs
        not_on_calendar
        tub_swim
        waiver_needed
        covid_vax
        manual_reg_finance
        housing_not_needed 
    /) {
        $P{$f} = '' unless exists $P{$f};
    }
    $P{url} =~ s{^\s*http://}{};

    @mess = ();
    # no need for the check for MMI standalone course
    for my $f (qw/ name title /) {
        if ($P{$f} !~ m{\S}) {
            push @mess, "$readable{$f} cannot be blank";
        }
    }
    # naming conventions for Resident && MMI programs
    #
    #my $category = model($c, 'Category')->find($P{category_id});
    #if (! $category) {
    #    push @mess, "Unknown Category!";
    #}
    #else {
    #    my $name = $category->name();
    #    if ($name ne 'Normal') {
    #        if ($P{name} !~ m{^$name}) {
    #            push @mess, 'Name does not match the Category.';
    #        }
    #    }
    #    else {
    #        # what is happening here???
    #        # category is 'Normal' but the program name
    #        # might begin with another category?  yeah.
    #        my $cats = join '|',
    #                   map {
    #                       $_->name()        
    #                   }
    #                   model($c, 'Category')->search({
    #                       name => { '!=', 'Normal' },
    #                   })
    #                   ;
    #        if ($P{name} =~ m{^($cats)}) {
    #            push @mess, 'Name does not match the Category.';
    #        }
    #    }
    #}
    #if ($P{school_id} != 1
    #    && $P{name} !~ m{MMI}
    #) {
    #    push @mess, 'Name must have MMI in it';
    #}
    #if ($P{school_id} == 1
    #    && $P{name} =~ m{MMI}
    #) {
    #    push @mess, 'Name has MMI in it but the program is not sponsored by an MMI school';
    #}
    # verify the level and school match okay
    #my $level = model($c, 'Level')->find($P{level_id});
    #if (! $level) {
    #    push @mess, 'Illegal Level!!';
    #}
    #else {
    #    my $lev_name = $level->name();
    #    if ($level->school_id && $level->school_id != $P{school_id}) {
    #        my $school = model($c, 'School')->find($P{school_id});
    #        my $sch_name = $school->name();
    #        # we _could_ have some Javascript to only permit
    #        # certain allowable options in the <select> for Level.
    #        push @mess, "Level '$lev_name' does not match the Sponsoring Organization '$sch_name'";
    #    }
    #    # the program name must match the level name_regex
    #    my $regex = $level->name_regex();
    #    if ($regex && $P{name} !~ m{$regex}i) {
    #        push @mess, "Program name '$P{name}' does not match the Level '$lev_name'";
    #    }
    #}

    # dates are converted to d8 format
    my ($sdate, $edate);
    if (empty($P{sdate})) {
        push @mess, "Missing Start Date";
    }
    else {
        $sdate = date($P{sdate});
        if (! $sdate) {
            push @mess, "Invalid Start Date: $P{sdate}";
        }
        else {
            $P{sdate} = $sdate->as_d8();
            Date::Simple->relative_date($sdate);
            if (empty($P{edate})) {
                push @mess, "Missing End Date";
            }
            else {
                $edate = date($P{edate});
                if (! $edate) {
                    push @mess, "Invalid End Date: $P{edate}";
                }
                else {
                    $P{edate} = $edate->as_d8();
                }
            }
            Date::Simple->relative_date();
        }
    }

    if (!@mess && $sdate && $sdate > $edate) {
        push @mess, "End Date must be after the Start Date";
    }
    if (! @mess && (my $mess = too_far($c, $P{edate}))) {
        push @mess, $mess;
    }
    # ensure that the program name has mm/yy that matches the start date
    # - unless it is a Template
    #
    if (!@mess
        && $P{name} !~ m{personal\s+retreat}i
        && $P{name} !~ m{template}i
    ) {
        $P{name} = ensure_mmyy($P{name}, $sdate);
    }
    # check for numbers
    for my $f (qw/
        extradays tuition full_tuition deposit donation_minimum
    /) {
        if ($P{$f} !~ m{^\s*\d+\s*$}) {
            push @mess, "$readable{$f} must be a number";
        }
    }
    if (!empty($P{discount_code}) && $P{discount_pct} !~ m{\A \s*\d+\s*\z}xms) {
            push @mess, "Discount Percentage must be a number";
    }
    if ($P{tuition} > 0 && $P{donation}) {
        push @mess, "Cannot have both Tuition > 0 and Sliding Scale Tuition";
    }
    # check format of donation_tiers
    if (! empty($P{donation_tiers})) {
        my $s = $P{donation_tiers};
        $s =~ s{\b other \b}{}xmsi;
            # one or more digit sequences
            # surrounded by spaces optionally followed by a *
            #
        if ($s !~ m{\A ( \s* \d+ \s* [*]? \s* )+ \z }xms) {
            push @mess, "Incorrect format for Donation Tiers: $P{donation_tiers}";
        }
    }
    # Checking House Cost, etc
    #
    my $hc = model($c, 'HouseCost')->find($P{housecost_id});
    my $per_day = $hc->type eq 'Per Day';
    my $PR = $P{name} =~ m{Personal\s+Retreat}xmsi;
    if ($per_day && $P{tuition_rolled}) {
        push @mess, "Cannot have Rolled Tuition for Per Day House Cost";
    }
    if ($P{reg_by_day} && ! $per_day) {
        push @mess, "HouseCost must be Per Day when Program is Reg By Day";
    }
    if ($P{extradays}) {
        if ($P{full_tuition} <= $P{tuition}) {
            push @mess, "Full Tuition must be more than normal Tuition.";
        }
        # House cost must be Per Day
        if (! $per_day) {
            push @mess, "With Extra Day programs the House Cost must be Per Day";
        }
    }
    else {
        $P{full_tuition} = 0;    # it has no meaning if > 0.
        if ($PR) {
            if (! $per_day) {
                push @mess, "For Personal Retreats the House Cost must be Per Day";
            }
        }
        elsif (!$P{reg_by_day} && !$P{housing_not_needed} && $per_day) {
            push @mess, "The House Cost cannot be Per Day";
        }
    }
    if ($PR && $P{tuition} > 0) {
        push @mess, "Personal Retreats cannot have Tuition";
    }
    if ($P{footnotes} =~ m{[^*%+]}) {
        push @mess, "Footnotes can only contain *, % and +";
    }
    for my $t (qw/
        reg_start
        reg_end
        prog_start
        prog_end
    /) {
        my $time = get_time($P{$t});
        if (!$time) {
            push @mess, Time::Simple->error();
        }
        else {
            $P{$t} = $time->t24();
        }
    }
    # This check is no longer needed.  The Registar will
    # take responsibility for the times being correct.
    #
    #if ($P{school_id} == 1       # check times for MMC not MMI
    #    &&
    #    !(($P{reg_start}  <= $P{reg_end})
    #      && ($P{reg_end} <= $P{prog_start}))
    #) {
    #    push @mess, "Sequence error in the registration/program start/end times",
    #}
    my @email = split m{[, ]+}, $P{notify_on_reg};
    for my $em (@email) {
        if (! valid_email($em)) {
            push @mess, "Illegal email address: $em";
        }
    }
    $P{notify_on_reg} = join ', ', @email;

    $P{confnote} = cf_expand($c, $P{confnote});

    if (! empty($P{max})
        && $P{max} !~ m{^\s*\d+\s*$}
    ) {
        push @mess, "Max must be an integer";
    }
    if (! empty($P{end_reg_date_time})) { 
        if (my ($d, $t) = $P{end_reg_date_time} =~ m{
            \A \s* (\d\d/\d\d/\d\d\d\d) \s+ (\d\d:\d\d) \s* \z
           }xms
        ) {
            date($d);
            if (! date($d)) {
                push @mess, "Invalid Date for End Reg Date Time";
            }
            elsif (! get_time($t)) {
                push @mess, "Invalid Time for End Reg Date Time";
            }
        }
        else {
            push @mess, "Invalid End Reg Date Time format: mm/dd/yyyy hh:mm";
        }
    }
    if (exists $P{glnum} && $P{glnum} !~ m{ \A [0-9A-Z]* \z }xms) {
        push @mess, "The GL Number must only contain digits and upper case letters.";
    }
    if (!empty($P{discount_code}) && empty($P{discount_pct})) {
        push @mess, "Discount Percentage cannot be blank.";
    }
    if (empty($P{discount_code}) && !empty($P{discount_pct})) {
        push @mess, "Discount Code cannot be blank.";
    }
    if (@mess) {
        error($c,
            join("<br>\n", @mess),
            "program/error.tt2",
        );
    }
}

sub create_do : Local {
    my ($self, $c) = @_;

    _get_data($c);
    return if @mess;

    delete $P{section};      # irrelevant

    # gl num is computed not gotten
    $P{glnum} = ($P{name} =~ m{personal\s+retreat}i)?
                                   '99999'
               :($P{school_id} != 1)? 'XX'     # MMI programs/courses
               :                   compute_glnum($c, $P{sdate})
               ;

    $P{reg_count} = 0;       # otherwise it will not increment
    $P{bank_account} ||= 'mmc';     # it defaults but to be safe ...

    if (! $P{summary_id}) {
        # we do not have a summary already from
        # a parallel rental

        # create the summary from the right template
        #
        my $prefix = $P{school_id} != 1? 'MMI': 'MMC';
        my @prog = model($c, 'Program')->search({
            name => "$prefix Template",
        });
        my @dup_summ = ();
        if (@prog) {
            my $template_sum
                = model($c, 'Summary')->find($prog[0]->summary_id());
            @dup_summ = $template_sum->get_columns(),
        }
        else {
            # could find no template - just make a blank summary
        }
        my $sum = model($c, 'Summary')->create({
            @dup_summ,
            # and then override the following:
            id           => undef,          # new id
            date_updated => tt_today($c)->as_d8(),
            who_updated  => $c->user->obj->id,
            time_updated => get_time()->t24(),
            gate_code => '',
            needs_verification => 'yes',
        });
        $P{summary_id} = $sum->id();
    }

    check_alt_packet($c, 'program') || return;

    my $file = check_file_upload($c, 'program', $P{file_desc});
    return if $file eq 'error';

    # remove parameters that are not Program attributes
    delete $P{file_name};
    delete $P{file_desc};

    # now we can create the program itself
    #
    my $p = model($c, 'Program')->create({
        lunches    => '',
        refresh_days => '',
        rental_id  => 0,        # overridden by hybrid
        %P,         # this includes rental_id for a possible parallel rental
                    # and also a summary_id for the parallel rental
                    # OR a freshly created summary id.
        program_created => tt_today($c)->as_d8(),
        created_by => $c->user->obj->id,
        cancelled => '',
    });
    my $id = $p->id();

    # update any uploaded File with the program id now that we have it
    if (ref $file) {
        $file->update({
            program_id => $id,
        });
    }

    if ($P{rental_id}) {
        # we just created a parallel program
        # put its id in its corresponding parallel rental.
        # this is all very tricky!
        #
        my $r = model($c, 'Rental')->find($P{rental_id});
        $r->update({
            program_id => $id,
        });
    }
    _finalize_program_creation($c, $id);
}

sub _finalize_program_creation {
    my ($c, $id) = @_;

    my $url = $c->uri_for("/program/view/$id");

my $x = <<'EOC';
    # no more 3/6/19
    #                              MMI   and   Course or Public Course
    my $glnum_popup = $P{school_id} != 1 && $P{level_id} <= 2;
    if ($glnum_popup) {
        #
        # send email to all of the account admins
        # that they need to concoct a GL number for this program
        #
        my ($role) = model($c, 'Role')->search({
                         role => 'account_admin',
                     });
        my @users = $role->users;
        my $acct_admin_names = join ', ', map { $_->first } @users;
        my $cur_user = $c->user->first;
        email_letter($c,
            to      => (join ', ', map { $_->email } @users),
            cc      => $c->user->email,
            subject => "$P{name} needs a GL Number",
            from    => "$string{from_title} <$string{from}>",
            html    => <<"EOH",
Greetings $acct_admin_names,
<p>
A new program has been added that needs a GL number.<br>
Its name is:
<ul>
<a href=$url>$P{name}</a>
</ul>
Thank you,<br>
$cur_user
EOH
        );
    }

    # send an email alert about this new program
    new_event_alert(
        $c,
        $P{school_id} == 1, 'Program',
        $P{name}, 
        $url,
    );
EOC
    $c->response->redirect($c->uri_for("/program/view/$id/1"));
}

my @day_name = qw/
    Sun
    Mon
    Tue
    Wed
    Thu
    Fri
    Sat
/;
sub view : Local {
    my ($self, $c, $id, $section, $glnum_popup) = @_;

    Global->init($c);       # for web_addr if nothing else.
    $section ||= 1;
    $glnum_popup ||= 0;
    stash($c, section => $section);

    my $p;
    if ($id == 0) {
        # a personal retreat reg from online
        # show the current Personal Retreat program
        # this is not ideal - but okay 
        #
        my $today = today()->as_d8();
        ($p) = model($c, 'Program')->search({
            name  => { -like => '%personal%retreat%' },
            sdate => { '<=' => $today },
            edate => { '>=' => $today },
        });
        if ($p) {
            $id = $p->id();
        }
    }
    else {
        $p = model($c, 'Program')->find($id);
    }
    if (! $p) {
        error($c,
            "Program not found.",
            "gen_error.tt2",
        );
        return;
    }
    # Check if program is editable
    my $current_date = tt_today($c);
    my $is_editable = 1;

    if ($current_date > $p->edate2_obj + $string{max_days_after_program_ends}) {
        $is_editable = 0;
    }

    # was this program's web page generated by Reg?
    # if so, we display/edit several more fields - like webdesc, etc
    my $pre_craft = $p->sdate <= $string{pre_craft};

    stash($c,
        pre_craft => $pre_craft,
        program   => $p,
        editable  => $is_editable,
        pg_title  => $p->name(),
    );
    my $extra = $p->extradays();
    if ($extra) {
        my $edate2 = $p->edate_obj() + $extra;
        stash($c,
            plus => "<b>Plus</b> $extra day"
                  . ($extra > 1? "s": '')
                  . " <b>To</b> " . $edate2
                  . " <span class=dow>"
                  . $edate2->format("%a")
                  . "</span>"
        );
    }

    #
    # no lunches for personal retreat, resident programs,
    # or credentialed long term MMI programs.
    #
    if (! ($p->PR()
           || $p->category->name() ne 'Normal'
           || $p->level->long_term()
           || $p->sdate_obj >= $lunch_always_date
          )
    ) {
        stash($c,
              lunch_table => lunch_table(
                                 1,
                                 $p->lunches(),
                                 $p->sdate_obj(),
                                 $p->edate_obj() + $p->extradays(),
                                 $p->prog_start_obj(),
                             ),
        );
    }
    if (! ($p->PR()
           || $p->category->name() ne 'Normal'
           || $p->level->long_term())       # no credentialed programs
        && ($p->edate()-$p->sdate()+1+$p->extradays() >= 7)
    ) {
        stash($c,
            refresh_table => refresh_table(
                                 1,
                                 $p->refresh_days(),
                                 $p->sdate_obj(),
                                 $p->edate_obj() + $p->extradays(),
                             ),
        );
    }

    my @files = </var/Reg/online/*>;
    my $sdate = $p->sdate();
    my $nmonths = months_calc(date($sdate), date($p->edate()));

    my ($UNres, $res) = split /XX/, _get_cluster_groups($c, $id, $is_editable);

    my @acct_adm_name;
    if ($glnum_popup) {
        my ($role) = model($c, 'Role')->search({
                         role => 'account_admin',
                     });
        @acct_adm_name = (acct_adm_name => join ' and ',
                                           map { $_->first }
                                           $role->users);
    }
    stash($c,
        cgi                 => $string{cgi},
        glnum_popup         => $glnum_popup,
        @acct_adm_name,
        UNreserved_clusters => $UNres,
        reserved_clusters   => $res,
        online              => scalar(@files),
        daily_pic_date      => ($p->category->name() eq 'Normal'? "indoors"
                                :                                 "resident")
                                . "/$sdate",
        cluster_date        => $sdate,
        cal_param           => "$sdate/$nmonths",
        leaders_house       => $p->leaders_house($c),
        template            => "program/view.tt2",
    );
}

sub _get_cluster_groups {
    my ($c, $program_id, $is_editable) = @_;

    my @reserved = reserved_clusters($c, $program_id, 'Program');
    my %my_reserved_ids;
    my $reserved = "<tr><th align=left>Reserved</th></tr>\n";
    CLUSTER:
    for my $cl (@reserved) {
        my $cid = $cl->id();
        $my_reserved_ids{$cid} = 1;
        $reserved .=
           "<tr><td>"
           . ($is_editable ? "<a href='#' onclick='UNreserve_cluster($cid); return false;'>" : "")
           . $cl->name()
           . ($is_editable ? "</a>" : "")
           . "</td></tr>\n"
           ;
    }
    my $UNreserved = "<tr><th align=left>Available</th></tr>\n";

    #
    # what distinct cluster ids are already taken by
    # other programs or rentals that overlap this program?
    #
    my $prog = model($c, 'Program')->find($program_id);
    my %cids = other_reserved_cids($c, $prog);

    #
    # and that leaves what clusters as available?
    #
    CLUSTER:
    for my $cl (@clusters) {
        my $id = $cl->id();
        next CLUSTER if exists $my_reserved_ids{$id} || exists $cids{$id};
        $UNreserved
            .= "<tr><td>"
            .  ($is_editable ? "<a href='#' onclick='reserve_cluster($id); return false;'>" : "")
            .  $cl->name()
            .  ($is_editable ? "</a>" : "")
            .  "</td></tr>\n"
            ;
    }
    return "<table>\n$UNreserved</table>XX<table>\n$reserved</table>";
}

sub list : Local {
    my ($self, $c, $type) = @_;

    $type ||= '';
    my $hide_mmi = $c->user->obj->hide_mmi();
    #if ($type eq '2') {
    #    my $today = today()->as_d8();
    #    $string{date_coming_going_printed} = $today;
    #    model($c, 'String')->find('date_coming_going_printed')->update({
    #        value => $today,
    #    });
    #}
    # ??? how to include programs that are extended and not quite finished???
    # good enough to include programs that may have finished a week ago?
    #
    my $cutoff = tt_today($c) - 7;
    my $end_date = $cutoff + $string{default_num_prog_days};
    $cutoff = $cutoff->as_d8();
    $end_date = $end_date->as_d8();
    my @cond = ();
    if ($type eq 'long_term') {     # obsolete
        @cond = (
            'category.name' => 'Normal',
            'level.long_term' => 'yes',
            edate => { '>=', 19890101 },       # all programs not just current.
                                # this overrides the cutoff one below
        );
    }
    elsif ($type eq 'monthly') {
        @cond = (
            -or => [
                'me.name' => { -like => 'Personal Retreats%' },
                'me.name' => { -like => 'Special Guests%' },
                'me.name' => { -like => 'MMS Parent%' },
            ],
        );
    }
    elsif ($type eq 'mmi') {
        @cond = (
            'me.name' => { -like => '%MMI%' },
        );
    }
    elsif ($type eq 'other') {
        @cond = (
            -and => [
                'me.name' => { -not_like => 'Personal Retreats%' },
                'me.name' => { -not_like => 'Special Guests%' },
                'me.name' => { -not_like => 'MMS Parent%' },
                'me.name' => { -not_like => '%MMI%' },
            ],
        );
    }
    else {
        @cond = (
            'category.name'   => 'Normal',
            'level.long_term' => '',
        );
        if ($hide_mmi) {
            push @cond, ('me.name' => { -not_like => '%MMI%' });      # only MMC no MMI
        }
    }
    stash($c,
        programs => [
            model($c, 'Program')->search(
                {
                    edate => { -between => [ $cutoff, $end_date ] },
                    @cond,
                },
                {
                    join     => [qw/ category school level /],
                    prefetch => [qw/ category /],
                    order_by => [qw/ sdate me.name /]
                },
            )
        ]
    );
    my @files = </var/Reg/online/*>;
    stash($c,
        time_travel_class($c),
        long_term => $type eq 'long_term',
        pg_title  => "Programs",
        online    => scalar(@files),
        pr_pat    => '',
        template  => "program/list.tt2",
    );
}

# ??? order of display?   also end date???
sub listpat : Local {
    my ($self, $c) = @_;

    my @hide_mmi = $c->user->obj->hide_mmi()?
                       ('me.name' => { -not_like => '%MMI%' })
                     : ();
    my $today = tt_today($c)->as_d8();
    my $pr_pat = trim($c->request->params->{pr_pat});
    if (empty($pr_pat)) {
        $c->forward('list');
        return;
    }
    my $cond;
    if ($pr_pat =~ m{(^[fs])(\d\d)}i) {
        my $seas = $1;
        my $year = $2;
        $seas = lc $seas;
        if ($year > 70) {
            $year += 1900;
        }
        else {
            $year += 2000;
        }
        my ($d1, $d2);
        if ($seas eq 'f') {
            $d1 = $year . '1001';
            $d2 = ($year+1) . '0331';
        }
        else {
            $d1 = $year . '0401';
            $d2 = $year . '0930';
        }
        $cond = {
            @hide_mmi,
            sdate => { 'between' => [ $d1, $d2 ] },
        };
    }
    elsif ($pr_pat =~ m{^((\d\d)?\d\d)$}) {
        my $year = $1;
        if ($year > 70 && $year <= 99) {
            $year += 1900;
        }
        elsif ($year < 70) {
            $year += 2000;
        }
        $cond = {
            @hide_mmi,
            sdate => { 'between' => [ "${year}0101", "${year}1231" ] },
        };
    }
    elsif ($pr_pat =~ m{id=(\d+)}xms) {
        $c->response->redirect($c->uri_for("/program/view/$1/1"));
        return;
    }
    else {
        my $pat = $pr_pat;
        $pat =~ s{\*}{%}g;
        $cond = {
            @hide_mmi,
            name => { 'like' => "${pat}%" },
        };
    }
    my @files = </var/Reg/online/*>;
    stash($c,
        pg_title => "Programs",
        online   => scalar(@files),
        programs => [
            model($c, 'Program')->search(
                $cond,
                { order_by => ['sdate asc', 'me.id asc'] },
            )
        ],
        pr_pat   => $pr_pat,
        template => "program/list.tt2",
    );
}

sub update : Local {
    my ($self, $c, $id, $section) = @_;

    $section ||= 1;
    my $p = model($c, 'Program')->find($id);
    for my $w (qw/
        sbath single req_pay collect_total reg_by_day
        tuition_rolled
        donation
        allow_dup_regs kayakalpa
        children_welcome
        strangers_share
        retreat
        economy commuting webready linked do_not_compute_costs
        not_on_calendar tub_swim waiver_needed covid_vax housing_not_needed
        manual_reg_finance
    /) {
        stash($c,
            "check_$w" => ($p->$w)? "checked": ''
        );
    }
    for my $w (qw/ sdate edate /) {
        stash($c,
            $w => date($p->$w)->format("%D") || ''
        );
    }

    # was this program's web page generated by Reg?
    # if so, we display/edit several more fields - like webdesc, etc
    my $pre_craft = $p->sdate <= $string{pre_craft};

    my $bank = $p->bank_account() || 'mmc';
    stash($c,
        section     => $section,
        program     => $p,
        pre_craft   => $pre_craft,
        bank_mmi => $bank eq 'mmi'? 'checked': '',
        bank_mmc => $bank eq 'mmc'? 'checked': '',
        bank_both => $bank eq 'both'? 'checked': '',
        canpol_opts => [ model($c, 'CanPol')->search(
            undef,
            { order_by => 'name' },
        ) ],
        housecost_opts =>
            [ model($c, 'HouseCost')->search(
                {
                    -or => [
                        id       => $p->housecost_id,
                        inactive => { '!=' => 'yes' },
                    ],
                },
                { order_by => 'name' },
            ) ],
        template_opts => [
            grep { $_ eq "default" || ! sys_template($_) }
            map { s{^.*templates/web/(.*)[.]html$}{$1}; $_ }
            <root/static/templates/web/*.html>
        ],
        cl_template_opts => [
            map { s{^.*templates/letter/(.*)[.]tt2$}{$1}; $_ }
            <root/static/templates/letter/*.tt2>
        ],
        webdesc_rows => lines($p->webdesc()) + 5,
        cat_opts     => _opts($c, 'Category', $p->category_id()),
        school_opts  => _opts($c, 'School', $p->school_id()),
        level_opts   => _opts($c, 'Level', $p->level_id()),
        show_level   => $p->school->mmi()? 'visible': 'hidden',
        edit_gl      => $c->check_user_roles('account_admin') || 0,
        form_action  => "update_do/$id",
        ORS          => $or,
        template     => "program/create_edit.tt2",
    );
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    my $p = model($c, 'Program')->find($id);
    _get_data($c);
    return if @mess;

    if ($P{prog_start} >= 1300
        &&
        $p->sdate_obj() < $lunch_always_date
    ) {
        # can't have lunch on the first day
        #
        clear_lunch();
        my ($event_start, $lunches) = get_lunch($c, $id, 'Program');
        if ($lunches && substr($lunches, 0, 1) == 1) {
            error($c,
                  "Can't have lunch since program start time is after 1:00 pm!",
                  'gen_error.tt2');
            return;
        }
    }
    my $section = $P{section};
    delete $P{section};

    if (! $c->check_user_roles('prog_admin')) {
        delete $P{glnum};
    }
    $P{max} ||= 0;
    if (   $p->sdate       ne $P{sdate}
        || $p->edate       ne $P{edate}
        || $p->extradays() != $P{extradays}
    ) {
        _check_several_things($c, $p, 'change the dates of or add extra days to ')
            or return;
        $P{lunches} = '';
        $P{refresh_days} = '';
    }

    check_alt_packet($c, 'program', $p) || return;
 
    my $file = check_file_upload($c, 'program', $P{file_desc});
    return if $file eq 'error';
    if (ref $file) {
        $file->update({
            program_id => $id,
        });
    }

    # remove parameters that are not Program attributes
    delete $P{file_name};
    delete $P{file_desc};

    # if we changed where we expect payments (MMC vs MMI)
    # we will need to recalculate all registration balances AFTER the update.
    my $recalc = $p->bank_account ne $P{bank_account};
    $p->update(\%P);
    if ($recalc) {
        for my $reg ($p->registrations()) {
            $reg->calc_balance();
        }
    }
    $c->response->redirect($c->uri_for("/program/view/"
                           . $p->id . "/$section"));
}

sub del_alt_packet : Local {
    my ($self, $c, $id) = @_;
    my $p = model($c, 'Program')->find($id);
    unlink '/var/Reg/documents/' . $p->alt_packet;
    $p->update({
        alt_packet => '',
    });
    $c->response->redirect($c->uri_for("/program/view/$id/2"));
}

sub leader_update : Local {
    my ($self, $c, $id) = @_;

    my $p = model($c, 'Program')->find($id);
    stash($c,
        program      => $p,
        leader_table => leader_table($c, $p->leaders()),
        template     => "program/leader_update.tt2",
    );
}

sub leader_update_do : Local {
    my ($self, $c, $prog_id) = @_;

    my $program = model($c, 'Program')->find($prog_id);
    my @cur_leaders = grep {  s{^lead(\d+)}{$1}  }
                      keys %{$c->request->params};
    # delete all old leaders and create the new ones.
    model($c, 'LeaderProgram')->search(
        { p_id => $prog_id },
    )->delete();
    for my $cl (@cur_leaders) {
        model($c, 'LeaderProgram')->create({
            l_id => $cl,
            p_id => $prog_id,
        });
    }
    #
    # ensure that the leaders are registered for the program.
    #
    my $new_regs = 0;
    for my $cl (@cur_leaders) {
        my $leader = model($c, 'Leader')->find($cl);
        my $assist = $leader->assistant();
        my $person_id = $leader->person->id();
        my ($reg) = model($c, 'Registration')->search({
            person_id  => $person_id,
            program_id => $prog_id,
        });
        if (! $reg) {
            # need to register them
            # we will house them later...
            #
            my $edate = date($program->edate()) + $program->extradays();
            model($c, 'Registration')->create({
                person_id  => $person_id,
                program_id => $prog_id,
                comment    => '',
                house_id   => 0,
                h_type     => $assist? 'dble': 'single_bath',
                cancelled  => '',    # to be sure
                arrived    => '',    # ditto
                date_start => $program->sdate(),
                date_end   => $edate->as_d8(),
                balance    => 0,
                leader_assistant => 'yes',      # only way to set this
                pref1      => $assist? 'dble': 'single_bath',
                pref2      => $assist? 'dble': 'single_bath',
                transaction_id => 0,
            });
            ++$new_regs;
        }
        else {
            # make sure they're marked as 'leader_assistant'
            if (! $reg->leader_assistant()) {
                $reg->update({
                    leader_assistant => 'yes',
                });
            }
            # awkward - no real easy way to UNmark someone
            # as an assistant/leader except to delete their registration
            # and then re-register them as a leader.
            # oh well.
            # in a similar way to recompute someone's finances
            # you have to vacate and then rehouse them.
            # oh well.  -  later???
            # 
        }
    }
    if ($new_regs) {
        $program->update({
            reg_count => $program->reg_count() + $new_regs,
        });
    }
    $c->response->redirect($c->uri_for("/program/view/$prog_id/2"));
}

sub affil_update : Local {
    my ($self, $c, $id) = @_;

    my $p = model($c, 'Program')->find($id);
    stash($c,
        program     => $p,
        affil_table => affil_table($c, 0, $p->affils()),
        template    => "program/affil_update.tt2",
    );
}

sub affil_update_do : Local {
    my ($self, $c, $id) = @_;

    my @new_affils = grep {  s{^aff(\d+)}{$1}  }
                     keys %{$c->request->params};

    # make sure that all existing registrants have
    # all of the new affiliations.
    #
    my $prog = model($c, 'Program')->find($id);
    for my $person (map { $_->person } $prog->registrations) {
        my $person_id = $person->id;
        my %cur_affils = map { $_->id => 1 }
                         grep { $_->descrip() ne 'None' }
                         $person->affils;
        for my $new_pr_affil_id (@new_affils) {
            if (! exists $cur_affils{$new_pr_affil_id}) {
                model($c, 'AffilPerson')->create({
                    a_id => $new_pr_affil_id,
                    p_id => $person_id,
                });
            }
        }
    }
    # delete all old affils and create the new ones.
    model($c, 'AffilProgram')->search(
        { p_id => $id },
    )->delete();
    for my $ca (@new_affils) {
        model($c, 'AffilProgram')->create({
            a_id => $ca,
            p_id => $id,
        });
    }
    $c->response->redirect($c->uri_for("/program/view/$id/2"));
}

#
# what if it is a hybrid???
# it cascades and deletes the rental - wow! is this good?!
#
sub delete : Local {
    my ($self, $c, $id) = @_;

    my $p = model($c, 'Program')->find($id);

    if ($p->rental_id) {
        error($c,
            "This is a hybrid.  Ask Sahadev for help in deleting it.",
            'gen_error.tt2',
        );
        return;
        # cascading deletes are very confusing in DBIx::Class
        # perhaps it is better in the latest version which we
        # do not have ...
        # what to do?   just prohibit it from the UI.
        # first clear out any registrations, bookings, etc from the program
        # then on the mysql command line 
        # - update the rental and set program_id to 0
        #   and mmi_does_reg to ''
        # - delete the program (it won't cascade)
    }

    _check_several_things($c, $p, 'delete') or return;

    # affiliation/programs
    model($c, 'AffilProgram')->search({
        p_id => $id,
    })->delete();

    # leader/programs
    model($c, 'LeaderProgram')->search({
        p_id => $id,
    })->delete();

    # the summary
    $p->summary->delete();

    # any alt packet
    if ($p->alt_packet) {
        unlink '/var/Reg/documents/' . $p->alt_packet;
    }

    # and finally, the program itself
    $p->delete();

    $c->response->redirect($c->uri_for('/program/list'));
}

sub _check_several_things {
    my ($c, $p, $what) = @_;
    my $id = $p->id;
    my @bookings = $p->bookings();
    my @blocks = $p->blocks();
    my @regs = $p->registrations();
    my @res_clust = reserved_clusters($c, $id, 'Program');
    if (@bookings || @blocks || @regs || @res_clust) {
        stash($c,
            action => "/program/view/$id",
            message => "Sorry, cannot $what a program when there are"
                     . ' meeting place bookings, blocks, registrations, or reserved clusters.',
            template => 'action_message.tt2',
        );
        return 0;
    }
    return 1;
}

sub access_denied : Private {
    my ($self, $c) = @_;

    error($c,
        "Authorization denied!",
        "gen_error.tt2",
    );
}

sub update_lunch : Local {
    my ($self, $c, $id) = @_;

    my $p = model($c, 'Program')->find($id);
    stash($c,
        program     => $p,
        lunch_table => lunch_table(0,
                                   $p->lunches,
                                   $p->sdate_obj,
                                   $p->edate_obj + $p->extradays,
                                   $p->prog_start_obj(),
                                  ),
        template    => "program/update_lunch.tt2",
    );
}

sub update_lunch_do : Local {
    my ($self, $c, $id) = @_;

    %P = %{ $c->request->params() };
    my $p = model($c, 'Program')->find($id);
    my $ndays = $p->edate_obj - $p->sdate_obj + 1 + $p->extradays;
    my $l = '';
    for my $n (0 .. $ndays-1) {
        $l .= (exists $P{"d$n"})? "1": "0";
    }
    $p->update({
        lunches => $l,
    });
    if (my $r_id = $p->rental_id()) {
        my $r = model($c, 'Rental')->find($r_id);
        if ($r) {
            $r->update({
                lunches => $l,
            });
        }
    }
    $c->response->redirect($c->uri_for("/program/view/$id/1"));
}

# should duplicate ONLY ask for new dates?
# no.   this is the time to change things from the old one.
#
sub duplicate : Local {
    my ($self, $c, $id) = @_;
    my $orig_p = model($c, 'Program')->find($id);

    # things that are different from the original:
    # tricky!  we will duplicate the summary but
    # not a parallel program.  the user will need to
    # reset "MMC Does Registration" themselves.
    #
    $orig_p->set_columns({
        id      => undef,
        sdate   => '',
        edate   => '',
        lunches => '',
        refresh_days => '',
        glnum   => '',
        rental_id => 0,
        webready => 0,
    });
    for my $w (qw/
        sbath single req_pay collect_total reg_by_day
        donation
        tuition_rolled
        allow_dup_regs kayakalpa
        children_welcome
        strangers_share
        retreat
        commuting economy webready linked
        not_on_calendar tub_swim
    /) {
        stash($c,
            "check_$w" => ($orig_p->$w)? "checked": ''
        );
    }
    stash($c,
        canpol_opts => [ model($c, 'CanPol')->search(
            undef,
            { order_by => 'name' },
        ) ],
        housecost_opts =>
            [ model($c, 'HouseCost')->search(
                {
                    -or => [
                        id       => $orig_p->housecost_id,
                        inactive => { '!=' => 'yes' },
                    ],
                },
                { order_by => 'name' },
            ) ],
        template_opts => [
            grep { $_ eq "default" || ! sys_template($_) }
            map { s{^.*templates/web/(.*)[.]html$}{$1}; $_ }
            <root/static/templates/web/*.html>
        ],
        cl_template_opts => [
            map { s{^.*templates/letter/(.*)[.]tt2$}{$1}; $_ }
            <root/static/templates/letter/*.tt2>
        ],
        cat_opts    => _opts($c, 'Category', $orig_p->category_id()),
        school_opts => _opts($c, 'School', $orig_p->school_id()),
        level_opts  => _opts($c, 'Level', $orig_p->level_id()),
        show_level  => $orig_p->school->mmi()? 'visible': 'hidden',
        section     => 1,   # Web (a required field)
        edit_gl     => 0,
        program     => $orig_p,      # with modifed columns
        form_action => "duplicate_do/$id",
        dup_message => " - <span style='color: red'>Duplication</span>",
            # forgive me for putting html/css here!
            # i didn't want the dash '-' to be red
            # and the dash shouldn't be there if there's no message...
            # I could have done a conditional in the template
            # but that would be more complex, yes?
        template    => "program/create_edit.tt2",
    );
}

#
# duplicated code here from create_do - can we not repeat ourself - DRY???
# should we?   let's not worry about that for now.
# there are several extra things that a duplication requires.
# We did put some common ending things in sub _finalize_program_creation as a start...
#
# The title of a personal retreat will be taken directly
# from the name.
#
sub duplicate_do : Local {
    my ($self, $c, $old_id) = @_;
    _get_data($c);
    return if @mess;

    delete $P{section};      # irrelevant

    if ($P{name} =~ m{ personal \s+ retreat }xmsi) {
        $P{title} = $P{name};
    }
    # gl num is computed not gotten
    $P{glnum} = ($P{name} =~ m{personal\s+retreat}i)?
                                   '99999'
               :($P{school_id} != 1)? 'XX'     # MMI programs/courses
               :                   compute_glnum($c, $P{sdate})
               ;

    $P{reg_count} = 0;       # otherwise it will not increment

    # get the old program and the old summary
    my ($old_prog)    = model($c, 'Program')->find($old_id);
    my ($old_summary) = $old_prog->summary();

    my $sum = model($c, 'Summary')->create({
        $old_summary->get_columns(),        # to dup the old ...
        id => undef,                        # with a new id
        date_updated => tt_today($c)->as_d8(),   # and new update status info
        who_updated  => $c->user->obj->id,
        time_updated => get_time()->t24(),
        gate_code => '',
        needs_verification => 'yes',
    });
    my @tprog = model($c, 'Program')->search({
        name => "MMC Template",
    });
    if (@tprog) {
        my $template_sum = model($c, 'Summary')->find($tprog[0]->summary_id());
        $sum->update({
            check_list => $template_sum->check_list(),
        });
    }

    my $file = check_file_upload($c, 'program', $P{file_desc});
    return if $file eq 'error';

    # remove parameters that are not Program attributes
    delete $P{file_name};
    delete $P{file_desc};

    # now we can create the new dup'ed program
    my $new_p = model($c, 'Program')->create({
        %P,     # this comes first so summary_id can override
        summary_id => $sum->id,
        program_created => tt_today($c)->as_d8(),
        created_by => $c->user->obj->id,
        cancelled => '',
    });

    my $new_id = $new_p->id();

    # copy the leaders and affils
    my @leader_programs = model($c, 'LeaderProgram')->search({
        p_id => $old_id,
    });
    for my $lp (@leader_programs) {
        model($c, 'LeaderProgram')->create({
            l_id => $lp->l_id(),
            p_id => $new_id,
        });
    }
    my @affil_programs = model($c, 'AffilProgram')->search({
        p_id => $old_id,
    });
    for my $ap (@affil_programs) {
        model($c, 'AffilProgram')->create({
            a_id => $ap->a_id(),
            p_id => $new_id,
        });
    }

    _finalize_program_creation($c, $new_id);
}

# AJAX call to reserve a cluster for this program
sub reserve_cluster : Local {
    my ($self, $c, $program_id, $cluster_id) = @_;

    model($c, 'ProgramCluster')->create({
        program_id => $program_id,
        cluster_id => $cluster_id,
    });
    $c->res->output(_get_cluster_groups($c, $program_id, 1));
}

# AJAX call to UNreserve a cluster
sub UNreserve_cluster : Local {
    my ($self, $c, $program_id, $cluster_id) = @_;

    model($c, 'ProgramCluster')->search({
        program_id => $program_id,
        cluster_id => $cluster_id,
    })->delete();
    $c->res->output(_get_cluster_groups($c, $program_id, 1));
}

# find the 'current' program - not a Personal Retreat
# and show the alphabetically first registrant.
sub cur_prog : Local {
    my ($self, $c) = @_;
    
    my $today_d8 = tt_today($c)->as_d8();
    my @progs = model($c, 'Program')->search(
        {
            edate => { '>=', $today_d8 },
            name  => { -not_like => "%personal%retreat%" },
        },
        {
            rows     => 1,
            order_by => 'sdate',
        },
    );
    if (@progs) {
        $c->response->redirect($c->uri_for("/registration/first_reg/"
                                           . $progs[0]->id()));
    }
    else {
        $c->response->redirect($c->uri_for("/program/list"));
    }
}

sub ceu : Local {
    my ($self, $c, $prog_id) = @_;    

    my $html = '';
    for my $r (model($c, 'Registration')->search({
                   program_id  => $prog_id,
                   ceu_license => { "!=", '' },
                   cancelled => { "!=", 'yes' },
               }) 
    ) {
        $html .= ceu_license($r)
              .  "<div style='page-break-after:always'></div>\n"
              ;
    }
    if (! $html) {
        $html = "No one requested a CEU.";
    }
    $c->res->output($html);
}

sub email_all : Local {
    my ($self, $c, $id) = @_;

    my $p = model($c, 'Program')->find($id);
    stash($c,
        program  => $p,
        template => "program/email_all.tt2",
    );
}

sub email_all_do : Local {
    my ($self, $c, $id) = @_;

    my $subj = $c->request->params->{subject};
    my $body = $c->request->params->{body};
    @mess = ();
    if (empty($subj)) {
        push @mess, "Missing subject";
    }
    if (empty($body)) {
        push @mess, "Missing body of letter";
    }
    if (@mess) {
        error($c,
            join("<br>\n", @mess),
            "program/error.tt2",
        );
        return;
    }
    my $cc = $c->request->params->{cc};
    my $p = model($c, 'Program')->find($id);
    my @regs = model($c, 'Registration')->search(
        {
            program_id   => $id,
            cancelled    => '',
        },
        {
            join     => qw/person/,
            prefetch => qw/person/,
        },
    );
    my (@emails, @snails);
    for my $r (@regs) {
        if (empty($r->person->email())) {
            push @snails, $r->person();
        }
        else {
            push @emails, $r->person->name_email();
        }
    }
    Global->init($c);
    email_letter($c,
        to      => 'noreply@mountmadonna.org',
        bcc     => \@emails,
        subject => $subj,
        from    => "$string{from_title} <$string{from}>",
        html    => $body,
        which   => "To All in Program " . $p->name . " - $subj",
    );
    # sort by last, first
    @snails = map {
                  $_->[1],
              }
              sort {
                  $a->[0] cmp $b->[1]
              }
              map {
                  [ $_->last() . ", " . $_->first(), $_ ],
              }
              @snails;

    my $ne = @emails;
    my $ns = @snails;
    stash($c,
        program  => $p,
        nemail   => $ne . (($ne == 1)? " person": " people"),
        nsnail   => $ns . (($ns == 1)? " person": " people"),
        snails   => \@snails,
        template => "program/email_report.tt2",
    );
}

#
# we have just created or updated a rental and
# mmc_does_reg was set to true (yes) from either not being
# set at all (creation) or from being not set.
# put up a program creation dialog with name and dates taken
# from the rental.
#
sub parallel : Local {
    my ($self, $c, $rental_id) = @_;
    my $rental = model($c, 'Rental')->find($rental_id);
    __PACKAGE__->create($c, $rental);
}

sub view_parallel : Local {
    my ($self, $c, $rental_id) = @_;
    my $rental = model($c, 'Rental')->find($rental_id);
    my $name = $rental->name();
    my $sdate = $rental->sdate();
    my $edate = $rental->edate();
    my @programs = model($c, 'Program')->search({
        name => $name,
        sdate => $sdate,
        edate => $edate,
    });
    if (@programs) {
        my $prog_id = $programs[0]->id();
        $c->response->redirect($c->uri_for("/program/view/$prog_id"));
    }
    else {
        error($c,
            "Sorry, No parallel Program for Rental '$name'.",
            "program/error.tt2",
        );
    }
}

#
# does not exclude DCM programs nor MMI programs for a non mmi_admin.
# should it???
#
sub view_adj : Local {
    my ($self, $c, $prog_id, $dir, $section) = @_;

    my $prog = model($c, 'Program')->find($prog_id);
    my $sdate = $prog->sdate();
    my $relation = ($dir eq 'next')? '>'  : '<';
    my $ord      = ($dir eq 'next')? 'asc': 'desc';
    my @cond = ();
    if ($c->user->obj->hide_mmi()) {
        push @cond, (school_id => 1);      # only MMC
    }
    my @progs = model($c, 'Program')->search(
        {
            -or => [
                sdate => { $relation => $sdate },
                -and => [
                    sdate   => $sdate,
                    'me.id' => { $relation => $prog_id },
                ],
            ],
            @cond,
        },
        {
            rows => 1,
            order_by => "sdate $ord",
        }
    );
    if (@progs) {
        $c->response->redirect($c->uri_for("/program/view/" .
                               $progs[0]->id() . "/$section"));
    }
    else {
        # likely BOF beginning of file or EOF.
        $c->response->redirect($c->uri_for("/program/view/$prog_id/$section"));
    }
}

sub color : Local {
    my ($self, $c, $program_id) = @_;
    my $program = model($c, 'Program')->find($program_id);
    my ($r, $g, $b) = (127, 127, 127);
    if ($program->color()) {
        ($r, $g, $b) = $program->color() =~ m{\d+}g;
    }
    stash($c,
        Type     => 'Program',
        type     => 'program',
        id       => $program_id,
        name     => $program->name(),
        red      => $r,
        green    => $g,
        blue     => $b,
        color    => "$r, $g, $b",
        palette  => palette(),
        template => 'color.tt2',
    );
}

sub color_do : Local {
    my ($self, $c, $program_id) = @_;
    my $program = model($c, 'Program')->find($program_id);
    $program->update({
        color => $c->request->params->{color},
    });
    $c->response->redirect($c->uri_for("/program/view/$program_id/2"));
}

sub update_refresh : Local {
    my ($self, $c, $id) = @_;

    my $p = model($c, 'Program')->find($id);
    stash($c,
        program     => $p,
        refresh_table => refresh_table(0,
                                   $p->refresh_days(),
                                   $p->sdate_obj,
                                   $p->edate_obj + $p->extradays,
                                  ),
        template    => "program/update_refresh.tt2",
    );
}

sub update_refresh_do : Local {
    my ($self, $c, $id) = @_;

    %P = %{ $c->request->params() };
    my $p = model($c, 'Program')->find($id);
    my $ndays = $p->edate_obj - $p->sdate_obj + 1 + $p->extradays;
    my $l = '';
    for my $n (0 .. $ndays-1) {
        $l .= (exists $P{"d$n"})? "1": "0";
    }
    $p->update({
        refresh_days => $l,
    });
    if (my $r_id = $p->rental_id()) {
        my $r = model($c, 'Rental')->find($r_id);
        if ($r) {
            $r->update({
                refresh_days => $l,
            });
        }
    }
    $c->response->redirect($c->uri_for("/program/view/$id/1"));
}

sub cancel : Local {
    my ($self, $c, $id) = @_;

    my $p = model($c, 'Program')->find($id);
    if ($p->cancelled) {
        $p->update({
            cancelled => '',
        });
    }
    else {
        _check_several_things($c, $p, 'cancel') or return;
        $p->update({
            cancelled => 'yes',
        });
    }
    $c->response->redirect($c->uri_for("/program/view/$id/1"));
}

sub del_file : Local {
    my ($self, $c, $file_id) = @_;
    my $f = model($c, 'File')->find($file_id);
    unlink "/var/Reg/documents/$file_id" . '.' . $f->suffix;
    my $program_id = $f->program_id;
    my $rental_id = $f->rental_id;
    $f->delete();
    if ($program_id) {
        $c->response->redirect($c->uri_for("/program/view/$program_id/4"));
    }
    else {
        $c->response->redirect($c->uri_for("/rental/view/$rental_id/4"));
    }
}

1;
