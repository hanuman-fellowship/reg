use strict;
use warnings;

package RetreatCenter::Controller::String;
use base 'Catalyst::Controller';
use RetreatCenterDB::String;

use Global qw/
    %string
/;
use Util qw/
    resize
    model
    stash
/;
use Date::Simple;
use HLog;

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c, $colors) = @_;

    my @colors = ();
    if ($colors) {
        push @colors, the_key => { -like => '%color%' };
    }
    else {
        push @colors, the_key => { -not_like => '%color%' };
    }
    $c->stash->{strings} = [ model($c, 'String')->search(
        { 
            the_key => { -not_like => 'sys_%' },
            @colors,
        },
        {
            order_by => 'the_key'
        },
    ) ];
    stash($c,
        doc_for  => RetreatCenterDB::String::doc_for(),
        colors   => $colors,
        template => "string/list.tt2",
    );
}

use URI::Escape;
sub update : Local {
    my ($self, $c, $the_key) = @_;

    my $s = model($c, 'String')->find($the_key);

    $c->stash->{the_key} = $the_key;
    my $value = $c->stash->{value} = uri_escape($s->value, '"');
    $c->stash->{form_action} = "update_do/$the_key";
    if ($the_key =~ m{_color$}) {
        my ($r, $g, $b) = $value =~ m{\d+}g;
        $c->stash->{red}   = $r;
        $c->stash->{green} = $g;
        $c->stash->{blue}  = $b;
        $c->stash->{template}    = "string/create_edit_color.tt2";
    }
    else {
        $c->stash->{template}    = "string/create_edit.tt2";
    }
}

sub update_do : Local {
    my ($self, $c, $the_key) = @_;

    my $value = uri_unescape($c->request->params->{value});
    model($c, 'String')->find($the_key)->update({
        value => $value,
    });
    $string{$the_key} = $value;
    if ($the_key =~ m{imgwidth} && $c->request->params->{resize_all}) {
        for my $f (<root/static/images/*o-*.jpg>) {
            my ($type, $id) = $f =~ m{/(\w+)o-(\d+).jpg$};
            resize($type, $id, $the_key);
        }
    }
    if ($the_key eq 'default_date_format') {
        Date::Simple->default_format($value);
    }
    elsif ($the_key eq 'housing_log') {
        hlog_toggle($c, $value);
    }
    elsif ($the_key =~ m{^center_tent_}) {
        _update_CT();
    }
    elsif ($the_key eq 'online_notify') {
        # need to send this string up to mountmadonna.org
        BLOCK: {
        open my $out, '>', '/tmp/online_notify.txt' or last BLOCK;
        print {$out} "$value\n";
        close $out;
        my $ftp = Net::FTP->new($string{ftp_site},
                                Passive => $string{ftp_passive}) or last BLOCK;
        $ftp->login($string{ftp_login}, $string{ftp_password})   or last BLOCK;
        $ftp->cwd("www/cgi-bin") or last BLOCK;
        $ftp->ascii()            or last BLOCK;
        $ftp->put("/tmp/online_notify.txt", "online_notify.txt") or last BLOCK;
        $ftp->quit();
        unlink "/tmp/online_notify.txt";
        }
    }
    #
    # and where to go next?
    #
    if ($the_key =~ m{color}) {
        $c->response->redirect($c->uri_for("/string/list/1/#$the_key"));
    }
    else {
        $c->response->redirect($c->uri_for("/string/list#$the_key"));
    }
}

# we need to update the www.mountmadonna.org/personal/CT.txt file
#
sub _update_CT {
    open my $ct, ">", "/tmp/CT.txt" or return;
    print {$ct} "$string{center_tent_start}-$string{center_tent_end}\n";
    close $ct;
    my $ftp = Net::FTP->new($string{ftp_site},
                            Passive => $string{ftp_passive}) or return;;
    $ftp->login($string{ftp_login}, $string{ftp_password}) or return;
    $ftp->cwd("www/personal") or return;
    $ftp->ascii() or return;
    $ftp->put("/tmp/CT.txt", "CT.txt") or return;
    $ftp->quit();
    unlink "/tmp/CT.txt";
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

1;
