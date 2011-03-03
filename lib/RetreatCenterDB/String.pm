use strict;
use warnings;
package RetreatCenterDB::String;

use base qw/DBIx::Class/;

use Util qw/
    d3_to_hex
/;

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
    my $v = defined($self->value())? $self->value()
            :                        ""
            ;
    if ($k =~ m{_color$}) {
        my $color = d3_to_hex($v);
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
