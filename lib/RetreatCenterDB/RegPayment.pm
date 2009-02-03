use strict;
use warnings;
package RetreatCenterDB::RegPayment;
use base qw/DBIx::Class/;

use Date::Simple qw/date/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('reg_payment');
__PACKAGE__->add_columns(qw/
    id
    reg_id
    user_id
    the_date
    time
    amount
    type
    what
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to('registration' => 'RetreatCenterDB::Registration', 'reg_id');
__PACKAGE__->belongs_to('user' => 'RetreatCenterDB::User', 'user_id');

sub the_date_obj {
    my ($self) = @_;
    return date($self->the_date);
}

sub name {
    my ($self) = @_;
    my $per = $self->registration->person;
    return $per->last . ", " . $per->first;
}

sub link {
    my ($self) = @_;
    return "/registration/view/" . $self->reg_id;
}

sub pname {
    my ($self) = @_;
    return $self->registration->program->name();
}

sub glnum {
    my ($self) = @_;
    return $self->registration->program->glnum();
}

1;
