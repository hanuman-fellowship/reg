#!/local/bin/perl -w
package Rental;
use strict;
use Date::Simple;
use Program;
use Lookup;
use Util qw/expand/;

my %field = map { $_, 1 } qw/
	rname sdate edate title subtitle desc phone website email linked
/;

my @rentals;

BEGIN {
	open IN, "rentals.tmp" or die "cannot open rentals.tmp: $!\n";
	#
	# we know they come in sdate order
	#
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
        if ($k =~ /date/) {
            my ($m, $d, $y) = split '/', $v;
            $hash{$k} = Date::Simple->new($y, $m, $d);
        } else {
			$v =~ s#http://## if $k eq "website";
            $hash{$k} = $v;
        }
		if ($k eq "linked") {
			push @rentals, bless { %hash };
			%hash = ();
		}
	}
	close IN;
}

#
# invoke the Program method by the same name.
# Rentals also have sdate and edate methods.
# no extdays but that's okay.
#
sub dates {
	my ($self) = @_;
	return Program::dates($self);
}
sub dates_tr {
	my ($self) = @_;
	return Program::dates_tr($self);
}
sub dates_tr2 {
	my ($self) = @_;
	return Program::dates_tr2($self);
}

sub title {
	my ($self) = @_;
	my $title = $self->title;
	my $website = $self->{"website"};
	$title = "<a href='http://$website' target=_blank>$title</a>" if $website;
	$title;
}
sub subtitle {
	my ($self) = @_;
	my $subtitle = $self->subtitle;
	return "" unless $subtitle;
	"<span class='event_subtitle'>$subtitle</span><br>";
}
sub desc {
	my ($self) = @_;
	my $desc = expand($self->desc);
	return "" unless $desc;
	"<span class='event_desc'>$desc</span><br>";
}
sub phone {
	my ($self) = @_;
	my $phone = $self->phone;
	return "" unless $phone;
	"<span class='event_phone'>$lookup{phone}: $phone</span><br>";
}
sub weburl {
	my ($self) = @_;
	my $website = $self->website;
	$website =~ s#http://##;
	return "" unless $website;
	"<span class='event_website'>$lookup{website}: ".
	"<a href='http://$website' target=_blank>$website</a></span><br>";
}
sub email {
	my ($self) = @_;
	my $email = $self->{"email"};
	return "" unless $email;
	return "<span class='event_email'>$lookup{email}: ".
		   "<a href='mailto:$email'>$email</a></span><br>";
}

sub rentals {
	return @rentals;
}

use vars '$AUTOLOAD';
sub AUTOLOAD {
	my ($self) = @_;
	$AUTOLOAD =~ s/.*:://;
	return if $AUTOLOAD eq "DESTROY";
	die "unknown rental field: $AUTOLOAD\n"
		unless exists $field{$AUTOLOAD};
	return $self->{$AUTOLOAD};
}

1;
