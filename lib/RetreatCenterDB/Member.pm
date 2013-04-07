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
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to(person => 'RetreatCenterDB::Person', 'person_id');

# sponsor history payments - maybe
__PACKAGE__->has_many(payments => 'RetreatCenterDB::SponsHist', 'member_id',
                      { order_by => 'date_payment desc, time desc' },
                     );
__PACKAGE__->has_many(nighthist => 'RetreatCenterDB::NightHist', 'member_id',
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
    if (($self->category() eq 'General' && $self->date_general() < $today)
        ||
        ($self->category() eq 'Sponsor' && $self->date_sponsor() < $today)
    ) {
        return "Lapsed";
    }
    else {
        return "";
    }
}
my %index = (
    General                => 1,
    'Contributing Sponsor' => 2,
    Sponsor                => 3,
    Life                   => 4,
    'Founding Life'        => 5,
    Inactive               => 6,
);
sub category_id {
    my ($self) = @_;
    return $index{$self->category()};
}

1;
__END__
overview - People can become Members of the Hanuman Fellowship by paying dues.
category - General, Contributing Sponsor, Sponsor, Life, Founding Life, or Inactive.
date_general - date the General membership will expire
date_life - date the Life membership began - apparently no longer used
date_sponsor - date the Sponsor membership will expire
free_prog_taken - was this year's free program taken?
id - unique id
person_id - foreign key to person
sponsor_nights - how many sponsor free nights remain?
total_paid - total dollars paid towards a sponsor membership
