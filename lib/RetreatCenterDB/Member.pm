use strict;
use warnings;
package RetreatCenterDB::Member;
use base qw/DBIx::Class/;

use Date::Simple qw/date/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('member');
__PACKAGE__->add_columns(qw/
    id
    category
    person_id
    date_general
    date_sponsor
    sponsor_nights
    date_life
    free_prog_taken
    date_lapsed
    total_paid
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to('person' => 'RetreatCenterDB::Person', 'person_id');

# sponsor history payments - maybe
__PACKAGE__->has_many('payments' => 'RetreatCenterDB::SponsHist', 'member_id',
                      { order_by => 'date_payment desc' },
                     );

sub date_general_obj {
    my ($self) = @_;
    date($self->date_general) || "";
}
sub date_sponsor_obj {
    my ($self) = @_;
    date($self->date_sponsor) || "";
}
sub date_life_obj {
    my ($self) = @_;
    date($self->date_life) || "";
}
sub date_lapsed_obj {
    my ($self) = @_;
    date($self->date_lapsed) || "";
}

1;
