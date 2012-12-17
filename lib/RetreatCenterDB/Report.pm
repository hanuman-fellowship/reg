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
overview - 
descrip - 
format - 
id  - 
last_run - 
nrecs - 
rep_order - 
zip_range - 
