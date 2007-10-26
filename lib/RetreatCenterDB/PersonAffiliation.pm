packager RetreatCenterDB::PersonAffiliation; 
use strict;
 
use base qw/DBIx::Class/; 
 
__PACKAGE__->load_components(qw/PK::Auto Core/); 
__PACKAGE__->table('person_affiliation'); 
__PACKAGE__->add_columns(qw/
                person_id 
                affiliation_id 
                affiliation_dt 
            /);

__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to(affiliation => 'RetreatCenterDB::Affiliation', 'affiliation_id');

__PACKAGE__->belongs_to(person => 'RetreatCenterDB::Person', 'person_id');
 
1;
