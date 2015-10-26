use strict;
use warnings;
package RetreatCenterDB::School;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('school');
__PACKAGE__->add_columns(qw/
    id
    name
    mmi
/);
__PACKAGE__->set_primary_key(qw/id/);

1;
__END__
overview - Either MMC or one of the MMI colleges/schools
id - unique id
name - the school name
mmi - Is this an MMI school?
