use strict;
use warnings;
package RetreatCenterDB::Report;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('reports');
__PACKAGE__->add_columns(qw/
    id 
    descrip
    format
    zip_range
    rep_order
    nrecs
    last_run
/);
__PACKAGE__->set_primary_key(qw/id/);
__PACKAGE__->many_to_many(affils => 'affil_report', 'affil');

1;
__END__
overview - Reports are used to select a subset of People for mailing list purposes.
    The selection is based on zip code and affiliation.
    A variety of formats can be generated - including snail mail address and or email address.
descrip - an identifier for the report
format - 10 different ones
id  - a unique id
last_run - last date this report was run
nrecs - how many records do you want?  a random selection will be made for you
    to achieve this many.
rep_order - what order should the people records be in?  Zip Code or Last Name
zip_range - a free text field describing a zip code range - like "95060, 94050-94090"
