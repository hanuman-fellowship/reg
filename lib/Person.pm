use strict;
use warnings;
package Person;

use DBH;

sub new {
    my ($class, $h_ref) = @_;
    bless $h_ref, $class;
}

#
# the sql must do a search on the People table
# and return all columns.  the return from this
# function is an array ref of Person objects.
#
# we COULD not bless them and just return
# an array of hashrefs.   would no longer be
# able to call methods - like address() below.
#
sub search {
    my ($class, $sql) = @_;

    my $sth = $dbh->prepare($sql) or die "cannot prepare $sql: $DBI::errstr";
    $sth->execute() or die "cannot execute";
    my $a_ref = $sth->fetchall_arrayref({});
    for my $p (@{$a_ref}) {
        $p = Person->new($p);
    }
    return $a_ref;
}

#
# take the SQL and make a statement handle that you
# can use in search_next to return the next Person.
#
sub search_start {
    my ($class, $sql) = @_;

    my $search_sth = $dbh->prepare($sql)
        or die "cannot prepare $sql: $DBI::errstr";
    $search_sth->execute()
        or die "cannot execute";
    return $search_sth;
}

#
# this will return an undefined value in
# case we are at the end of the search results.
#
sub search_next {
    my ($class, $search_sth) = @_;

    my $href = $search_sth->fetchrow_hashref();
    return unless $href;
    return bless $href, $class;
}

sub address {
    my ($self) = @_;
    my $addr = $self->{addr1};
    $addr .= " " . $self->{addr2} if $self->{addr2};
    if ($addr) {
        $addr .= ", $self->{city}" if $self->{city};
        $addr .= ", $self->{st_prov} $self->{zip_post}" if $self->{st_prov};
        $addr .= " $self->{country}" if $self->{country};
    }
    $addr;
}

sub addrs {
    my ($self) = @_;
    my $addr = $self->{addr1};
    $addr .= " " . $self->{addr2} if $self->{addr2};
    $addr;
}

our $AUTOLOAD;
sub AUTOLOAD {
    my ($self) = @_;
    my $field = $AUTOLOAD;
    $field =~ s{.*:}{};
    return if $field eq "DESTROY";
    if (! exists $self->{$field}) {
        die "no such field in Person: $field\n";
    }
    return $self->{$field};
}

1;
