use strict;
use warnings;
package RetreatCenterDB::Program;
use base qw/DBIx::Class/;

# Load required DBIC stuff
__PACKAGE__->load_components(qw/PK::Auto Core/);
# Set the table name
__PACKAGE__->table('program');
# Set columns in table
__PACKAGE__->add_columns(qw/
    id
    name
    title
    subtitle
    glnum
    housecost_id
    retreat
    sdate
    edate
    tuition
    confnote
    url
    webdesc
    brdesc
    webready
    image
    kayakalpa
    canpol_id
    extradays
    full_tuition
    deposit
    collect_total
    linked
    ptemplate
    sbath
    quad
    economy
    footnotes
    school
    level
    phone
    email
/);
# Set the primary key for the table
__PACKAGE__->set_primary_key(qw/id/);

# relationships
__PACKAGE__->belongs_to(canpol => 'RetreatCenterDB::CanPol', 'canpol_id');
__PACKAGE__->belongs_to(housecost => 'RetreatCenterDB::HouseCost',
                        'housecost_id');

__PACKAGE__->has_many(affil_program => 'RetreatCenterDB::AffilProgram',
                      'p_id');
__PACKAGE__->many_to_many(affils => 'affil_program', 'affil',
                          { order_by => 'descrip' },
                         );

__PACKAGE__->has_many(leader_program => 'RetreatCenterDB::LeaderProgram',
                      'p_id');
__PACKAGE__->many_to_many(leaders => 'leader_program', 'leader');

sub fullname {
    my ($self) = @_;

    return  uc $self->name
          ." ".$self->title
          ." ".$self->subtitle
          ." ".$self->canpol->name
}

use Date::Simple qw/date/;
sub sdate_obj {
    my ($self) = @_;
    
    return date($self->sdate()) || "";
}

1;
