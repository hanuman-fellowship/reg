use strict;
use warnings;
package RetreatCenterDB::String;

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('string');
__PACKAGE__->add_columns(qw/
    the_key
    value
/);

__PACKAGE__->set_primary_key('the_key');

sub value_td {
    my ($self) = @_;
    my $v = $self->value;
    if ($self->the_key =~ m{_color}) {
        my $color = sprintf "#%02x%02x%02x", $v =~ m{\d+}g;
        return "<td><span style='background: $color'>$v</span></td>";
    }
    return "<td>$v</td>";
}

1;
