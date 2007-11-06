use strict;
use warnings;
package RetreatCenter::Controller::Listing;
use base 'Catalyst::Controller';

# DOES NOT WORK - do not try!
# Joins???
sub phone : Local {
    my ($self, $c) = @_;

    # join with affils, affil_people and people
    # to find "Phone List" affil id, then join with Person
    # or find Phone List first, then join two???
    my (@affils) = $c->model('RetreatCenterDB::Affil')->search(
        {
            descrip => { 'like', 'phone list' }
        },
    );
    my @people = $c->model('RetreatCenterDB::Person')->search(
        {
            'affil_people.a_id' => $affils[0]->id(),
        },
        {
            join => [qw/affil_people/],
        }
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
