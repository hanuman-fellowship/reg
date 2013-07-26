use strict;
use warnings;
package RetreatCenterDB::Report;
use base qw/DBIx::Class/;

use lib "..";       # so can do perl -c
use Date::Simple qw/
    date
/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('reports');
__PACKAGE__->add_columns(qw/
    id
    descrip
    format
    zip_range
    rep_order
    nrecs
    update_cutoff
    end_update_cutoff
    last_run
/);
__PACKAGE__->set_primary_key(qw/id/);
__PACKAGE__->has_many(affil_report => 'RetreatCenterDB::AffilReport', 'report_id');
__PACKAGE__->many_to_many(affils => 'affil_report', 'affil');

sub update_cutoff_obj {
    my ($self) = @_;
    date($self->update_cutoff) || "";
}
sub end_update_cutoff_obj {
    my ($self) = @_;
    date($self->end_update_cutoff) || "";
}
sub last_run_obj {
    my ($self) = @_;
    date($self->last_run) || "";
}
sub update_cutoff_range {
    my ($self) = @_;
    my $s = '';
    if ($self->update_cutoff) {
        $s = date($self->update_cutoff)->format("%D");
        if ($self->end_update_cutoff) {
            $s .= " to " . date($self->end_update_cutoff)->format("%D");
        }
    }
    return $s;
}

1;
__END__
overview - Reports are used to select a subset of People for mailing list purposes.
    The selection is based on zip code and affiliation.
    A variety of formats can be generated - including snail mail address and or email address.
descrip - an identifier for the report
end_update_cutoff - on or before what date of last update should people be included in the report.
    defaults to 'today'.
format - 10 different ones
id - unique id
last_run - last date this report was run
nrecs - how many records do you want?  a random selection will be made for you
    to achieve this many.
rep_order - what order should the people records be in?  Zip Code or Last Name
update_cutoff - on or after what date of last update should people be included in the report
zip_range - a free text field describing a zip code range - like "95060, 94050-94090"
