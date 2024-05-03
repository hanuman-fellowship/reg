use strict;
use warnings;
package RetreatCenterDB::HousingType;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('housing_type');
__PACKAGE__->add_columns(qw/
    name
    ht_order
    short_desc
    long_desc
/);
__PACKAGE__->set_primary_key(qw/name/);

sub short_desc_with_br {
    my ($self) = @_;
    my $s = $self->short_desc;
    $s =~ s{\s*/\s*}{<br>}xmsg;
    $s;
}

sub pics {
    my ($self) = @_;
    my $name = $self->name;
    my $dir = '/var/www/src/root/static/images';
    my $html = '';
    for my $i (1 .. 4) {
        if (-f "$dir/$name$i.jpg") {
            $html .= "<img src=/static/images/$name$i.jpg width=200>";
            $html .= $i % 2? '&nbsp;': '<p>';
        }
    }
    return $html;
}

1;
__END__
overview - Housing types - from 'own tent' to 'whole cottage'
ht_order - what order to present the housing types in
long_desc - a long (however long you wish) description
name - brief internal name of the type
short_desc - a short succinct description
