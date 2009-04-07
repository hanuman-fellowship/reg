use strict;
use warnings;
package RetreatCenterDB::RegPayment;
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
sub time_obj {
    my ($self) = @_;
    return get_time($self->time());
}

sub name {
    my ($self) = @_;
    my $per = $self->registration->person;
    return $per->last . ", " . $per->first;
}

sub link {
    my ($self) = @_;
    return "/registration/view/" . $self->reg_id();
}

sub plink {
    my ($self) = @_;
    return "/program/view/" . $self->registration->program_id();
}

sub pname {
    my ($self) = @_;
    return $self->registration->program->name();
}

sub glnum {
    my ($self) = @_;
    return $self->registration->program->glnum();
}

sub type_sh {
    my ($self) = @_;
    return $string{"payment_" . $self->type() };
}

1;
