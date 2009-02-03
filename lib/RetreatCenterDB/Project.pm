use strict;
use warnings;
package RetreatCenterDB::Project;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('project');
__PACKAGE__->add_columns(qw/
    id
    descr
    glnum
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->has_many(donations => 'RetreatCenterDB::Donation', 'project_id',
                          { order_by => 'date_donate desc'});

1;
