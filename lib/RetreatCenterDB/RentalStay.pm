use strict;
use warnings;
package RetreatCenterDB::RentalStay;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('rental_stay');
__PACKAGE__->add_columns(qw/
    id
    rental_id
    name
    house_id
    nights
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to('rental' => 'RetreatCenterDB::Rental', 'rental_id');
__PACKAGE__->belongs_to('house'  => 'RetreatCenterDB::House',  'house_id');

sub house_name {
    my ($self) = @_;
    my $hid = $self->house_id();
    if ($hid == 1000) {
        "OV";
    }
    elsif ($hid == 2000) {
        "COM";
    }
    else {
        $self->house->name();
    }
}

sub house_code {
    my ($self) = @_;
    my $hid = $self->house_id();
    if ($hid == 1000) {
        return "";
    }
    elsif ($hid == 2000) {
        return "";
    }
    else {
        my $house = $self->house;
        if ($house->bath()) {
            return "B";
        }
        elsif ($house->tent()) {
            return ($house->center()? "CT": "OT");
        }
    }
}

sub arr_nights {
    my ($self) = @_;
    return split m{\s*,\s*}, $self->nights();
    # soon - return split m{}, $self->nights();
}

1;
