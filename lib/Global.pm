use strict;
use warnings;
#
# this is just an exported hash
# initialized from the database table
# must be a better way - to access %string
# from Program.pm
# how to get access to $c from Program.pm???
#
# after updating a string this hash is out of date.
# so must call Lookup->init($c) each time before
# using %string.
# - not any more - we now change the exported hash.
# we'll call it each time anyway - in case we
# restart without Logging out and in again.
# we don't need to reinitialize if we've done it before, however.
# very confusing indeed.
# there must be a way to do this init() at
# catalyst startup time.???
#
# why can't I do "use Util qw/ model /; here???
#
package Global;

use Date::Simple;

use base 'Exporter';
our @EXPORT_OK = qw/
    %string
    @clusters
    %cluster
    %houses_in
    %houses_in_cluster
    %house_name_of
    %annotations_for
    $alert
    $guru_purnima
/;

our %string;
our @clusters;
our %cluster;
our %houses_in;     # house objects in cluster type
our %houses_in_cluster;         # ??? better name?
our %house_name_of;
our %annotations_for;
our $alert;
our $guru_purnima;

sub init {
    my ($class, $c, $force) = @_;
    
    return if %string && ! $force;      # already done
                                        # and we don't want to force it again

    %string            = ();
    @clusters          = ();
    %houses_in         = ();
    %houses_in_cluster = ();
    %house_name_of     = ();
    %annotations_for   = ();
    for my $s (Util::model($c, 'String')->all()) {
        $string{$s->the_key} = $s->value;
    }
    my %clust_type;     # not exported - intermediate variable
    for my $cl (Util::model($c, 'Cluster')->search(
        {},
        { order_by => 'name' })
    ) {
        my $id = $cl->id();
        push @clusters, $cl;
        $cluster{$id} = $cl;
        $houses_in_cluster{$id} = [];
        $clust_type{$id} = $cl->type();
    }
    for my $h (Util::model($c, 'House')->search(
                  {
                      inactive => '',
                  },
                  {
                      order_by => 'cluster_order',    # mostly for ClusterView
                  }
              )
    ) {
        $house_name_of{$h->id()} = $h->name();
        push @{$houses_in{$clust_type{$h->cluster_id()}}}, $h;      # wow
        push @{$houses_in_cluster{$h->cluster_id()}},      $h;
    }
    for my $a (Util::model($c, 'Annotation')->search({
                   inactive => '',
               })
    ) {
        push @{$annotations_for{$a->cluster_type()}}, $a;           # yeah
    }
    my @affils = Util::model($c, 'Affil')->search({
        descrip => { like => '%alert%when%' },
    });
    $alert = $affils[0]->id();
    @affils = Util::model($c, 'Affil')->search({
        descrip => { like => '%guru%purnima%' },
    });
    $guru_purnima = $affils[0]->id();
    Date::Simple->default_format($string{default_date_format});
    #
    # create the stop script
    #
    open my $stop, ">", "stop"
        or die "cannot create stop script\n";
    print {$stop} "#!/bin/sh\n";
    print {$stop} "kill $$\n";
    print {$stop} "rm stop\n";
    close $stop;
    chmod 0755, "stop";
}

1;
