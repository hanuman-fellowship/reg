use strict;
use warnings;
# ??? order - name, sanskrit, zip - not first, last, zip
package RetreatCenter::Controller::Report;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.

use Util qw/
    affil_table
    parse_zips
    empty
    trim
    model
    tt_today
/;
use Date::Simple qw/
    date
/;
use Template;

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('list');
}

sub formats : Private {
    my ($self, $c) = @_;

    return {
        1 => 'To CMS',
        2 => 'Name, Address, Email',
        3 => 'Name, Home, Work, Cell',
        4 => 'Email to VistaPrint',
        5 => 'Just Email',
        6 => 'Name, Address, Link',
        7 => 'First Sanskrit To CMS',
    };
}


sub list : Local {
    my ($self, $c) = @_;

    $c->stash->{reports} = [
        model($c, 'Report')->search(
            undef,
            {
                order_by => 'descrip',
            },
        )
    ];
    $c->stash->{template} = "report/list.tt2";
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    model($c, 'Report')->search({id => $id})->delete();
    model($c, 'AffilReport')->search({report_id => $id})->delete();

    $c->forward('list');
}


sub view : Local {
    my ($self, $c, $id, $mmi) = @_;

    my $report = model($c, 'Report')->find($id);
    $c->stash->{format_verbose} = $self->formats->{$report->format()};
    $c->stash->{report} = $report;
    $c->stash->{mmc_report} = !$mmi;
    $c->stash->{mmi_report} = $mmi;
    $c->stash->{affils} = [
        $report->affils(
            undef,
            {order_by => 'descrip'}
        )
    ];
    $c->stash->{last_run}  = date($report->last_run())  || "";;
    $c->stash->{template} = "report/view.tt2";
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $report = model($c, 'Report')->find($id);
    $c->stash->{report} = $report;
    $c->stash->{'format_selected_' . $report->format()} = 'selected';
    $c->stash->{'rep_order_selected_' . $report->rep_order()} = 'selected';
    $c->stash->{affil_table} = affil_table($c, $report->affils());
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "report/create_edit.tt2";
}

my %hash;
my @mess;
sub _get_data {
    my ($c) = @_;

    %hash = %{ $c->request->params() };
    for my $k (keys %hash) {
        delete $hash{$k} if $k =~ m{^aff\d+$};
    }
    @mess = ();
    if (empty($hash{descrip})) {
        push @mess, "The report description cannot be blank.";
    }
    my $zips = parse_zips($hash{zip_range});
    if (! ref($zips)) {
        push @mess, $zips;
    }
    unless ($hash{nrecs} =~ m{^\s*\d*\s*$}) {
        push @mess, "illegal Number of Records: $hash{nrecs}";
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "report/error.tt2";
    }
}

#
# currently there's no way to know which fields changed
# so assume they all did.  DBIx::Class is smart about this.
# can we be smart about affils???  yes, see ZZ below.
#
# check for dups???
#
sub update_do : Local {
    my ($self, $c, $id) = @_;

    _get_data($c);
    return if @mess;

    model($c, 'Report')->find($id)->update(\%hash);

    #
    # which affiliations are checked?
    #
    model($c, 'AffilReport')->search(
        { report_id => $id },
    )->delete();

    my @cur_affils = grep { s/^aff(\d+)/$1/ }
                     $c->request->param();
    for my $ca (@cur_affils) {
        model($c, 'AffilReport')->create({
            affiliation_id => $ca,
            report_id => $id,
        });
    }
    #$c->forward("view/$id");
    $c->response->redirect($c->uri_for("/report/view/$id"));
}

sub create : Local {
    my ($self, $c) = @_;

    $c->stash->{affil_table} = affil_table($c);
    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "report/create_edit.tt2";
}

