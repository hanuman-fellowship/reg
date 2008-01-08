use strict;
use warnings;
package RetreatCenter::Controller::Program;
use base 'Catalyst::Controller';

use Util qw/
    leader_table
    affil_table
    slurp 
    monthyear
    expand
    resize
    housing_types
/;

use Date::Simple qw/date/;
use Net::FTP;
use Lookup;
use File::Copy;

use lib '../../';       # so you can do a perl -c here.

my %sys_template = map { $_ => 1 } qw/
    progRow
    e_progRow
    e_rentalRow
    events
    popup
    programs
/;

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('list');
}

sub create : Local {
    my ($self, $c) = @_;

    # set defaults
    $c->stash->{check_kayakalpa}     = "checked";
    $c->stash->{check_retreat}       = "";
    $c->stash->{check_sbath}         = "checked";
    $c->stash->{check_quad}          = "";
    $c->stash->{check_collect_total} = "";
    $c->stash->{check_economy}       = "";
    $c->stash->{check_webready}      = "checked";
    $c->stash->{check_linked}        = "checked";
    $c->stash->{program_leaders}     = [];
    $c->stash->{program_affils}      = [];
    $c->stash->{program}             = {
        tuition      => 0,
        extradays    => 0,
        full_tuition => 0,
        deposit      => 100,
        canpol       => { name => "MMC" },      # a clever way to set default!
        housecost    => { name => "Default" },  # fake an object!
        ptemplate    => 'template',
    };
    $c->stash->{canpol_opts} = [ $c->model("RetreatCenterDB::CanPol")->search(
        undef,
        { order_by => 'name' },
    ) ];
    $c->stash->{housecost_opts} =
        [ $c->model("RetreatCenterDB::HouseCost")->search(
            undef,
            { order_by => 'name' },
        ) ];
    $c->stash->{template_opts} = [
        grep { ! $sys_template{$_} }
        map { s{^.*templates/(.*)[.]html$}{$1}; $_ }
        <root/static/templates/*.html>
    ];
    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "program/create_edit.tt2";
}

sub create_do : Local {
    my ($self, $c) = @_;

    # dates are either blank or converted to d8 format
    my @mess;
    for my $d (qw/ sdate edate /) {
        my $fld = $c->request->params->{$d};
        if (! $fld =~ /\S/) {
            push @mess, "missing date field";
            next;
        }
        my $dt = date($fld);
        if ($fld && ! $dt) {
            # tell them which date field is wrong???
            push @mess, "Invalid date: $fld";
            next;
        }
        $c->request->params->{$d} = $dt? $dt->as_d8()
                                   :     "";
    }
    if (!@mess && $c->request->params->{sdate}
                  > 
                  $c->request->params->{edate}
    ) {
        push @mess, "end date must be after the start date";
    }
    if (! $c->request->params->{title} =~ /\S/) {
        push @mess, "title cannot be blank";
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "program/error.tt2";
        return;
    }

    my %hash;
    for my $w (qw/
        name title subtitle glnum housecost_id
        retreat sdate edate tuition confnote
        url webdesc brdesc webready
        kayakalpa canpol_id extradays full_tuition deposit
        collect_total linked ptemplate sbath quad
        economy footnotes
        school level
    /) {
        $hash{$w} = $c->request->params->{$w};
    }
    $hash{url} =~ s{^\s*http://}{};
    my $upload = $c->request->upload('image');
    my $p = $c->model("RetreatCenterDB::Program")->create({
        image => $upload? "yes": "",
        %hash,
    });
    my $id = $p->id();
    if ($upload) {
        $upload->copy_to("root/static/images/po-$id.jpg");
        Lookup->init($c);
        resize('p', $id);
    }
    $c->response->redirect($c->uri_for("/program/view/$id"));
}

sub view : Local {
    my ($self, $c, $id) = @_;

    my $p = $c->stash->{program}
        = $c->model("RetreatCenterDB::Program")->find($id);
    for my $w (qw/ sdate edate /) {
        $c->stash->{$w} = date($p->$w) || "";
    }
    for my $w (qw/ webdesc brdesc confnote /) {
        my $s = $p->$w();
        $s =~ s{\r?\n}{<br>\n}g if $s;
        $c->stash->{$w} = $s;
    }
    my $l = join "<br>\n",
                 map  {
                    "<a href='/leader/view/" . $_->id() . "'>"
                     . $_->person->last() . ", " . $_->person->first()
                     . "</a>"
                 }
                 sort {
                     $a->person->last  cmp $b->person->last or
                     $a->person->first cmp $b->person->first
                 }
                 $p->leaders();
    $l .= "<br>" if $l;
    $c->stash->{leaders} = $l;

    my $a = join "<br>\n",
                 map { $_->descrip() }
                 $p->affils();
    $a .= "<br>" if $a;
    $c->stash->{affils} = $a;

    $c->stash->{template} = "program/view.tt2";
}

sub list : Local {
    my ($self, $c) = @_;

    $c->stash->{programs} = [
        $c->model('RetreatCenterDB::Program')->search(
            undef,
            { order_by => 'name' },
        )
    ];
    $c->stash->{template} = "program/list.tt2";
}

sub listdate : Local {
    my ($self, $c) = @_;

    $c->stash->{programs} = [
        $c->model('RetreatCenterDB::Program')->search(
            undef,
            { order_by => 'sdate' },
        )
    ];
    $c->stash->{template} = "program/list.tt2";
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $p = $c->model('RetreatCenterDB::Program')->find($id);
    $c->stash->{program} = $p;
    for my $w (qw/
        sbath collect_total kayakalpa retreat
        economy webready quad linked
    /) {
        $c->stash->{"check_$w"}  = ($p->$w)? "checked": "";
    }
    for my $w (qw/ sdate edate /) {
        $c->stash->{$w} = date($p->$w) || "";
    }

    # get all cancellation policies
    $c->stash->{canpol_opts} = [ $c->model("RetreatCenterDB::CanPol")->search(
        undef,
        { order_by => 'name' },
    ) ];
    # and housing costs
    $c->stash->{housecost_opts} =
        [ $c->model("RetreatCenterDB::HouseCost")->search(
            undef,
            { order_by => 'name' },
        ) ];
    # templates
    $c->stash->{template_opts} = [
        grep { ! $sys_template{$_} }
        map { s{^.*templates/(.*)[.]html$}{$1}; $_ }
        <root/static/templates/*.html>
    ];

    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "program/create_edit.tt2";
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    # dates are either blank or converted to d8 format
    my @mess;
    for my $d (qw/ sdate edate /) {
        my $fld = $c->request->params->{$d};
        if (! $fld =~ /\S/) {
            push @mess, "missing date field";
            next;
        }
        my $dt = date($fld);
        if ($fld && ! $dt) {
            # tell them which date field is wrong???
            push @mess, "Invalid date: $fld";
            next;
        }
        $c->request->params->{$d} = $dt? $dt->as_d8()
                                   :     "";
    }
    if (!@mess && $c->request->params->{sdate}
                  > 
                  $c->request->params->{edate}
    ) {
        push @mess, "end date must be after the start date";
    }
    if (! $c->request->params->{title} =~ /\S/) {
        push @mess, "title cannot be blank";
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        # ??? person or program or a general error template?
        $c->stash->{template} = "person/error.tt2";
        return;
    }

    my %hash;
    # ??? ask DBIx for this list?
    # ??? put at top for use here and in update_do?
    for my $w (qw/
        name title subtitle glnum housecost_id
        retreat sdate edate tuition confnote
        url webdesc brdesc webready
        kayakalpa canpol_id extradays full_tuition deposit
        collect_total linked ptemplate sbath quad
        economy footnotes
        school level
    /) {
        $hash{$w} = $c->request->params->{$w};
    }
    $hash{url} =~ s{^\s*http://}{};
    if (my $upload = $c->request->upload('image')) {
        $upload->copy_to("root/static/images/po-$id.jpg");
        Lookup->init($c);
        resize('p', $id);
        $hash{image} = "yes";
    }
    my $p = $c->model("RetreatCenterDB::Program")->find($id);
    $p->update(\%hash);
    $c->response->redirect($c->uri_for("/program/view/" . $p->id));
}

sub leader_update : Local {
    my ($self, $c, $id) = @_;

    my $p = $c->stash->{program}
        = $c->model("RetreatCenterDB::Program")->find($id);
    $c->stash->{leader_table} = leader_table($c, $p->leaders());
    $c->stash->{template} = "program/leader_update.tt2";
}

sub leader_update_do : Local {
    my ($self, $c, $id) = @_;

    my @cur_leaders = grep {  s{^lead(\d+)}{$1}  }
                      keys %{$c->request->params};
    # delete all old leaders and create the new ones.
    $c->model("RetreatCenterDB::LeaderProgram")->search(
        { p_id => $id },
    )->delete();
    for my $cl (@cur_leaders) {
        $c->model("RetreatCenterDB::LeaderProgram")->create({
            l_id => $cl,
            p_id => $id,
        });
    }
    # show the program again - with the updated leaders
    view($self, $c, $id);
    $c->forward('view');
}

sub affil_update : Local {
    my ($self, $c, $id) = @_;

    my $p = $c->stash->{program}
        = $c->model("RetreatCenterDB::Program")->find($id);
    $c->stash->{affil_table} = affil_table($c, $p->affils());
    $c->stash->{template} = "program/affil_update.tt2";
}

sub affil_update_do : Local {
    my ($self, $c, $id) = @_;

    my @cur_affils = grep {  s{^aff(\d+)}{$1}  }
                     keys %{$c->request->params};
    # delete all old affils and create the new ones.
    $c->model("RetreatCenterDB::AffilProgram")->search(
        { p_id => $id },
    )->delete();
    for my $ca (@cur_affils) {
        $c->model("RetreatCenterDB::AffilProgram")->create({
            a_id => $ca,
            p_id => $id,
        });
    }
    # show the program again - with the updated affils
    view($self, $c, $id);
    $c->forward('view');
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    # explain this choice - see Person.pm.
    $c->model('RetreatCenterDB::Program')->search(
        { id => $id }
    )->delete();
    $c->model('RetreatCenterDB::AffilProgram')->search(
        { p_id => $id }
    )->delete();
    # ??? LeaderProgram, too.
    $c->response->redirect($c->uri_for('/program/list'));
}

sub del_image : Local {
    my ($self, $c, $id) = @_;

    my $p = $c->stash->{program}
        = $c->model("RetreatCenterDB::Program")->find($id);
    $p->update({
        image => "",
    });
    unlink <root/static/images/p*-$id.jpg>;
    $c->response->redirect($c->uri_for("/program/view/$id"));
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

my @programs;
my %except;

#
# shall we provide some entertainment while
# the ftp'ing is happening???  how to do that?
# some Javascript and some way of not using
# a template at the end with the results
# but to show the incremental progress.
#
sub publish : Local {
    my ($self, $c) = @_;

    # clear the arena
    system("rm -rf gen_files; mkdir gen_files; mkdir gen_files/pics");

    # and make sure we have initialized %lookup.
    Lookup->init($c);

    #
    # get all the programs into an array
    # sorted by start date and then end date.
    # ???this seems to work but I suspect there is
    # a better way to do this???  
    # Can I do $c->model('RetreatCenterDB::Program')->future_programs()???
    # No.
    #
    @programs = RetreatCenterDB::Program->future_programs($c);

    gen_month_calendars($c);
    gen_regtable();

    #
    # get the exceptions
    #
    for my $e ($c->model('RetreatCenterDB::Exception')->all()) {
        $except{$e->prog_id}{$e->tag} = expand($e->value);
    }

    # 
    # generate each of the program pages
    #
    # a side effect will be to copy the pictures of
    # the leaders or the program picture
    # to the holding area.
    #
    my $tag_regexp = '<!--\s*T\s+(\w+)\s*-->';
    for my $p (@programs) {
        my $fname = $p->fname();
        open my $out, ">", "gen_files/$fname"
            or die "cannot create $fname: $!\n";
        my $copy = $p->template_src();
        $copy =~ s{$tag_regexp}{
            $except{$p->id}{$1} || $p->$1()
        }xge;
        print {$out} $copy;
        close $out;
    }

    #
    # generate the program and event calendars
    #
    my $events = "";
    my $programs = "";

    my $progRow     = slurp "progRow";
    my $e_progRow   = slurp "e_progRow";
    my $e_rentalRow = slurp "e_rentalRow";

    my $cur_event_month = 0;
    my $cur_prog_month = 0;
    my ($rental);
    my @rentals  = RetreatCenterDB::Rental->future_rentals($c);
    for my $e (sort {
                   $a->sdate <=> $b->sdate
                   or
                   $a->edate <=> $b->edate
               }
               grep {
                   $_->linked
               }
               @programs,
               @rentals
    ) {
        $rental = (ref($e) =~ m{Rental$});
        my $sdate = $e->sdate_obj;
        my $smonth = $sdate->month;
        my $my = monthyear($sdate);
        if ($cur_event_month != $smonth) {
            $events .= "<tr><td class='event_my_row' colspan=2>$my</td></tr>\n";
            $cur_event_month = $smonth;
        }
        if (not $rental and $cur_prog_month != $smonth) {
            $programs .= "<tr><td class='prog_my_row' colspan=2>$my</td></tr>\n";
            $cur_prog_month = $smonth;
        }
        if ($rental) {
            my $copy = $e_rentalRow;
            $copy =~ s/$tag_regexp/
                $e->$1()        # no exception for rentals here - okay???
            /xge;
            $events .= $copy;
        }
        else {
            my $copy = $e_progRow;
            $copy =~ s/$tag_regexp/
                $except{$e->id}{$1} || $e->$1()
            /xge;
            $events .= $copy;

            $copy = $progRow;
            $copy =~ s/$tag_regexp/
                $except{$e->id}{$1} || $e->$1()
            /xge;
            $programs .= $copy;
        }
    }
    #
    # we have gathered all the info.
    # now to insert it in the templates and output
    # the .html files for the program and event lists.
    #
    my $s;
    $s = slurp "events";
    open my $out, ">", "gen_files/events.html"
        or die "cannot create events.html: $!\n";
    $s =~ s/<!--\s*T\s+eventlist.*-->/$events/;
    print {$out} $s;
    close $out;
    $s = slurp "programs";
    undef $out;
    open $out, ">", "gen_files/programs.html"
        or die "cannot create programs.html: $!\n";
    $s =~ s/<!--\s*T\s+programlist.*-->/$programs/;
    print {$out} $s;
    close $out;

    #
    # finally, ftp it all to www.mountmadonna.org
    # or whereever Lookup says, that is...
    #
    my $ftp = Net::FTP->new($lookup{ftp_site})
        or die "cannot connect to ...";    # not die???
    $ftp->login($lookup{ftp_login}, $lookup{ftp_password})
        or die "cannot login ", $ftp->message; # not die???
    if ($lookup{ftp_dir}) {
        $ftp->cwd($lookup{ftp_dir})
            or die "cannot cwd ", $ftp->message; # not die???
    }
    $ftp->rmdir("staging", 1);      # clear it all away
    $ftp->mkdir("staging");
    $ftp->cwd("staging");
    chdir "gen_files";
    $ftp->ascii();
    for my $f (<*.html>, 'regtable') {
        $ftp->put($f)
            or die "cannot put $f"; # not die???
    }
    $ftp->binary();
    chdir "pics";
    $ftp->mkdir("pics");
    $ftp->cwd("pics");
    for my $f (<*.jpg>) {
        $ftp->put($f)
            or die "cannot put $f"; # not die???
    }
    chdir "../..";
    $ftp->quit();
    $c->stash->{template} = "program/published.tt2";
}

#
# go through the programs in ascending date order
# and create the monthly calendar files calX.html
# where X is the month number.
#
# skip the unlinked ones
#
# clear them first? or after using them???
#
sub gen_month_calendars {
my ($c) = @_;
    my $cur_month = 0;
    my $cal;
    for my $p (grep { $_->linked } @programs) {
        my $m = $p->sdate_obj->month;
        if ($m != $cur_month) {
            # finish the prior calendar file, if any
            if ($cur_month) {
                print {$cal} "</table>\n";
                close $cal;
                undef $cal;
            }
            # start a new calendar file
            $cur_month = $m;
            undef $cal;
            open $cal, ">", "root/static/templates/cal$m.tmp"
                or die "cannot create cal$m.tmp: $!\n";
            my $my = monthyear($p->sdate_obj);
            print {$cal} <<EOH;
<table class='caltable'>
<tr><td class="monthyear" colSpan=2>$my</td></tr>
EOH
        }
        # the program info itself
        print {$cal} "<tr>\n<td class='dates_tr'>",
                  $p->dates_tr, "</td>",
                  "<td class='title'><a href='",
                  $p->fname, "'>",
                  $p->title1, 
                  "</a><br><span class='subtitle'>",
                  $except{$p->id}{title2} || $p->title2,
                  "</span></td></tr>";
    }
    # finish the prior calendar file, if any
    if ($cur_month) {
        print {$cal} "</table>\n";
        close $cal;
    }
}
#
# generate the regtable for online registration
#
sub gen_regtable {
    open my $regt, ">", "gen_files/regtable"
        or die "cannot create regtable: $!\n";
    for my $p (@programs) {
        my $ndays = ($p->edate_obj - $p->sdate_obj) || 1;	# personal retreats
        my $fulldays = $ndays + $p->extradays;

        #
        # prognum and pname should be first and second
        # for looking up purposes.
        #
        print {$regt} "prognum\t", $p->prognum, "\n";
        print {$regt} "pname\t", $p->name, "\n";
        print {$regt} "desc\t", $p->title, "\n";
        print {$regt} "dates\t", $p->dates, "\n";
        print {$regt} "edate\t", $p->edate, "\n";
        print {$regt} "leaders\t", $p->leader_names, "\n";
        print {$regt} "footnotes\t", $p->footnotes, "\n";
        print {$regt} "ndays\t$ndays\n";
        print {$regt} "fulldays\t$fulldays\n";
        print {$regt} "deposit\t", $p->deposit, "\n";
        print {$regt} "colltot\t", $p->collect_total, "\n";
        my $pol = $p->cancellation_policy();
        $pol =~ s/\n/NEWLINE/g;
        print {$regt} "canpol\t$pol\n";

        my $tuition = $p->tuition;
        my $full_tuition = $p->full_tuition;
        my $month = $p->sdate_obj->month;

        my $housecost = $p->housecost;
        for my $t (housing_types()) {
            next if $t =~ /unknown/;
            next if $t =~ /quad/        && !$p->quad;
            next if $t =~ /economy/     && !$p->economy;
            next if $t =~ /single_bath/ && !$p->sbath;
            next if $t =~ /center_tent/
                && !($p->name =~ m{personal retreat}i
                     || $p->name =~ m{tnt}i
                     || (5 <= $month && $month <= 10));
            next if $t =~ m{triple|dormitory}
                    && $p->name =~ m{personal retreat}i;
            print {$regt} "basic $t\t", $p->fees(0, $t), "\n";
            if ($p->extradays) {
                print {$regt} "full $t\t", $p->fees(1, $t), "\n";
            }
        }
    }
    close $regt;
}

1;

__END__

