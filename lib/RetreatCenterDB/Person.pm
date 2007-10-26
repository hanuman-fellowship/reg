packager RetreatCenterDB::Person; 
use strict;
 
use base qw/DBIx::Class/; 
 
__PACKAGE__->load_components(qw/PK::Auto Core/); 
__PACKAGE__->table('persons'); 
__PACKAGE__->add_columns(qw/
                id 
                first_name 
                last_name 
                alias 
                address 
                city 
                state 
                zip 
                country 
                day_phone 
                evening_phone 
                email 
                fax 
                name_preference 
                sex 
                partner_id 
                akey 
                referral 
                ad_source 
                wstudy 
                ceu_requested 
                ceu_license 
                center_status 
                credit_code 
                birth_dt 
                hf_dt 
                path_dt 
                lm_dt 
                create_dt 
                update_dt 
            /);

__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->has_many(person_affiliations => 'RetreatCenterDB::PersonAffiliation', 'person_id');

__PACKAGE__->many_to_many(affiliations => 'person_affiliations', 'affiliation');

__PACKAGE__->belongs_to(partner => 'RetreatCenterDB::Person', 'partner_id');

__PACKAGE__->belongs_to(name_preference => 'RetreatCenterDB::NamePreference', 'name_preference');

__PACKAGE__->belongs_to(credit_code => 'RetreatCenterDB::CreditCode', 'credit_code');

__PACKAGE__->belongs_to(center_status => 'RetreatCenterDB::CenterStatus', 'center_status');


1; 
