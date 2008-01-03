use strict;
use warnings;
#
# this is just an exported hash
# initialized from the database table
# must be a better way - to access %lookup
# from Program.pm
# how to get access to $c from Program.pm???
#
# after updating a string this hash is out of date.
# so must call Lookup->init($c) each time before
# using %lookup.
#
package Lookup;
use base 'Exporter';
our %lookup;
our @EXPORT = qw/%lookup/;

sub init {
    my ($class, $c) = @_;
    for my $s ($c->model("RetreatCenterDB::String")->all()) {
        $lookup{$s->key} = $s->value;
    }
    $c->log->info("here we are $lookup{website}");
}

1;
