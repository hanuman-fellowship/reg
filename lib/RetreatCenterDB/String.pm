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
    my $k = $self->the_key();
    my $v = $self->value() || "";
    if ($k =~ m{_color$}) {
        my $color = sprintf "#%02x%02x%02x", $v =~ m{\d+}g;
        #return "<td><span style='background: $color'>"
        #      . "&nbsp;" x 30
        #      . "</span></td>";
        return <<"EOH";
<td style="cursor: pointer; border: solid; border-width: thin;"
 width=100 bgcolor=$color
 onclick="window.location.href='/string/update/$k'"
>
EOH
    }
    return "<td>$v</td>";
}

1;
