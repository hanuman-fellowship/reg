use strict;
use warnings;
package RetreatCenterDB::Member;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('member');
__PACKAGE__->add_columns(qw/
    id
    category
    person_id
    date_general
    date_sponsor
    date_life
    date_lapsed
    total_paid
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to('person' => 'RetreatCenterDB::Person', 'person_id');

# ??? there's likely some way to put here the relationship to spons_hist???
# so given a member can get the spons_hist records?

1;
