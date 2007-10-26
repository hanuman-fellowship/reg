packager RetreatCenterDB::Kid; 
use strict;
 
use base qw/DBIx::Class/; 
 
__PACKAGE__->load_components(qw/PK::Auto Core/); 
__PACKAGE__->table('kids'); 
__PACKAGE__->add_columns(qw/
                parent_id 
                birth_dt
                sex
            /);

__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->has_many(affiliation_persons => 'RetreatCenterDB::PersonAffiliation', 'affiliation_id');

__PACKAGE__->many_to_many(persons => 'affiliation_persons', 'person');
 
1;
