package RetreatCenter::Controller::Report;

use strict;
use warnings;
use base 'Catalyst::Controller';

use lib '../../';

use Util qw/affil_table/;
use Validate;
use Date::Simple qw/date today/;

Date::Simple->default_format("%D");      # set it here - where else???



sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('search');
}

sub formats : Private {
    my ($self, $c) = @_;

    return {
        '1' =>  'Name, Address, Country, Email',
        '2' =>  'Name, Address, Zip',
        '3' =>  'Name, Address, Zip, Country',
        '4' =>  'Name, Home Tel#, Work Tel#',
        '5' =>  'Name, Home Tel#',
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
    $c->stash->{last_run}  = date($report->last_run())  || "Not Run Yet.";;
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

    # ???: This needs refactoring. Put this in some validate.pm or something.

    my $zip_range = $c->request->params->{zip_range};
    my $error;

    if ($error = Validate::zip_range($zip_range)) {
        $c->stash->{error_msg} = $error;
        $c->stash->{template} = 'report/error.tt2';
        return;
    }

    # ???: No transactions? How do you know the update worked?

    $c->model("RetreatCenterDB::Report")->find($id)->update({
        descrip       => $c->request->params->{descrip},
        rep_order     => $c->request->params->{rep_order},
        format        => $c->request->params->{format},
        zip_range     => $c->request->params->{zip_range},
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
    $c->forward('list');
}

sub create : Local {
    my ($self, $c) = @_;

    $c->stash->{affil_table} = affil_table($c);
    $c->stash->{form_action} = "create_do";
    $c->log->info("Setting template in create()");
    $c->stash->{template}    = "report/create_edit.tt2";
}

#
# check for dups???
#
sub create_do : Local {
    my ($self, $c) = @_;

    my $zip_range = $c->request->params->{zip_range};
    my $error;

    if ($error = Validate::zip_range($zip_range)) {
        $c->stash->{error_msg} = $error;
        $c->stash->{template} = 'report/error.tt2';
        return;
    }

    my $report = $c->model("RetreatCenterDB::Report")->create({
        descrip       => $c->request->params->{descrip},
        rep_order     => $c->request->params->{rep_order},
        format        => $c->request->params->{format},
        zip_range     => $c->request->params->{zip_range},
        last_run => '',
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

1;
