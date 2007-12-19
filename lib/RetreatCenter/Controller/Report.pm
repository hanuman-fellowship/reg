use strict;
use warnings;
# ??? order - name, sanskrit, zip - not first, last, zip
package RetreatCenter::Controller::Report;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.

use Util qw/affil_table/;
use Validate qw/parse_zips/;
use Date::Simple qw/date today/;

Date::Simple->default_format("%D");      # set it here - where else???

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('list');
}

sub formats : Private {
    my ($self, $c) = @_;

    return {
        1 => 'Email to CMS',
        2 => 'Name, Address, Email',
        3 => 'Name, Home, Work, Cell',
        4 => 'Email to VistaPrint',
        5 => 'Just Email',
    };
}


sub list : Local {
    my ($self, $c) = @_;

    $c->stash->{reports} = [
        $c->model('RetreatCenterDB::Report')->search(
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

    #
    # i tried using delete_all to do the cascade to the affils for this report.
    # look at the DBIC_TRACE - it does it very inefficiently :(.
    # delete with find() does the same.  but not with search()???.
    #
    #$c->model('RetreatCenterDB::Report')->search({id => $id})->delete_all();
    #
    #$c->model('RetreatCenterDB::Report')->find($id)->delete();
    #
    $c->model('RetreatCenterDB::Report')->search({id => $id})->delete();
    $c->model('RetreatCenterDB::AffilReport')->search({report_id => $id})->delete();

    $c->forward('list');
}


sub view : Local {
    my ($self, $c, $id) = @_;

    my $report = $c->model('RetreatCenterDB::Report')->find($id);
    $c->stash->{format_verbose} = $self->formats->{$report->format()};
    $c->stash->{report} = $report;
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

    my $report = $c->model('RetreatCenterDB::Report')->find($id);
    $c->stash->{report} = $report;
    $c->stash->{'format_selected_' . $report->format()} = 'selected';
    $c->stash->{'rep_order_selected_' . $report->rep_order()} = 'selected';
    $c->stash->{affil_table} = affil_table($c, $report->affils());
    $c->stash->{form_action} = "update_do/$id";
    $c->stash->{template}    = "report/create_edit.tt2";
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

    my $zips = parse_zips($c->request->params->{zip_range});
    if (! ref($zips)) {
        $c->stash->{error_msg} = $zips;
        $c->stash->{template} = 'report/error.tt2';
        return;
    }

    # ???: No transactions? How do you know the update worked?

    $c->model("RetreatCenterDB::Report")->find($id)->update({
        descrip   => $c->request->params->{descrip},
        rep_order => $c->request->params->{rep_order},
        format    => $c->request->params->{format},
        zip_range => $c->request->params->{zip_range},
        nrecs     => $c->request->params->{nrecs},
    });


    #
    # which affiliations are checked?
    #
    $c->model("RetreatCenterDB::AffilReport")->search(
        { report_id => $id },
    )->delete();

    my @cur_affils = grep { s/^aff(\d+)/$1/ }
                     keys %{$c->request->params};
    for my $ca (@cur_affils) {
        $c->model("RetreatCenterDB::AffilReport")->create({
            affiliation_id => $ca,
            report_id => $id,
        });
    }
    $c->forward('view');
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

    my $zips = parse_zips($c->request->params->{zip_range});
    if (! ref($zips)) {
        $c->stash->{error_msg} = $zips;
        $c->stash->{template} = 'report/error.tt2';
        return;
    }

    my $report = $c->model("RetreatCenterDB::Report")->create({
        descrip   => $c->request->params->{descrip},
        rep_order => $c->request->params->{rep_order},
        format    => $c->request->params->{format},
        zip_range => $c->request->params->{zip_range},
        nrecs     => $c->request->params->{nrecs},
        last_run  => '',
    });


    my $id = $report->id();
    #
    # which affiliations are checked?
    #
    my @cur_affils = grep { s/^aff(\d+)/$1/ }
                     keys %{$c->request->params};
    for my $ca (@cur_affils) {
        $c->model("RetreatCenterDB::AffilReport")->create({
            affiliation_id => $ca,
            report_id => $id,
        });
    }
    $c->forward('list');
}

#
# execute the report generating the proper output
# for the people that match the conditions.
#
sub run : Local {
    my ($self, $c, $id) = @_;

    my $report = $c->model('RetreatCenterDB::Report')->find($id);

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

    my $order = $report->rep_order();
    my $fields = "first||' '||last as name, p.*";

    my $just_email = "";
    if ($report->format() == 5) {   # Just Email
        # we only want non-blank emails
        $just_email = " and email != ''";
        $order = "email";
        $fields = "email";
    }

# ??? without the distinct below
# we get a row for each person and each affil that matches
# i need an sql expert to explain this to me.

    my $sql = <<"EOS";

select distinct $fields
  from people p $ap
 where mailings = 'yes' $just_email and
       $zip_bool $affil_bool
 order by $order;

EOS
    # mimic DBIx::Class tracing    - it is worth the energy to
    #                                figure out how to do the above
    #                                in Abstract::SQL???
    if ($ENV{DBIC_TRACE}) {
        $c->log->info($sql);
    }
# ??? put it in an array dude - yes simpler ???
# thanks to Shanku
    my $people_ref = Person->search($sql);
    #
    # now to take care of two people in the report
    # who are partners.   this is tricky!  wake up.
    #
    # if we are asking for "Just Email" this won't really apply.
    # no id_sps field so...
    #
    my %partner_index = ();
    my $i = 0;
    for my $p (@$people_ref) {
        if ($p->{id_sps}) {
            $partner_index{$p->{id}} = $i;
        }
        ++$i;
    }
    my $ndel = 0;
    for my $p (@$people_ref) {
        if ($p->{id_sps}
            && (my $pi = $partner_index{$p->{id_sps}})
        ) {
            my $ptn = $people_ref->[$pi];
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
    # filter out the ones we marked for deletion above.
    # wasteful of memory???
    # yes, but memory is cheap, right?
    # if you have a better way of doing this please suggest it!
    #
    if ($ndel) {
        $people_ref = [
            grep { ! $_->{deleted} } @$people_ref
        ];
    }
    #
    # a random selection of nrecs?
    # keep it in the same order as before.
    #
    my $nrecs = $report->nrecs();
    if ($nrecs && $nrecs > 0 && $nrecs < $#$people_ref) {
        my @nums = 0 .. $#$people_ref;      # looks funny!
        my @subset;
        for (1 .. $nrecs) {
            push @subset, splice(@nums, rand(@nums), 1);
        }
        @subset = sort { $a <=> $b } @subset;
        $people_ref = [ @$people_ref[@subset] ];    # an intense slice!
    }

    #
    # generate a file rather than a screen?
    # for all???
    #
    my $fname = '';
    if ($report->format() == 4) {       # VistaPrint
        #
        # ??? what about partnered people?
        # yeah. what does VistaPrint do with
        # the 6 fields of the name - concatenate them all (if
        # non-blank, that is)?
        # any length restrictions on them?
        # if not we could just put our 'name' in the Salutation
        # and it could be a partnered name.
        #
        $fname = "root/static/vistaprint.txt";
        open my $out, ">", $fname
            or die "cannot create $fname: $!\n";
        my $t = "\t";
        print {$out} join $t,
            "Salutation",
            "First name",
            "Middle",
            "Last Name",
            "Suffix",
            "Title",
            "Company",
            "Address Line 1",
            "Address Line 2",
            "City",
            "State",
            "Zip+4";
        print {$out} "\n";
        for my $p (@$people_ref) {
            # accomodate partners
            if ($p->{name} =~ m{(.*)(\&.*)}) {
                $p->{first} = $1;
                $p->{last}  = $2;
            }
            print {$out} join $t,
                "",
                $p->{first},
                "",
                $p->{last},
                "",
                "",
                "",
                $p->{addr1},
                $p->{addr2},
                $p->{city},
                $p->{st_prov},
                $p->{zip_post};
            print {$out} "\n";
        }
        close $out;
    }
    elsif ($report->format() == 5) {       # Just Email
        $fname = "root/static/just_email.txt";
        open my $out, ">", $fname
            or die "cannot create $fname: $!\n";
        for my $p (@$people_ref) {
            print {$out} $p->{email}, "\n";
        }
        close $out;
    }
    #
    # finally, mark the report as having been run today.
    #
    $report->update({
        last_run => today(),
    });

    $c->stash->{count}    = scalar(@$people_ref);
    $fname =~ s{root/}{};       # why is this needed???
    $c->stash->{filename} = $fname;
    $c->stash->{people}   = $people_ref;
    $c->stash->{template} = "report/run" . $report->format() . ".tt2";
}

1;
