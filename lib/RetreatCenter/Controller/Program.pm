use strict;
use warnings;
package RetreatCenter::Controller::Program;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.
use Util qw/
    leader_table
    affil_table
    slurp 
    monthyear
    expand
    expand2
    resize
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
    PR_progtable
    months_calc
    new_event_alert
    time_travel_class
    too_far
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
use Net::FTP;
use Global qw/
    %string
    @clusters
/;
use File::Copy;
use JSON;

my $export_dir = '/var/Reg/export';

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
        check_linked        => 'checked',
        check_allow_dup_regs => '',
        check_kayakalpa     => 'checked',
        check_retreat       => '',
        check_sbath         => 'checked',
        check_single        => 'checked',
        check_req_pay       => 'checked',
        check_collect_total => '',
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
            extradays    => 0,
            full_tuition => 0,
            deposit      => 100,
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
);
my %P;
my @mess;
sub _get_data {
    my ($c) = @_;

    %P = %{ $c->request->params() };
    #
    if ($P{school_id} == 1) {
        # MMC
        $P{level_id} = 1;      # course
    }
    # since unchecked boxes are not sent...
    for my $f (qw/
        req_pay
        collect_total
        allow_dup_regs
        kayakalpa
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
    my $category = model($c, 'Category')->find($P{category_id});
    if (! $category) {
        push @mess, "Unknown Category!";
    }
    else {
        my $name = $category->name();
        if ($name ne 'Normal') {
            if ($P{name} !~ m{^$name}) {
                push @mess, 'Name does not match the Category.';
            }
        }
        else {
            # what is happening here???
            # category is 'Normal' but the program name
            # might begin with another category?  yeah.
            my $cats = join '|',
                       map {
                           $_->name()        
                       }
                       model($c, 'Category')->search({
                           name => { '!=', 'Normal' },
                       })
                       ;
            if ($P{name} =~ m{^($cats)}) {
                push @mess, 'Name does not match the Category.';
            }
        }
    }
    if ($P{school_id} != 1
        && $P{name} !~ m{MMI}
    ) {
        push @mess, 'Name must have MMI in it';
    }
    if ($P{school_id} == 1
        && $P{name} =~ m{MMI}
    ) {
        push @mess, 'Name has MMI in it but the program is not sponsored by an MMI school';
    }
    # verify the level and school match okay
    my $level = model($c, 'Level')->find($P{level_id});
    if (! $level) {
        push @mess, 'Illegal Level!!';
    }
    else {
        my $lev_name = $level->name();
        if ($level->school_id && $level->school_id != $P{school_id}) {
            my $school = model($c, 'School')->find($P{school_id});
            my $sch_name = $school->name();
            # we _could_ have some Javascript to only permit
            # certain allowable options in the <select> for Level.
            push @mess, "Level '$lev_name' does not match the Sponsoring Organization '$sch_name'";
        }
        # the program name must match the level name_regex
        my $regex = $level->name_regex();
        if ($regex && $P{name} !~ m{$regex}i) {
            push @mess, "Program name '$P{name}' does not match the Level '$lev_name'";
        }
    }

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
        extradays tuition full_tuition deposit
    /) {
        if ($P{$f} !~ m{^\s*\d+\s*$}) {
            push @mess, "$readable{$f} must be a number";
        }
    }
    if ($P{extradays}) {
        if ($P{full_tuition} <= $P{tuition}) {
            push @mess, "Full Tuition must be more than normal Tuition.";
        }
    }
    else {
        $P{full_tuition} = 0;    # it has no meaning if > 0.
    }
    if ($P{footnotes} =~ m{[^\*%+]}) {
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

    if (! empty($P{max}) && $P{max} !~ m{^\s*\d+\s*$}) {
        push @mess, "Max must be an integer";
    }
    if (exists $P{glnum} && $P{glnum} !~ m{ \A [0-9A-Z]* \z }xms) {
        push @mess, "The GL Number must only contain digits and upper case letters.";
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

    my $upload     = $c->request->upload('image');
    if ($upload) {
        $P{image} = 'yes';
    }
    my $doc_upload = $c->request->upload('new_web_doc');
    my $doc_title = $P{doc_title};
    delete $P{doc_title};       # so they aren't referenced below
    delete $P{new_web_doc};

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
    # now we can create the program itself
    #
    my $p = model($c, 'Program')->create({
        image      => $upload? 'yes': '',
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
    if ($upload) {
        $upload->copy_to("root/static/images/po-$id.jpg");
        Global->init($c);
        resize('p', $id);
    }
    if ($doc_upload) {
        my ($suffix) = $doc_upload->filename =~ m{ [.] (\w+) \z }xms;
        my $pdoc = model($c, 'ProgramDoc')->create({
            program_id => $id,
            title      => $doc_title,
            suffix     => $suffix,
        });
        $doc_upload->copy_to("root/static/images/pdoc"
                           . $pdoc->id()
                           . ".$suffix");
    }
    _finalize_program_creation($c, $id);
}

sub _finalize_program_creation {
    my ($c, $id) = @_;

    my $url = $c->uri_for("/program/view/$id");

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
    $c->response->redirect($c->uri_for("/program/view/$id/1/$glnum_popup"));
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
    stash($c,
        program  => $p,
        pg_title => $p->name(),
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

    my @files = <root/static/online/*>;
    my $sdate = $p->sdate();
    my $nmonths = months_calc(date($sdate), date($p->edate()));

    my ($UNres, $res) = split /XX/, _get_cluster_groups($c, $id);

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
    my ($c, $program_id) = @_;

    my @reserved = reserved_clusters($c, $program_id, 'program');
    my %my_reserved_ids;
    my $reserved = "<tr><th align=left>Reserved</th></tr>\n";
    for my $cl (@reserved) {
        my $cid = $cl->id();
        $my_reserved_ids{$cid} = 1;
        $reserved .=
           "<tr><td>"
           . "<a href='#' onclick='UNreserve_cluster($cid); return false;'>"
           . $cl->name()
           . "</a>"
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
            .  "<a href='#' onclick='reserve_cluster($id); return false;'>"
            .  $cl->name()
            .  "</a>"
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
    $cutoff = $cutoff->as_d8();
    my @cond = ();
    if ($type eq 'long_term') {
        @cond = (
            'category.name' => 'Normal',
            'level.long_term' => 'yes',
            edate => { },       # all programs not just current.
                                # this overrides the cutoff one below
        );
    }
    else {
        @cond = (
            'category.name'   => 'Normal',
            'level.long_term' => '',
        );
        if ($hide_mmi) {
            push @cond, ('school.mmi' => '');      # only MMC no MMI
        }
    }
    stash($c,
        programs => [
            model($c, 'Program')->search(
                {
                    edate => { '>=', $cutoff },
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
    my @files = <root/static/online/*>;
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
            name => { 'like' => "${pat}%" },
        };
    }
    my @files = <root/static/online/*>;
    stash($c,
        pg_title => "Programs",
        online   => scalar(@files),
        programs => [
            model($c, 'Program')->search(
                $cond,
                { order_by => ['sdate desc', 'me.id asc'] },
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
        sbath single req_pay collect_total allow_dup_regs kayakalpa
        retreat
        economy commuting webready linked do_not_compute_costs
        not_on_calendar tub_swim waiver_needed housing_not_needed
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

    my $bank = $p->bank_account();
    stash($c,
        section     => $section,
        program     => $p,
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
        template     => "program/create_edit.tt2",
    );
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    _get_data($c);
    return if @mess;

    if ($P{prog_start} >= 1300) {
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
    if (my $upload = $c->request->upload('image')) {
        $upload->copy_to("root/static/images/po-$id.jpg");
        Global->init($c);
        resize('p', $id);
        $P{image} = 'yes';
    }
    if (my $doc_upload = $c->request->upload('new_web_doc')) {
        my ($suffix) = $doc_upload->filename =~ m{ [.] (\w+) \z }xms;
        my $pdoc = model($c, 'ProgramDoc')->create({
            program_id => $id,
            title      => $P{doc_title},
            suffix     => $suffix,
        });
        $doc_upload->copy_to("root/static/images/pdoc"
                           . $pdoc->id()
                           . ".$suffix");
    }
    delete $P{doc_title};       # so they aren't referenced below
    delete $P{new_web_doc};
    my $p = model($c, 'Program')->find($id);
    $P{max} ||= 0;
    if (   $p->sdate       ne $P{sdate}
        || $p->edate       ne $P{edate}
        || $p->extradays() != $P{extradays}
    ) {
        # cannot change dates if there are any meeting place
        # bookings in effect.   no registrations, either.
        # 
        my @bookings = model($c, 'Booking')->search({
            program_id => $id,
        });
        my @regs = model($c, 'Registration')->search({
            program_id => $id,
            -or => [
                date_start => { '!=' => $P{sdate} },
                date_end   => { '!=' => $P{edate} },
            ],
        });
        if (@bookings || @regs) {
            error($c,
                'Cannot change the dates or add extra days when there are'
                . ' meeting place bookings or outlying registrations.',
                'gen_error.tt2',
            );
            return;
        }
        $P{lunches} = '';
        $P{refresh_days} = '';
    }
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
# how about a max for a program???
# ??? obsoleted
#
sub meetingplace_update : Local {
    my ($self, $c, $id) = @_;

    my $p = model($c, 'Program')->find($id);
    my $edate = $p->edate;
    if ($p->extradays) {
        $edate += $p->extradays;
    }
    stash($c,
        program => $p,
        meetingplace_table => meetingplace_table($c,
                                  $p->max, $p->sdate,
                                  $edate,  $p->bookings(),
                              ),
        template => "program/meetingplace_update.tt2",
    );
}

# ??? obsoleted
sub meetingplace_update_do : Local {
    my ($self, $c, $program_id) = @_;

    meetingplace_book($c, 'program', $program_id);
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

    if (my @regs = $p->registrations()) {
        my $n = @regs;
        my $pl = $n == 1? '': "s";
        error($c,
            "You must first delete the $n registration$pl for this program.",
            'gen_error.tt2',
        );
        return;
    }
    if (my @bookings = $p->bookings()) {
        my $n = @bookings;
        my $pl = $n == 1? '': "s";
        error($c,
            "You must first delete the $n meeting place$pl for this program.",
            'gen_error.tt2',
        );
        return;
    }
    if (my @docs = $p->documents()) {
        my $n = @docs;
        my $pl = $n == 1? '': "s";
        error($c,
            "You must first delete the $n document$pl attached to this program.",
            'gen_error.tt2',
        );
        return;
    }
    if (my @blocks = $p->blocks()) {
        my $n = @blocks;
        my $pl = $n == 1? '': "s";
        error($c,
            "You must first delete the $n block$pl attached to this program.",
            'gen_error.tt2',
        );
        return;
    }

    # affiliation/programs
    model($c, 'AffilProgram')->search({
        p_id => $id,
    })->delete();

    # leader/programs
    model($c, 'LeaderProgram')->search({
        p_id => $id,
    })->delete();

    # exceptions
    $p->exceptions()->delete();

    # the summary
    $p->summary->delete();

    # any image
    unlink <root/static/images/p*-$id.jpg>;

    # and finally, the program itself
    $p->delete();

    $c->response->redirect($c->uri_for('/program/list'));
}

sub del_image : Local {
    my ($self, $c, $id) = @_;

    my $p = $c->stash->{program} = model($c, 'Program')->find($id);
    $p->update({
        image => '',
    });
    unlink <root/static/images/p*-$id.jpg>;
    $c->response->redirect($c->uri_for("/program/view/$id/4"));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    error($c,
        "Authorization denied!",
        "gen_error.tt2",
    );
}

sub _pub_err {
    my ($c, $msg, $chdir) = @_;

    chdir ".." if $chdir;
    stash($c,
        mess     => $msg,
        template => "program/pub_error.tt2",
    );
    return;
}

sub publish : Local {
    my ($self, $c) = @_;

    # clear the arena
    system("rm -rf gen_files; mkdir gen_files; "
         . "mkdir gen_files/pics; mkdir gen_files/docs");

    # and make sure we have initialized %string.
    Global->init($c);

    #
    # get all the future programs destined for the web into an array
    # sorted by start date and then end date.
    #
    my @programs = RetreatCenterDB::Program->future_programs($c);

    # ensure that all of these programs have at least one affiliation set
    #
    for my $pr (@programs) {
        my @affils = $pr->affils();
        unless (@affils) {
            error($c,
                "Program " . $pr->name . " has no affiliations!",
                "program/error.tt2",
            );
            return;
        }
    }

    gen_month_calendars($c, \@programs);
    gen_progtable(\@programs);

    # 
    # generate each of the program pages
    # MMI Standalone courses do not need a program page.
    #
    # a side effect will be to copy the pictures of
    # the leaders or the program picture to the holding area.
    # (see RetreatCenterDB::Program->picture)
    #
    # the docs, if any, we copy ourselves here.
    #
    my @unlinked;
    my $tt = Template->new();
    PROGRAM:
    for my $p (@programs) {
        next PROGRAM if $p->school->mmi();     # stand alone MMI courses
        my $fname = $p->fname();
        my $copy = $p->template_src();
        $tt->process(
            \$copy,
            { program => $p },
            "gen_files/$fname",
        ) or die "error in processing template: "
             . $tt->error();
        for my $d ($p->documents) {
            my $pdoc = "pdoc" . $d->id . '.' . $d->suffix;
            copy("root/static/images/$pdoc", "gen_files/docs/$pdoc");
        }
        if (! $p->linked) {
            push @unlinked, $p;
        }
    }

    #
    # generate the program and rental calendars.
    # programs (MMC and MMI standalone courses) appear only on the program calendar.
    # rentals appear only on the rental calendar.
    # Unlinked MMC programs appear on neither.
    #
    # It's okay to require that MMI standalone courses have linked checked.
    # Yes?
    #
    my $rentallist = '';
    my $programlist = '';

    my $progRow   = slurp "progRow";
    my $mmiRow    = slurp "mmiRow";
    my $rentalRow = slurp "rentalRow";

    my $cur_rental_month = 0;
    my $cur_rental_year = 0;
    my $cur_prog_month = 0;
    my $cur_prog_year = 0;
    my @rentals  = RetreatCenterDB::Rental->future_rentals($c);
    for my $e (sort {
                   $a->sdate <=> $b->sdate
                   or
                   $a->edate <=> $b->edate
               }
               grep {
                   $_->linked && ! $_->cancelled
               }
               @programs,
               @rentals
    ) {
        my $rental = (ref($e) =~ m{Rental$});
        my $for_rental_calendar = $rental;

        my $sdate = $e->sdate_obj;
        my $smonth = $sdate->month;
        my $syear = $sdate->year;
        my $my = monthyear($sdate);

        if ($for_rental_calendar) {
            if ($cur_rental_month != $smonth || $cur_rental_year != $syear) {
                $rentallist
                    .= "<tr><td class='rental_my_row' colspan=2>$my</td></tr>\n";
                $cur_rental_month = $smonth;
                $cur_rental_year = $syear;
            }
            my $s;
            $tt->process(
                \$rentalRow,
                { rental => $e },
                \$s,
            ) or die "error in processing template: "
                 . $tt->error();
            $rentallist .= $s;
        }
        else {
            if ($cur_prog_month != $smonth || $cur_prog_year != $syear) {
                $programlist
                    .= "<tr><td class='prog_my_row' colspan=2>$my</td></tr>\n";
                $cur_prog_month = $smonth;
                $cur_prog_year = $syear;
            }
            my $s;
            $tt->process(
                $e->level->public()? \$mmiRow: \$progRow,
                { program => $e },
                \$s,
            ) or die "error in processing template: "
                     . $tt->error();
            $programlist .= $s;
        }
    }
    #
    # we have gathered all the info into rentallist and programlist.
    # now to insert them in the templates and output
    # the .html files for the programs and rentals pages.
    #
    my $rental_template = slurp "rentals";
    $tt->process(
        \$rental_template,
        { rentallist => $rentallist },
        "gen_files/rentals.html",
    ) or die "error in processing template: "
             . $tt->error();
    my $program_template = slurp "programs";
    $tt->process(
        \$program_template,
        { programlist => $programlist },
        "gen_files/programs.html",
    ) or die "error in processing template: "
             . $tt->error();

    #
    # schmush around the unlinked programs
    #
    for my $ulp (@unlinked) {
        my $dir = $ulp->unlinked_dir;
        mkdir "gen_files/$dir";
        mkdir "gen_files/$dir/pics";
        rename "gen_files/" . $ulp->fname,
               "gen_files/$dir/index.html";
        copy "gen_files/progtable",
             "gen_files/$dir/progtable";
        # now for the pictures and the associated html files...
        my $src = slurp("gen_files/$dir/index.html");
        my @img = $src =~ m{pics/(.*?(?:jpg|gif))}g;
        for my $im (@img) {
            copy "gen_files/pics/$im",   # not move.
                 "gen_files/$dir/pics/$im";
                                        # it is POSSIBLE for a leader
                                        # to lead both a linked and an
                                        # unlinked program.
            my $pic = $im;
            $pic =~ s{gen_files/pics/}{};
            $pic =~ s{th}{b};
            copy "gen_files/pics/$pic",   # not move.
                 "gen_files/$dir/pics/$pic";
            copy "gen_files/$pic.html",
                 "gen_files/$dir/$pic.html";
        }
    }
    #
    # remove the temporary calX.html files
    #
    unlink <root/static/templates/web/cal?.html>;

    #
    # finally, ftp all generated pages to www.mountmadonna.org
    # or whereever Global says, that is...
    #
    my $ftp = Net::FTP->new($string{ftp_site}, Passive => $string{ftp_passive})
        or return _pub_err($c, "cannot connect to $string{ftp_site}");
    $ftp->login($string{ftp_login}, $string{ftp_password})
        or return _pub_err($c, "cannot login: " . $ftp->message);
    $ftp->cwd($string{ftp_dir})
        or return _pub_err($c, "cannot cwd: " . $ftp->message);
    $ftp->cwd($string{ftp_dir2})
        or return _pub_err($c, "cannot cwd: " . $ftp->message);
    for my $f ($ftp->ls()) {
        $ftp->delete($f) if $f ne 'pics';
    }
    $ftp->ascii();
    # dangerous to chdir - in case we die...
    # need to restore current directory.
    # die does not really die.  the server keeps running somehow.
    chdir "gen_files";
    FILE:
    for my $f (<*>) {
        if (-d $f) {
            next FILE if $f eq 'pics' || $f eq 'docs';
            # an unlinked program directory
            $ftp->mkdir("../$f");
            for my $hf (<$f/*.html>) {
                $ftp->put($hf, "../$hf")
                    or return _pub_err($c, "cannot put $hf to ../$hf", 1);
            }
            $ftp->binary();
            $ftp->mkdir("../$f/pics");
            for my $p (<$f/pics/*>) {
                $ftp->put($p, "../$p")
                    or return _pub_err($c, "cannot put $p to ../$p", 1);
            }
            $ftp->mkdir("../$f/docs");
            for my $d (<$f/docs/*>) {
                $ftp->put($d, "../$d")
                    or return _pub_err($c, "cannot put $d to ../$d", 1);
            }
            $ftp->ascii();
            $ftp->put("$f/progtable", "../$f/progtable")
                    or return _pub_err($c, "cannot put $f/progtable to ../$f/progtable", 1);
        }
        else {
            $ftp->put($f)
                or return _pub_err($c, "cannot put $f: " . $ftp->message, 1);
        }
    }
    $ftp->quit();
    chdir "..";     # important!
    stash($c,
        ftp_dir2 => $string{ftp_dir2},
        unlinked => \@unlinked,
        template => "program/published.tt2",
    );
}

# Obsolete!
sub mmi_publish : Local {
    my ($self, $c) = @_;

    # clear the arena
    system("rm -rf gen_files; mkdir gen_files");

    # and make sure we have initialized %string.
    Global->init($c);

    # fill the global @programs with all future 
    # webready MMI public courses ordered by start date.
    #
    my @programs = model($c, 'Program')->search(
                       {
                           sdate  => { '>=', tt_today($c)->as_d8() },
                           'school.mmi' => 'yes',      # not MMC
                           'level.public' => 'yes', # MMI public course
                           webready => 'yes',
                       },
                       {
                           order_by => 'sdate',
                           join     => [qw/ school level /],
                       },
                   );
    gen_progtable(\@programs);
    # send to mountmadonnainstitute.org/courses
    my $ftp = Net::FTP->new($string{ftp_mmi_site},
                            Passive => $string{ftp_mmi_passive})
        or return _pub_err($c, "cannot connect to ...");
    $ftp->login($string{ftp_mmi_login}, $string{ftp_mmi_password})
        or return _pub_err($c, "cannot login: " . $ftp->message);
    $ftp->cwd($string{ftp_mmi_dir})
        or return _pub_err($c, "cannot cwd " . $ftp->message);
    $ftp->put('gen_files/progtable');
    $ftp->quit();
    stash($c,
        programs => \@programs,
        template => "program/mmi_published.tt2",
    );
}

# Obsolete!
sub publish_pics : Local {
    my ($self, $c) = @_;

    Global->init($c);
    my $ftp = Net::FTP->new($string{ftp_site}, Passive => $string{ftp_passive})
        or return _pub_err($c, "cannot connect to ...");
    $ftp->login($string{ftp_login}, $string{ftp_password})
        or return _pub_err($c, "cannot login: " . $ftp->message);
    #
    # this assumes pics/ is there...
    #
    $ftp->cwd("$string{ftp_dir}/$string{ftp_dir2}/pics")
        or return _pub_err($c, "cannot cwd " . $ftp->message);
    for my $f ($ftp->ls()) {
        $ftp->delete($f);
    }
    $ftp->binary();
    chdir "gen_files/pics";
    PIC:
    for my $f (<*.jpg>) {
        if ($f =~ m{^[lp]b}) {      # skip the big ones for now
            next PIC;
        }
        if (! $ftp->put($f)) {
            chdir "../..";
            return _pub_err($c, "cannot put $f", 1);
        }
    }
    #
    # this assumes docs/ is there...
    #
    $ftp->cwd("../docs")
        or return _pub_err($c, "cannot cwd " . $ftp->message);
    for my $f ($ftp->ls()) {
        $ftp->delete($f);
    }
    $ftp->binary();
    chdir "../docs";
    for my $f (<*>) {
        if (! $ftp->put($f)) {
            chdir "../..";
            return _pub_err($c, "cannot put $f", 1);
        }
    }
    $ftp->quit();
    chdir "../..";
    my @unlinked = grep { ! $_->linked }
                   RetreatCenterDB::Program->future_programs($c);
    stash($c,
        unlinked => \@unlinked,
        pics     => 1,
        ftp_dir2 => $string{ftp_dir2},
        template => "program/published.tt2",
    );
}

# Obsolete!
#
# go through the programs in ascending date order
# and create the monthly calendar files calX.html
# where X is the month number.
#
# skip the unlinked ones
# treat the MMI ones specially
#
# clear them first? or after using them???
#
sub gen_month_calendars {
    my ($c, $programs_ref) = @_;
    my $cur_ym = 0;
    my $mmi_link = "</span><span class='external_link_icon'>"
                 . "<i class='fa fa-external-link'></i> MMI</span>";
    my $cal;
    for my $p (grep { $_->linked && ! $_->cancelled } @$programs_ref) {
        my $ym = $p->sdate_obj->format("%Y%m");
        if ($ym != $cur_ym) {
            # finish the prior calendar file, if any
            if ($cur_ym) {
                print {$cal} "</table>\n";
                close $cal;
                undef $cal;
            }
            # start a new calendar file
            $cur_ym = $ym;
            undef $cal;
            open $cal, ">", "root/static/templates/web/cal$ym.html"
                or die "cannot create cal$ym.html: $!\n";
            my $my = monthyear($p->sdate_obj);
            print {$cal} <<EOH;
<table class='caltable'>
<tr><td class="monthyear" colSpan=2>$my</td></tr>
EOH
        }
        my $title = "";
        my $class = "";
        if ($p->school->mmi) {
            $title .= "<a href='http://" . $p->url . "'>";
            $title .= $p->title;
            $title .= "</a>";
            $title .= $mmi_link;
            $title .= "<br><span class='subtitle'>" . $p->subtitle . "</span>";
            $class = "mmi_event";
        }
        else {
            $title .= "<a href='" . $p->fname . "'>";
            $title .= $p->title1;
            $title .= "</a>";
            $title .= "<br><span class='subtitle'>" . $p->title2 . "</span>";
            $class = "title";
        }
        # the program info itself
        print {$cal} "<tr>\n<td class='dates_tr'>",
                     $p->dates_tr, "</td>",
                     "<td class='$class'>",
                     $title,
                     "</td></tr>";
    }
    # finish the prior calendar file, if any
    if ($cur_ym) {
        print {$cal} "</table>\n";
        close $cal;
    }
}

# ??? Use Data::Dumper?
sub _prt_data {
    my ($progt, $p, $id) = @_;
    my $PR = $p->name() =~ m{personal\s+retreat}i;
    my $ndays = $p->edate_obj - $p->sdate_obj;
    my $fulldays = $ndays + $p->extradays;
    my $canpol = esc_dquote($p->canpol->policy());
    print {$progt} $id, <<"EOD";
=> {
    ndays    => $ndays,
    fulldays => $fulldays,
    canpol   => "$canpol",
EOD
    # plink - be careful with unlinked programs
    if ($p->linked) {
        print {$progt} "    plink    => 'http://www.mountmadonna.org/live/"
               . $p->fname()
               . "',\n"
               ;
    }
    else {
        print {$progt} "    plink    => 'http://www.mountmadonna.org/"
                     . $p->unlinked_dir     # index.html is implied
                     . "',\n"
                     ;
    }
    for my $f (qw/
        name
        title
        dates
        sdate
        edate
        leader_names
        footnotes
        deposit
        collect_total
        req_pay
        do_not_compute_costs
        dncc_why
        percent_tuition
        tuition
        reg_start
        reg_end
        prog_start
        prog_end
        waiver_needed
        housing_not_needed
    /) {
        print {$progt} qq!    $f => "!,
                       esc_dquote($p->$f()),
                       qq!",\n!
                       ;
    }
    my $month_day     = $p->sdate_obj->format("%m%d");
    my $housecost = $p->housecost();

    for my $t (reverse housing_types(1)) {
        next if $t eq 'commuting'   && !$p->commuting;
        next if $t eq 'economy'     && !$p->economy;
        next if $t eq 'single_bath' && !$p->sbath;
        next if $t eq 'single'      && !$p->single;
        next if $t eq 'center_tent'
            && !($PR
                 || $p->name =~ m{tnt}i
                 || ($string{center_tent_start} <= $month_day
                     && $month_day <= $string{center_tent_end}));
        next if $PR && $t =~ m{triple|dormitory};
        my $fees = $PR? $housecost->$t()
                  :     $p->fees(0, $t);
        next if $fees == 0;    # another way to eliminate a housing option 
        print {$progt} "    'basic $t' => $fees,\n";
        if ($p->extradays()) {
            print {$progt} "    'full $t' => ", $p->fees(1, $t), ",\n";
        }
    }
    print {$progt} "    type => '", $housecost->type(), "',\n";

    # pictures
    #
    my @leaders = $p->leaders();
    my $nleaders = @leaders;

    # images - be careful with unlinked programs
    my ($pic1, $pic2) = ('', '');
    my $url = $p->linked? "http://www.mountmadonna.org/live/pics"
             :            ("http://www.mountmadonna.org/" . $p->unlinked_dir . "/pics")
             ;
    if ($nleaders >= 1 && $leaders[0]->image) {
        $pic1 = "$url/lth-" . $leaders[0]->id() . ".jpg";
    }
    if ($nleaders >= 2 && $leaders[1]->image) {
        $pic2 = "$url/lth-" . $leaders[1]->id() . ".jpg";
    }
    if ($pic2 and ! $pic1) {
        $pic1 = $pic2;
        $pic2 = '';
    }
    if ($p->image()) {  # program pic, if present, overrides the leader pics
        $pic1 = "$url/pth-" . $p->id() . ".jpg";
        $pic2 = '';
    }
    print {$progt} "    image1 => '$pic1',\n";
    print {$progt} "    image2 => '$pic2',\n";

    # finalization
    #
    print {$progt} "},\n";
}

#
# generate the progtable for online registration
#
sub gen_progtable {
    my ($programs_ref) = @_;
    open my $progt, ">", "/var/Reg/export/progtable"
        or die "cannot create progtable: $!\n";
    print {$progt} "{\n";       # the enclosing anonymous hash ref
    for my $p (grep { ! $_->cancelled } @$programs_ref) {
        _prt_data($progt, $p, $p->id());
    }
    print {$progt} "};\n";
    close $progt;
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

    # the image takes some special handling
    # in the initial duplication dialog we want to indicate
    # what the image _will_ be if we would take the image
    # from the original program - but that image (the dup'ed one)
    # does not yet exist.   We may abort the duplication process,
    # we may upload a different image for the dup'ed program.
    # if we want to not have an image at all in the dup'ed program
    # we'll need to accept the old when creating the dup
    # and THEN delete it.
    if ($orig_p->image()) {
        stash($c,
            dup_image => $orig_p->image_file(),
        );
    }

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
        image   => '',      # not yet
        rental_id => 0,
        webready => 0,
    });
    for my $w (qw/
        sbath single req_pay collect_total allow_dup_regs kayakalpa
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
    my $doc_upload = $c->request->upload('new_web_doc');
    my $doc_title = $P{doc_title};
    delete $P{doc_title};       # so they aren't referenced below
    delete $P{new_web_doc};
    # documents from the original program are not copied forward.
    # hope this is okay.

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

    # the image takes special handling
    # if a new one is provided, take that.
    # otherwise use the old one, if any.
    #
    my $upload = $c->request->upload('image');

    # now we can create the new dup'ed program
    my $new_p = model($c, 'Program')->create({
        %P,     # this comes first so summary_id can override
        summary_id => $sum->id,
        image      => ($upload || $old_prog->image())? 'yes': '',
        program_created => tt_today($c)->as_d8(),
        created_by => $c->user->obj->id,
        cancelled => '',
    });

    my $new_id = $new_p->id();

    # mess with the new image, if any.
    if ($upload) {
        $upload->copy_to("root/static/images/po-$new_id.jpg");
        Global->init($c);
        resize('p', $new_id);
    }
    elsif ($new_p->image()) {
        # complicated! wake up.
        my $path = "root/static/images";
        my $suf = (-f "$path/po-$old_id.jpg")? "jpg": "gif";
        for my $let (qw/ b o th /) {
            copy "$path/p$let-$old_id.$suf",
                 "$path/p$let-$new_id.$suf";
        }
    }
    if ($doc_upload) {
        my ($suffix) = $doc_upload->filename =~ m{ [.] (\w+) \z }xms;
        my $pdoc = model($c, 'ProgramDoc')->create({
            program_id => $new_id,
            title      => $doc_title,
            suffix     => $suffix,
        });
        $doc_upload->copy_to("root/static/images/pdoc"
                           . $pdoc->id()
                           . ".$suffix");
    }
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
    $c->res->output(_get_cluster_groups($c, $program_id));
}

# AJAX call to UNreserve a cluster
sub UNreserve_cluster : Local {
    my ($self, $c, $program_id, $cluster_id) = @_;

    model($c, 'ProgramCluster')->search({
        program_id => $program_id,
        cluster_id => $cluster_id,
    })->delete();
    $c->res->output(_get_cluster_groups($c, $program_id));
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

sub publishPR : Local {
    my ($self, $c, $id) = @_;

    Global->init($c);
    stash($c,
        id       => $id,
        discount => $string{disc_pr},
        start    => date($string{disc_pr_start}),
        end      => date($string{disc_pr_end}),
        getaway  => $string{personal_template} eq 'personal_getaway'?
                        'getaway': 'plain',
        template => "program/publish_pr.tt2",
    );
}

#
# get the form values and then
# invoke the publish_pr program usually invoked
# automatically on the 1st of the month at 1 am.
#
# we force the start date to the first of the month
# and the end date to the last day of the month.
#
sub publishPR_do : Local {
    my ($self, $c, $id) = @_;

    my $pct = trim($c->request->params->{discount});
    if ($pct !~ m{\A \d+ \z}xms) {
        error($c,
            "Illegal discount percentage",
            "gen_error.tt2",
        );
        return;
    }
    my $start = date($c->request->params->{start});
    if (! $start) {
        error($c,
            "Invalid start date",
            "gen_error.tt2",
        );
        return;
    }
    $start = ymd($start->year, $start->month, 1);
    my $end = date($c->request->params->{end});
    if (! $end) {
        error($c,
            "Invalid end date",
            "gen_error.tt2",
        );
        return;
    }
    my $y = $end->year;
    my $m = $end->month;
    $end = ymd($y, $m, days_in_month($y, $m));

    if ($start >= $end) {
        error($c,
            "Start is greater than End",
            "gen_error.tt2",
        );
        return;
    }

    #
    # put the values in the database table and in the %string hash.
    #
    model($c, 'String')->find('disc_pr')->update({
        value => $pct,
    });
    $string{disc_pr} = $pct;

    my $d8 = $start->as_d8();
    model($c, 'String')->find('disc_pr_start')->update({
        value => $d8,
    });
    $string{disc_pr_start} = $d8;

    $d8 = $end->as_d8();
    model($c, 'String')->find('disc_pr_end')->update({
        value => $d8,
    });
    $string{disc_pr_end} = $d8;

    my $value = ($c->request->params->{publish_type} eq 'getaway')?
        'personal_getaway': 'personal';
    model($c, 'String')->find('personal_template')->update({
        value => $value,
    });
    $string{personal_template} = $value;

    # now send everything up to mountmadonna.org
    system("publish_pr");

    $c->response->redirect($c->uri_for("/program/view/$id"));
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
        if (my @regs = grep { ! $_->cancelled } $p->registrations) {
            error($c,
                "Cannot cancel a program with active registrations.  Cancel them first.",
                "gen_error.tt2",
            );
            return;
        }
        if (my @bookings = $p->bookings) {
            error($c,
                "Cannot cancel a program with meeting place bookings.",
                "gen_error.tt2",
            );
            return;
        }
        if (my @blocks = $p->blocks) {
            error($c,
                "Cannot cancel a program with blocks.",
                "gen_error.tt2",
            );
            return;
        }
        if (my @res_clust = reserved_clusters($c, $id, 'Program')) {
            error($c,
                "Cannot cancel a program with reserved clusters.",
                "gen_error.tt2",
            );
            return;
        }
        $p->update({
            cancelled => 'yes',
        });
    }
    $c->response->redirect($c->uri_for("/program/view/$id/1"));
}

sub del_doc : Local {
    my ($self, $c, $program_id, $doc_id) = @_;

    my ($prog_doc) = model($c, 'ProgramDoc')->search({
        program_id => $program_id,
        id         => $doc_id,
    });
    if ($prog_doc) {
        $prog_doc->delete();
        unlink "root/static/images/pdoc$doc_id." . $prog_doc->suffix();
    }
    else {
        error($c,
            "Could not find the document you requested.",
            "gen_error.tt2",
        );
        return;
    }
    $c->response->redirect($c->uri_for("/program/view/$program_id/4"));
}

#
# for the new web site where the generation of the program pages
# happens in another way.
#
sub export : Local {
    my ($self, $c) = @_;

    # clear the arena
    system("/bin/rm -rf $export_dir/*");
    mkdir "$export_dir/pics";
    mkdir "$export_dir/docs";
    mkdir "$export_dir/mmi_pics";
    mkdir "$export_dir/mmi_docs";
    mkdir "$export_dir/pr";

    # and make sure we have initialized %string.
    Global->init($c);

    #
    # get all the future programs destined for the web into an array
    # sorted by start date and then end date.
    #
    # not sure why future_programs includes cancelled ones...
    #
    my @programs = grep { ! $_->cancelled }
                   RetreatCenterDB::Program->future_programs($c);

    # ensure that all of these programs have at least one affiliation set
    #
    for my $pr (@programs) {
        my @affils = $pr->affils();
        unless (@affils) {
            error($c,
                "Program " . $pr->name . " has no affiliations!",
                "program/error.tt2",
            );
            return;
        }
    }
    gen_progtable(\@programs);      # writes to $export_dir/progtable
    # documents and pictures
    for my $p (@programs) {
        my $mmi = $p->school->mmi();
        for my $d ($p->documents) {
            my $pdoc = "pdoc" . $d->id . '.' . $d->suffix;
            copy("root/static/images/$pdoc",
                 $export_dir . ($mmi? "mmi_docs": "docs") . "/$pdoc");
        }
        my $pic_html = $p->picture();   # a side effect of this is to
                                        # copy pics to gen_files/pics
                                        #           or gen_files/mmi_pics.
                                        # we do not need the returned $pic_html
    }
    my $fmt = '%Y-%m-%d';
    my (@export_programs, @export_mmi_programs, @export_unlinked_programs);
    for my $p (@programs) {
        my $mmi = $p->school->mmi();
        my $pic_dir = $mmi? "mmi_pics": "pics";
        my $doc_dir = $mmi? "mmi_docs": "docs";
        my @leaders;
        for my $l ($p->leaders()) {
            push @leaders, {
                map({ $_ => $l->$_ } qw/
                    id
                    public_email
                    url
                    biography
                    l_order
                /),
                first => $l->person->first,
                last => $l->person->last,
                image => ($l->image? ("$pic_dir/lth-" . $l->id . ".jpg"): ""),
            },
        }
        my @docs;
        for my $d ($p->documents()) {
            push @docs, {
                title    => $d->title,
                filename => "$doc_dir/pdoc" . $d->id . '.' . $d->suffix
            };
        }
        my $fee_table = $p->fee_table();
        my %extracted_fee_table = _extract_fee_table($fee_table);
        my $href = {
            map({ $_ => $p->$_ } qw/
                id

                extradays
                dates

                title1
                title2

                leader_names
                picture
                webdesc
                leader_bio
                url
                weburl
                footnotes
                deposit
                cancellation_policy
                reg_start
                reg_end
                prog_start
                prog_end
                housing_not_needed
                
                linked
                image

                do_not_compute_costs
                dncc_why
            /),
            sdate => $p->sdate_obj->format($fmt),
            edate => $p->edate_obj->format($fmt),
            footnotes_long => $p->long_footnotes,
            %extracted_fee_table,
            str_reg_start  => $p->reg_start_obj->ampm,
            str_reg_end    => $p->reg_end_obj->ampm,
            str_prog_start => $p->prog_start_obj->ampm,
            str_prog_end   => $p->prog_end_obj->ampm,
            mmi => $mmi,
            leaders => \@leaders,
            documents => \@docs,
        };
        if ($href->{image} eq 'yes') {
            $href->{image} = "$pic_dir/pth" . $p->id() . ".jpg";
        }
        if (! $href->{linked}) {
            push @export_unlinked_programs, $href;
        }
        else {
            push @export_programs, $href;   # includes mmi programs
        }
        if ($mmi) {
            push @export_mmi_programs, $href;
        }
    }
    _json_put(\@export_programs, 'programs.json');
    _json_put(\@export_unlinked_programs, 'unlinked_programs.json');
    _json_put(\@export_mmi_programs, 'mmi_programs.json');
    my $footnote_href = {
        'footnotes_*'   => $string{'*'},
        'footnotes_**'  => $string{'**'},
        'footnotes_+'   => $string{'+'},
        'footnotes_%'   => $string{'%'},
    };
    _json_put($footnote_href, 'footnotes.json');

    my @rentals  = grep {
                       $_->linked && ! $_->cancelled
                   }
                   RetreatCenterDB::Rental->future_rentals($c);
    my @export_rentals;
    for my $r (@rentals) {
        push @export_rentals, {
            map({ $_ => $r->$_ } qw/
                id
                dates_tr2
                title
                subtitle
                title1
                title2
                webdesc
                phone
                phone_str
                url
                weburl
                email
                email_str
                image
            /),
            sdate => $r->sdate_obj->format($fmt),
            edate => $r->edate_obj->format($fmt),
        };
        if ($r->image()) {
            copy $r->image_file(), "$export_dir/pics"
              or die "no copy of " . $r->image_file() . ": $!\n";
        }
    }
    _json_put(\@export_rentals, 'rentals.json');

    # noPR events
    my (@events) = model($c, 'Event')->search(
        {
            name  => { 'like' => 'No PR%' },
            edate => { '>='   => today()->as_d8() },
        },
        {
            order_by => 'sdate',
        }
    );
    my @no_prs;
    for my $ev (@events) {
        push @no_prs, {
            start => $ev->sdate(),
            end   => $ev->edate(),
            indoors => (($ev->name =~ m{indoors}xmsi)? "yes": ""),
        };
    }

    # now for personal retreats
    # we generate pr/pr.json and pr/progtable
    my $pr_ref = {
        disc_pr       => $string{disc_pr},
        disc_pr_start => date($string{disc_pr_start})->format($fmt),
        disc_pr_end   => date($string{disc_pr_end})->format($fmt),
        pr_template   => $string{personal_template},
                   # personal_getaway / personal
        noPR_dates    => \@no_prs,
        fee_table_headings => [
            'Housing Type',
            'Cost',
        ],

    };
    my ($currHC, $nextHC, $change_date)
        = PR_progtable($c, "$export_dir/pr/progtable");
    TYPE:
    for my $type (reverse housing_types(1)) {
        next TYPE if $type =~ m{^economy|dormitory|triple$};
        push @{$pr_ref->{curr_fee_table_rows}}, [
            $string{"long_$type"}, 
            $currHC->$type,
        ];
    }
    if ($nextHC) {
        # this IS optional - there may be no change in sight
        $pr_ref->{on_and_before} = date($change_date)->prev->format($fmt);
        $pr_ref->{on_and_after}  = date($change_date)->format($fmt);
        TYPE:
        for my $type (reverse housing_types(1)) {
            next TYPE if $type =~ m{^economy|dormitory|triple$};
            push @{$pr_ref->{next_fee_table_rows}}, [
                $string{"long_$type"},
                $nextHC->$type,
            ];
        }
    }
    _json_put($pr_ref, 'pr/pr.json');
    copy 'root/static/README', $export_dir;

    # tar it up
    system("cd $export_dir; /bin/tar czf /tmp/exported_reg_data.tgz .");

    # send it off
    system("send_export");
    stash($c,
        ftp_export_site => $string{ftp_export_site},
        template    => "program/exported.tt2",
    );
}

sub _extract_fee_table {
    my ($html) = @_;
    my %hash;
    my @th = $html =~ m{<th [^>]*>(.*?)</th>}xmsg;
    if (! @th) {
        return %hash;
    }
    my $top = shift @th;
    if ($th[0] !~ m{Housing}xms) {
        # an extra row(s) for spacing??
        my $toss = shift @th;
    }
    $top =~ s{</?center>}{}xmsg;
    $top =~ s{Cost[ ]Per[ ]Person<br>}{}xms;    # per Shantam's request
    $hash{fee_table_caption} = $top;
    $hash{fee_table_headings} = \@th;
    my $n = @th;    # number of columns per row
    my @td = $html =~ m{<td [^>]*>(.*?)</td>}xmsg;
    my @rows;
    while (my @one_row = splice(@td, 0, $n)) {
        push @rows, \@one_row;
    }
    $hash{fee_table_rows} = \@rows;
    return %hash;
}

my $json = JSON->new->utf8->pretty->canonical;
sub _json_put {
    my ($ref, $fname) = @_;
    open my $out, '>', "$export_dir/$fname"
        or die "no $export_dir/$fname!!\n";
    print {$out} $json->encode($ref);
    close $out;
}

1;
