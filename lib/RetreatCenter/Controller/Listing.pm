use strict;
use warnings;
package RetreatCenter::Controller::Listing;
use base 'Catalyst::Controller';

sub phone : Local {
    my ($self, $c) = @_;

    # join with affils, affil_people and people
    # to find "Phone List" affil id, then join with Person
    # or find Phone List first, then join two???
    my $rs = $c->model('RetreatCenterDB::Person')->search(
        # join with affil_people where 
    );
    my $rows;
    $rows .= <<"EOH";
<tr bgcolor=#dddddd> <!-- or #ffffff -->
<td class="name">Abby</td>
<td class="name">Abby Reyes</td>
<td class="phone">&nbsp;&nbsp;510-847-7467</td>
<td class="phone">&nbsp;&nbsp;626-229-7189</td>
<td class="phone">&nbsp;&nbsp;</td>
<td class="address">&nbsp;&nbsp;1553 Posen Avenue, Berkeley, CA 94706</td>
</tr>
EOH
    $c->stash->{rows} = $rows;
    $c->stash->{template} = "listing/phone.tt2";
}

1;
