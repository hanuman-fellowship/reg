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
package Global;

use base 'Exporter';
our @EXPORT_OK = qw/
    %string
    @clusters
    %clust_color
    %houses_in
    %houses_in_cluster
    %house_name_of
    %annotations_for
/;

our %string;
our @clusters;
our %clust_color;
our %houses_in;     # house objects in cluster type
our %houses_in_cluster;         # ??? better name?
our %house_name_of;
our %annotations_for;

use Date::Simple;

sub init {
    my ($class, $c, $force) = @_;
    
    return if %string && ! $force;      # already done
                                        # and we don't want to force it again

    %string            = ();
    @clusters          = ();
    %clust_color       = ();
    %houses_in         = ();
    %houses_in_cluster = ();
    %house_name_of     = ();
    %annotations_for   = ();
    for my $s ($c->model('RetreatCenterDB::String')->all()) {
        $string{$s->the_key} = $s->value;
    }
    my %clust_type;     # not exported - intermediate variable
    for my $cl ($c->model('RetreatCenterDB::Cluster')->search(
        {},
        { order_by => 'name' })
    ) {
        my $id = $cl->id();
        push @clusters, $cl;
        $clust_color{$id} = [ $cl->color =~ m{\d+}g ];
        $houses_in_cluster{$id} = [];
        $clust_type{$id} = $cl->type();
    }
    for my $h ($c->model('RetreatCenterDB::House')->search(
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
    for my $a ($c->model('RetreatCenterDB::Annotation')->search({
                   inactive => '',
               })
    ) {
        push @{$annotations_for{$a->cluster_type()}}, $a;           # yeah
    }
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
