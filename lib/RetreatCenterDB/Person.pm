use strict;
use warnings;
package RetreatCenterDB::Person;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('people');
__PACKAGE__->add_columns(qw/
    last
    first
    sanskrit
    addr1
    addr2
    city
    st_prov
    zip_post
    country
    akey
    tel_home
    tel_work
    tel_cell
    email
    sex
    id
    id_sps
    date_updat
    date_entrd
    comment
    e_mailings
    snail_mailings
    share_mailings
    ambiguous
/);
__PACKAGE__->set_primary_key(qw/id/);

# affiliations
__PACKAGE__->has_many(affil_person => 'RetreatCenterDB::AffilPerson', 'p_id');
__PACKAGE__->many_to_many(affils => 'affil_person', 'affil',
                          { order_by => 'descrip' },
                         );

# registrations
__PACKAGE__->has_many(registrations => 'RetreatCenterDB::Registration', 'person_id');

# member - maybe
__PACKAGE__->might_have(member => 'RetreatCenterDB::Member', 'person_id');
# leader - maybe
__PACKAGE__->might_have(leader => 'RetreatCenterDB::Leader', 'person_id');
# partner - maybe
__PACKAGE__->might_have(partner => 'RetreatCenterDB::Person', 'id_sps');

1;
