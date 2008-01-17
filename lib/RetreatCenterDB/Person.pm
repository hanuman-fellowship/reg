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
    mailings
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->has_many(affil_person => 'RetreatCenterDB::AffilPerson', 'p_id');
__PACKAGE__->many_to_many(affils => 'affil_person', 'affil',
                          { order_by => 'descrip' },
                         );

1;
