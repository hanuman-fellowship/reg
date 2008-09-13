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
    %clust_color
    %houses_in
    %annotations_for
/;

our %string;
our %clust_color;
our %houses_in;     # house objects in cluster type
our %annotations_for;

sub init {
    my ($class, $c, $force) = @_;
    
    return if !$force && %string;      # already done

    %string          = ();
    %clust_color     = ();
    %houses_in       = ();
    %annotations_for = ();
    for my $s ($c->model('RetreatCenterDB::String')->all()) {
        $string{$s->the_key} = $s->value;
    }
    my %clust_type;     # not exported - intermediate variable
    for my $cl ($c->model('RetreatCenterDB::Cluster')->all()) {
        my $id = $cl->id();
        $clust_color{$id} = [ $cl->color =~ m{\d+}g ];
        $clust_type{$id} = $cl->type();
    }
    for my $h ($c->model('RetreatCenterDB::House')->search({
                   inactive => '',
               })
    ) {
        push @{$houses_in{$clust_type{$h->cluster_id()}}}, $h;      # wow
    }
    for my $a ($c->model('RetreatCenterDB::Annotation')->search({
                   inactive => '',
               })
    ) {
        push @{$annotations_for{$a->cluster_type()}}, $a;           # yeah
    }
}

1;
