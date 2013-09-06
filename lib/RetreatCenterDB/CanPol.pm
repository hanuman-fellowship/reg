use strict;
use warnings;
package RetreatCenterDB::CanPol;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('canpol');
__PACKAGE__->add_columns(qw/
    id
    name
    policy
/);
__PACKAGE__->set_primary_key(qw/id/);

__PACKAGE__->has_many(programs => 'RetreatCenterDB::Program', 'canpol_id', 
                      { order_by => 'sdate desc' });

sub policy_br {
    my ($self) = @_;
    my $policy = $self->policy;
    $policy =~ s{\r?\n}{<br>\n}xmsg;
    $policy =~ s{(<p>[&]nbsp;</p>)* \z}{}xms;
        # the above is needed in case the user
        # hits Return at the end of the policy
        # one or more times.
    $policy;
}

1;
__END__
overview - What is the MMC policy for cancellation of a registration?  This
    can vary depending on the program.
id - unique id
name - policy name hopefully descriptive
policy - A full description of the policy.
