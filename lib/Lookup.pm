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
# - not any more - we now change the exported hash.
# we'll call it each time anyway - in case we
# restart without Logging out and in again.
# we don't need to reinitialize if we've done it before, however.
# very confusing indeed.
# there must be a way to do this init() at
# catalyst startup time.???
#
package Lookup;
use base 'Exporter';
our %lookup;
our @EXPORT = qw/%lookup/;

sub init {
    my ($class, $c) = @_;
    
    return if %lookup;      # already done
    for my $s ($c->model("RetreatCenterDB::String")->all()) {
        $lookup{$s->the_key} = $s->value;
    }
}

1;
