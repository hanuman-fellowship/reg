use strict;
use warnings;
package RetreatCenterDB::SponsHist;
use base qw/DBIx::Class/;

use Date::Simple qw/
    date
/;
use Time::Simple qw/
    get_time
/;
use Global qw/
    %string
/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('spons_hist');
__PACKAGE__->add_columns(qw/
    id
    member_id
    date_payment
    valid_from
    valid_to
    amount
    general
    user_id
    the_date
    time
    type
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to(member => 'RetreatCenterDB::Member', 'member_id');
__PACKAGE__->belongs_to(who    => 'RetreatCenterDB::User',   'user_id');

sub date_payment_obj {
    my ($self) = @_;
    date($self->date_payment) || "";
}
sub the_date_obj {
    my ($self) = @_;
    date($self->the_date) || "";
}
sub valid_from_obj {
    my ($self) = @_;
    date($self->valid_from) || "";
}
sub valid_to_obj {
    my ($self) = @_;
    date($self->valid_to) || "";
}
sub time_obj {
    my ($self) = @_;
    return get_time($self->time());
}
sub type_sh {
    my ($self) = @_;
    $string{"payment_" . $self->type()};
}


1;
__END__
overview - These records chronicle events in the life of a Sponsor member.
amount - dollar amount
date_payment - date the payment was made
general - was the payment for a general membership?
id - unique id
member_id - foreign key to member
the_date - date the event happened
time - time the event happened
type - type of payment - Credit (D), Cash (S), Check (C), Online (O)
user_id - foreign key to user - the one who created the event
valid_from - what date is the payment valid from?
valid_to - what date is the payment valid to?
