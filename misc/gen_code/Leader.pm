#!/local/bin/perl -w
package Leader;
use strict;
use Util qw/expand/;

my %field = map { $_, 1 } qw/
    id last first puemail web image bio
/;
my %leaders;    # look up a leader given their id number

BEGIN {
    open IN, "leaders.tmp" or die "cannot open leaders.tmp: $!\n";
    my %hash;
    while (<IN>) {
        s/\cM\n//;
        my ($k, $v) = split /\t/;
        $v =~ s/^\s*|\s*$//g;
        if ($v eq "-") {
            $v = "";
            while (<IN>) {
                s/\cM\n//;
                last if $_ eq ".";
                $v .= "$_\n";
            }
        }
		#
		# various transformations
		#
        $v =~ s/(\w+)/\L\u$1/g if $k =~ /first|last/;   # make mixed case
		$v = expand($v) if $k eq "bio";
		$v =~ s#^\s*http://## if $k eq "web";	# remove any http://

        $hash{$k} = $v;
		#
		# the bio field is the last one
		#
        if ($k eq "bio") {
            $leaders{$hash{id}} = bless { %hash };
            %hash = ();
        }
    }
    close IN;
}

sub get {
    my ($pkg, $id) = @_;
    return $leaders{$id};
}

use vars '$AUTOLOAD';
sub AUTOLOAD {
    my ($self) = @_;
    $AUTOLOAD =~ s/.*:://;
    return if $AUTOLOAD eq "DESTROY";
    die "unknown leader field: $AUTOLOAD\n"
        unless exists $field{$AUTOLOAD};
    return $self->{$AUTOLOAD};
}

1;
