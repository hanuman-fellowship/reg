use strict;
use warnings;
#
# these are exported hashes and arrays
# initialized from the database table.
#
# must be a better way - to access %string
# from Program.pm
# how to get access to $c from Program.pm???
#
# after updating a string this hash is out of date.
# so must call Global->init($c) each time before
# using %string.
# - not any more - we now change the exported hash.
# we'll call it each time anyway - in case we
# restart without Logging out and in again.
# we don't need to reinitialize if we've done it before, however.
# very confusing indeed.
# there must be a way to do this init() at
# catalyst startup time.???
# 4/28/19 - introduced the sys_cache_timestamp to deal
# with the multiple slave servers now.
#
# why can't I do "use Util qw/ model /; here???
#
package Global;

use Date::Simple;

use base 'Exporter';
our @EXPORT_OK = qw/
    %string
    %system_affil_id_for
    @hfs_affil_ids

    @clusters
    %cluster
    %houses_in
    %houses_in_cluster
    %house_name_of
    %annotations_for
/;

our %string;
our @clusters;
our %cluster;
our %houses_in;     # house objects in cluster type
our %houses_in_cluster;         # ??? better name?
our %house_name_of;
our %annotations_for;
our %system_affil_id_for;
our @hfs_affil_ids;

my $scts = 'sys_cache_timestamp';

sub init {
    my ($class, $c, $force, $for_grab) = @_;
    
    # is this memory cache up to date with the database?
    # do we want to force it again?
    if (%string
        && $string{$scts} >= Util::get_string($c, $scts)
        && ! $force
    ) {
        return;
    }

    %string            = ();
    @clusters          = ();
    %houses_in         = ();
    %houses_in_cluster = ();
    %house_name_of     = ();
    %annotations_for   = ();

    # strings
    for my $s (Util::model($c, 'String')->all()) {
        $string{$s->the_key} = $s->value;
    }
    if ($string{$scts} == 0) {
        # only needed once
        my $s = Util::model($c, 'String')->find($scts);
        my $t = time();
        $s->update({
            value => $t,
        });
        $string{$scts} = $t;
    }

    # system and hfs affiliations
    my @affils = Util::model($c, 'Affil')->search({
        system => 'yes',
    });
    for my $a (@affils) {
        my $id = $a->id;
        my $descrip = $a->descrip;
        $system_affil_id_for{$descrip} = $id;
        if ($descrip =~ m{ \A HFS \s+ Member }xms) {
            push @hfs_affil_ids, $id;
        }
    }

    return if $for_grab;    # grab_new only needs the above

    # cluster related variables
    my %clust_type;     # not exported - intermediate variable
    for my $cl (Util::model($c, 'Cluster')->search(
        {},
        { order_by => 'cl_order' })
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

    Date::Simple->default_format($string{default_date_format});
}

1;
