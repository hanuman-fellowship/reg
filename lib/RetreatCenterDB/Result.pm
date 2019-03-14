use strict;
use warnings;

package RetreatCenterDB::Result;

use base 'DBIx::Class::Core';
use Time::Simple qw/
    get_time
/;
use Date::Simple qw/
    date
/;

sub register_column {
    my $self = shift;
    my ($column, $info, $args) = @_;

    $self->next::method(@_);

    if ($info->{time_simple}) {
        $self->inflate_column(
            $column => {
                inflate => sub {
                    my ($raw_value_from_db, $result_object) = @_;
                    return $self->_get_as_time_obj($raw_value_from_db);

                },
                deflate => sub {
                    my ($inflated_value_from_user, $result_object) = @_;
                    return $inflated_value_from_user->t24;
                },
            }
        );
    } elsif ($info->{date_simple}) {
        $self->inflate_column(
            $column => {
                inflate => sub {
                    my ($raw_value_from_db, $result_object) = @_;
                    return $self->_get_as_date_obj($raw_value_from_db);
                },
                deflate => sub {
                    my ($inflated_value_from_user, $result_object) = @_;
                    return $inflated_value_from_user->d8;
                },
            }
      );
    }

    return;
}

sub _get_as_time_obj {
    my ($self, $time_string) = @_;
    my $time_obj = get_time($time_string);
    if(!$time_obj) {
        die "The string $time_string cannot be parsed into a Time::Simple object";
    }
    return $time_obj;
}

sub _get_as_date_obj {
    my ($self, $date_string) = @_;
    my $date_obj = date($date_string);
    if(!$date_obj) {
        die "The string $date_string cannot be parsed into a Date::Simple object";
    }
    return $date_obj;
}

1;

