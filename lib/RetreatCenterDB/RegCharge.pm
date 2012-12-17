use strict;
use warnings;
package RetreatCenterDB::RegCharge;
use base qw/DBIx::Class/;

use Date::Simple qw/
    date
/;
use Time::Simple qw/
    get_time
/;
use Util qw/
    penny
/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('reg_charge');
__PACKAGE__->add_columns(qw/
    id
    reg_id
    user_id
    the_date
    time
    amount
    what
    automatic
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to(registration => 'RetreatCenterDB::Registration', 'reg_id');
__PACKAGE__->belongs_to(user => 'RetreatCenterDB::User', 'user_id');

sub the_date_obj {
    my ($self) = @_;
    return date($self->the_date);
}
sub time_obj {
    my ($self) = @_;
    return get_time($self->time());
}
sub amount_disp {
    my ($self) = @_;
    penny($self->amount());
}

1;
__END__
overview - charges for a registration are recorded in these records
amount - dollar amount
automatic - was this charge a result of an automatic calculation?
id - unique id
reg_id - foreign key to registration
the_date - what day was this charge added?
time - what time was the charge added?
user_id - foreign key to user - the person who added it
what - a brief description of the charge
