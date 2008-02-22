use strict;
use warnings;
package RetreatCenterDB::Rental;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('rental');
__PACKAGE__->add_columns(qw/
    id
    name
    title
    subtitle
    glnum
    sdate
    edate
    url
    webdesc
    linked
    phone
    email
/);
# Set the primary key for the table
__PACKAGE__->set_primary_key(qw/id/);

use Lookup;
use Util qw/expand/;
use Date::Simple qw/date today/;

sub future_rentals {
    my ($class, $c) = @_;
    my @rentals = $c->model('RetreatCenterDB::Rental')->search(
        { sdate    => { '>=',    today()->as_d8() } },
        { order_by => [ 'sdate', 'edate' ] },
    );
    @rentals;
}
sub sdate_obj {
    my ($self) = @_;
    return date($self->sdate) || "";
}
sub edate_obj {
    my ($self) = @_;
    return date($self->edate) || "";
}
sub webdesc_br {
    my ($self) = @_;
    my $webdesc = $self->webdesc;
    $webdesc =~ s{\r?\n}{<br>\n}g;
    $webdesc;
}
sub extradays {     # see Program->dates()
    return 0;
}
sub desc {
	my ($self) = @_;
	my $desc = expand($self->webdesc);
	return "" unless $desc;
	"<span class='event_desc'>$desc</span><br>";
}
sub weburl {
    my ($self) = @_;
    my $url = $self->url;
    return "" unless $url;
    return "<span class='event_website'>$lookup{website}: <a href='http://$url' target='_blank'>$url</a></span><br>";
}
sub email_str {
	my ($self) = @_;
	my $email = $self->email;
	return "" unless $email;
	return "<span class='event_email'>$lookup{email}: ".
		   "<a href='mailto:$email'>$email</a></span><br>";
}
sub phone_str {
	my ($self) = @_;
	my $phone = $self->phone;
	return "" unless $phone;
	"<span class='event_phone'>$lookup{phone}: $phone</span><br>";
}
sub title1 {
    my ($self) = @_;
    my $title = $self->title;
    my $url = $self->url;
    $title = "<a href='http://$url' target=_blank>$title</a>" if $url;
    $title;
}
sub title2 {
    my ($self) = @_;
    my $subtitle = $self->subtitle;
    return "" unless $subtitle;
    "<span class='event_subtitle'>$subtitle</span><br>";
}
#
# invoke the Program method by the same name.
# Rentals also have sdate and edate methods.
# no extradays but that's okay.
#
sub dates {
	my ($self) = @_;
	return RetreatCenterDB::Program::dates($self);
}
sub dates_tr {
	my ($self) = @_;
	return RetreatCenterDB::Program::dates_tr($self);
}
sub dates_tr2 {
	my ($self) = @_;
	return RetreatCenterDB::Program::dates_tr2($self);
}

1;
