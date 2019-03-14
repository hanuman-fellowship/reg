package RetreatCenterDB::ResultSet::Activity;

use strict;
use warnings;
use base 'RetreatCenterDB::ResultSet';

sub by_date_of {
    my ($self, $cdate) = @_;
    $cdate = $cdate->as_d8() if ref($cdate); 
    return my $result_set = $self->search(
        {cdate => $cdate},
        {order_by => 'ctime ASC'}
    );
}
1;

