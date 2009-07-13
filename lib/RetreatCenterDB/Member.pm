use strict;
use warnings;
package RetreatCenterDB::Member;
use base qw/DBIx::Class/;

use Date::Simple qw/
    date
    today
/;

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
    total_paid
    cc_number
    cc_expire
    cc_code
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to('person' => 'RetreatCenterDB::Person', 'person_id');

# sponsor history payments - maybe
__PACKAGE__->has_many('payments' => 'RetreatCenterDB::SponsHist', 'member_id',
                      { order_by => 'date_payment desc, time desc' },
                     );
__PACKAGE__->has_many('nighthist' => 'RetreatCenterDB::NightHist', 'member_id',
                      { order_by => 'the_date desc, time desc, id desc' },
                      #  need id as well in case the date/time is the same...
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
sub lapsed {
    my ($self) = @_;
    my $today = today()->as_d8();       # can't use tt_today - no $c :(
    if (($self->category eq 'General' && $self->date_general < $today)
        ||
        ($self->category eq 'Sponsor' && $self->date_sponsor < $today)
    ) {
        return "Lapsed";
    }
    else {
        return "";
    }
}
my %index = (
    General  => 1,
    Sponsor  => 2,
    Life     => 3,
    Inactive => 4,
);
sub category_id {
    my ($self) = @_;
    return $index{$self->category()};
}

sub cc_number1 { substr(shift->cc_number(),  0, 4) }
sub cc_number2 { substr(shift->cc_number(),  4, 4) }
sub cc_number3 { substr(shift->cc_number(),  8, 4) }
sub cc_number4 { substr(shift->cc_number(), 12, 4) }

1;
