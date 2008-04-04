package RetreatCenter::Model::RetreatCenterDB;

use strict;
use base 'Catalyst::Model::DBIC::Schema';

__PACKAGE__->config(
    schema_class => 'RetreatCenterDB',
    connect_info => [
        undef,
        'sahadev',
        'JonB',
        { AutoCommit => 1 },
        
    ],
);

=head1 NAME

RetreatCenter::Model::RetreatCenterDB - Catalyst DBIC Schema Model
=head1 SYNOPSIS

See L<RetreatCenter>

=head1 DESCRIPTION

L<Catalyst::Model::DBIC::Schema> Model using schema L<RetreatCenterDB>

=head1 AUTHOR

Jon Bjornstad

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
