use strict;
use warnings;

package File::FTP;
use File::Copy 'copy';

our $trace = 1;
my $env = "FILE_FTP_DIR";
my $notice = 0;

sub new {
    my ($class) = @_;
    if (! exists $ENV{$env} || ! -d $ENV{$env}) {
        die "no ENV FILE_FTP_DIR\n";
    }
    print "using File::FTP\n" if $notice++ == 0;
    return bless {}, $class;
}

sub cwd {
    my ($self, $dir) = @_;
    $dir =~ s{ \A / }{}xms;
    $dir = "$ENV{FILE_FTP_DIR}/$dir";
    die "File::FTP - no dir $dir\n" if ! -d $dir;
    $self->{dir} = $dir;
    print "File::FTP cwd: $dir\n" if $trace;
    1;
}


sub ls {
    my ($self) = @_;
    my $dir = $self->{dir};
    die "File::FTP no dir\n" if ! $self->{dir};
    my @files = map { s{$dir/}{}xms; $_; } <$dir/*>;
    print "File::FTP ls: @files\n" if $trace;
    return @files;
}

sub get {
    my ($self, $src, $dest) = @_;
    print "File::FTP get: $src => $dest\n" if $trace;
    my $dir = $self->{dir};
    die "File::FTP no dir $dir\n" if ! $self->{dir};
    copy "$dir/$src", $dest
        or die "no copy $dir/$src to $dest\n";;
}

sub delete {
    my ($self, $file) = @_;
    die "File::FTP no dir\n" if ! $self->{dir};
    unlink $self->{dir} . "/$file";
    print "File::FTP delete: $file\n" if $trace;
}

# null methods
sub login { 1 }
sub message { 'no message - File::FTP' }
sub ascii { }
sub quit  { }

1;

__END__

=head1 NAME

File::FTP

=head1 SYNOPSIS
    
    Set this environment Variable: FILE_FTP_DIR=/tmp
    (better way??)
    Then:

    my $ftp = File::FTP->new();
    $ftp->cwd('/hello/bye');
    for my $f ($ftp->ls()) {
        # $f is just the base name
        # it does not have a /hello/bye directory prefix

        $ftp->get($f, "/tmp/$f");
        # process $f locally

        $ftp->delete($f);
    }

=head1 DESCRIPTION

A plug-in replacement for Net::FTP to do operations
on the local file system instead of a remote one.