#
# check for dups???
#
sub create_do : Local {
    my ($self, $c) = @_;

    _get_data($c);
    return if @mess;

    my $report = model($c, 'Report')->create({
        %hash,
        last_run  => '',
    });


    my $id = $report->id();
    #
    # which affiliations are checked?
    #
    my @cur_affils = grep { s/^aff(\d+)/$1/ }
                     $c->request->param();
    for my $ca (@cur_affils) {
        model($c, 'AffilReport')->create({
            affiliation_id => $ca,
            report_id => $id,
        });
    }
    $c->forward("view/$id");
}

#
# execute the report generating the proper output
# for the people that match the conditions.
#
sub run : Local {
    my ($self, $c, $id) = @_;

    my $share    = $c->request->params->{share};
    my $count    = $c->request->params->{count};
    my $collapse = $c->request->params->{collapse};
    my $incl_mmc = $c->request->params->{incl_mmc};
    my $mmi_report = $c->request->params->{report_type} eq 'mmi';
    my $pref = "";
    if ($mmi_report) {
        $pref = "mmi_";
    }

    my $report = model($c, 'Report')->find($id);
    my $format = $report->format();

    my $order = $report->rep_order();
    my $fields = "p.*";

    # restrictions apply?
    # have people said they want to be included?
    # ??? or is not null?
    my $restrict = "inactive != 'yes' and ";
    if ($format == 1 || $format == 2 || $format == 4 || $format == 7) {
        $restrict .= "${pref}snail_mailings = 'yes' and ";
    }
    if ($format == 2 || $format == 5) {
        $restrict .= "${pref}e_mailings = 'yes' and ";
    }
    if ($share) {
        $restrict .= "share_mailings = 'yes' and ";
    }
    if (! $incl_mmc) {
        $restrict .= "akey != '44595076SUM' and ";
    }

    my $just_email = "";
    if ($format == 5) {   # Just Email
        # we only want non-blank emails
        $just_email = "email != '' and ";
        $order = "email";
        $fields = "email";
    }

    my $range_ref = parse_zips($report->zip_range);
    # cannot return a scalar... else the edit would have failed...
    my $zip_bool;
    if (@$range_ref) {
        for my $r (@$range_ref) {
            $zip_bool .= "(p.zip_post between '$r->[0]' and '$r->[1]') or ";
        }
        $zip_bool =~ s{ or $}{};
        $zip_bool = "($zip_bool)";
        # we need the parens in case we have an 'or' inside
        # without parens here we get infinite looping in sql server???
        # why?
    }
    else {
        $zip_bool = "1";     # true
    }

    my $affils = join ',', map { $_->id() } $report->affils();
    my $ap = "";
    my $affil_bool = "";
    if ($affils) {
        $ap = ", affil_people ap";
        $affil_bool = "and (ap.p_id = p.id and ap.a_id in ($affils))";
    }

# ??? without the distinct below
# we get a row for each person and each affil that matches
# i need an sql expert to explain this to me.

    my $sql = <<"EOS";

select distinct $fields
  from people p $ap
 where $restrict $just_email
       $zip_bool $affil_bool
 order by $order;

EOS
    # mimic DBIx::Class tracing    - it is worth the energy to
    #                                figure out how to do the above
    #                                in Abstract::SQL???
    if ($ENV{DBIC_TRACE}) {
        $c->log->info($sql);
    }
    my @people = @{ Person->search($sql) };
    for my $p (@people) {
        if ($format == 7) {
            $p->{name} = $p->{first} . " "
                       . (($p->{sanskrit} && $p->{sanskrit} ne $p->{first})?
                              $p->{sanskrit} . " " : "")
                       . $p->{last};
        }
        elsif ($format != 5) {      # not just email
            $p->{name} = $p->{first} . " " . $p->{last};
        }
    }
    #
    # now to take care of two people in the report
    # who are partners.   this is tricky!  wake up.
    #
    # if we are asking for "Just Email" this won't really apply.
    # no id_sps field so...
    #
    my %partner_index = ();
    my $i = 0;
    for my $p (@people) {
        if ($p->{id_sps}) {
            $partner_index{$p->{id}} = $i;
        }
        ++$i;
    }
    my $ndel = 0;
    for my $p (@people) {
        if ($p->{id_sps}
            && (my $pi = $partner_index{$p->{id_sps}})
        ) {
            my $ptn = $people[$pi];
            if ($p->addr1() eq $ptn->addr1()) {
                # good enough match of address...
                # modify $p so that their 'name' is both of them
                # direct access... :(
                # treating this as an arrayref of hashrefs
                # or an arrayref of objects as convenient.
                $p->{name} = ($p->last eq $ptn->last)?
                                $p->first." & ".$ptn->first." ".$ptn->last:
                                $p->name." & ".$ptn->name; 
                #
                # and modify the data so the partner is not shown
                # nor even considered.
                #
                delete $partner_index{$p->id};
                delete $partner_index{$ptn->id};
                $ptn->{deleted} = 1;
                ++$ndel;
            }
        }
    }

    #
    # if we should collapse records with the same address, do so.
    #
    if ($collapse && ! $just_email) {
        # sort to get same addresses together
        @people = map {
                      $_->[1]
                  }
                  sort {
                      $a->[0] cmp $b->[0]
                  }
                  map {
                      [ $_->{akey}, $_ ]
                  }
                  @people;
        my $prev;
        my $prev_akey = "";
        for my $p (@people) {
            # if not deleted already (due to partnering) and the
            # address is the same as the previous person...
            #
            if (! $p->{deleted} && $p->{akey} eq $prev_akey) {
                $prev->{name} .= " et. al." unless $prev->{deleted};
                $p->{deleted} = 1;
                ++$ndel;
            }
            $prev = $p;
            $prev_akey = $p->{akey};
        }
        # resort
        @people = map {
                      $_->[1]
                  }
                  sort {
                      $a->[0] cmp $b->[0]
                  }
                  map {
                      [ $_->{$order}, $_ ]
                  }
                  @people;
    }

    #
    # filter out the ones we marked for deletion above.
    # wasteful of memory???
    # yes, but memory is cheap, right?
    # if you have a better way of doing this please suggest it!
    #
    if ($ndel) {
        @people = grep { ! $_->{deleted} } @people;
    }
    #
    # a random selection of nrecs?
    # keep it in the same order as before.
    #
    my $nrecs = $report->nrecs();
    if ($nrecs && $nrecs > 0 && $nrecs < @people) {
        my @nums = 0 .. $#people;
        my @subset = ();
        for (1 .. $nrecs) {
            push @subset, splice(@nums, rand(@nums), 1);
        }
        @subset = sort { $a <=> $b } @subset;
        @people = @people[@subset];    # slice!
    }
    if ($count) {
        $c->stash->{message} = "Record count = " . scalar(@people);
        $c->stash->{share}    = $share;
        $c->stash->{collapse} = $collapse;
        $c->stash->{incl_mmc} = $incl_mmc;
        view($self, $c, $id, $mmi_report);
        return;
    }
    #
    # mark the report as having been run today.
    #
    $report->update({
        last_run => tt_today($c),
    });
    if ($format == 4) {       # VistaPrint
        for my $p (@people) {
            # accomodate partners
            if ($p->{name} =~ m{(.*)(\&.*)}) {
                $p->{first} = trim($1);
                $p->{last}  = $2;
            }
        }
    }

    my $fname = "report$format";
    my $suf = "txt";
    if (open my $in, "<", "root/src/report/$fname.tt2") {
        my $line = <$in>;
        if ($line =~ m{^<}) {
            # it is likely HTML
            $suf = "html";
        }
    }
    # use the template toolkit outside of the Catalyst mechanism
    my $tt = Template->new({
        INCLUDE_PATH => 'root/src/report',
        EVAL_PERL    => 0,
    });
    $tt->process(
        "$fname.tt2", 
         { people => \@people },
         "root/static/$fname.$suf",
    ) or die "error in processing template: "
             . $tt->error();
    $c->response->redirect($c->uri_for("/static/$fname.$suf"));
}

1;
