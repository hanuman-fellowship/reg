use strict;
use warnings;
package RetreatCenterDB::Meal;
use base qw/DBIx::Class/;

use Util qw/
    ptrim
/;
use Date::Simple qw/
    date
/;
use Time::Simple qw/
    get_time
/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('meal');
__PACKAGE__->add_columns(qw/
    id
    sdate
    edate
    breakfast
    lunch
    dinner
    comment
    user_id
    the_date
    time
/);
__PACKAGE__->set_primary_key(qw/
    id
/);

__PACKAGE__->belongs_to(user    => 'RetreatCenterDB::User',  'user_id');

sub sdate_obj {
    my ($self) = @_;
    return date($self->sdate()) || "";
}
sub edate_obj {
    my ($self) = @_;
    return date($self->edate()) || "";
}
sub the_date_obj {
    my ($self) = @_;
    return date($self->the_date()) || "";
}
sub time_obj {
    my ($self) = @_;
    return get_time($self->time()) || "";
}
sub comment_tr {
    my ($self) = @_;
    return ptrim($self->comment());
}

1;
__END__
overview - Meals reserve a meal for a given number for breakfast, lunch or dinner in a date range.
    The meal list understands this.
breakfast - how many for breakfast?
comment - a long reason
dinner - how many for dinner?
edate - end date
id - unique id
lunch - how many for lunch?
sdate - start date
the_date - when was this block created?
time - what time was this block created?
user_id - foreign key to user
