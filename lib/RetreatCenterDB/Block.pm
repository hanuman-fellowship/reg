use strict;
use warnings;
package RetreatCenterDB::Block;
use base qw/DBIx::Class/;

use Date::Simple qw/
    date
/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('block');
__PACKAGE__->add_columns(qw/
    id
    house_id
    sdate
    edate
    nbeds
    reason
/);
__PACKAGE__->set_primary_key(qw/
    id
/);

__PACKAGE__->belongs_to('house' => 'RetreatCenterDB::House', 'house_id');

sub sdate_obj {
    my ($self) = @_;
    return date($self->sdate) || "";
}

sub edate_obj {
    my ($self) = @_;
    return date($self->edate) || "";
}

1;
