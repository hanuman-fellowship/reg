use strict;
use warnings;
package RetreatCenterDB::Credit;
use base qw/DBIx::Class/;

use Date::Simple qw/date/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('credit');
__PACKAGE__->add_columns(qw/
    id
    person_id
    reg_id
    date_given
    amount
    date_expires
    date_used
    used_reg_id
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->belongs_to('person' => 'RetreatCenterDB::Person', 'person_id');
__PACKAGE__->belongs_to('reg_given' => 'RetreatCenterDB::Registration',
                        'reg_id');
__PACKAGE__->belongs_to('reg_used' => 'RetreatCenterDB::Registration',
                        'used_reg_id');

sub date_given_obj {
    my ($self) = @_;
    date($self->date_given) || "";
}
sub date_expires_obj {
    my ($self) = @_;
    date($self->date_expires) || "";
}
sub date_used_obj {
    my ($self) = @_;
    date($self->date_used) || "";
}

1;
__END__
amount - 
date_expires - 
date_given - 
date_used - 
id - unique id
person_id - foreign key to person
reg_id - foreign key to registration
used_reg_id - foreign key to registration
