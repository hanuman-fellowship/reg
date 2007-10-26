packager RetreatCenterDB::CreditCode; 
 
use base qw/DBIx::Class/; 
 
__PACKAGE__->load_components(qw/PK::Auto Core/); 
__PACKAGE__->table('credit_codes'); 
__PACKAGE__->add_columns(qw/
                id 
                description
            /);

__PACKAGE__->set_primary_key(qw/id/);

1;
