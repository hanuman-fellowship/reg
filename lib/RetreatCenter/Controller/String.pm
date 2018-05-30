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
    error
    empty
    time_travel_class
/;
use Date::Simple qw/
    date
/;
use HLog;

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('list');
}

sub list : Local {
    my ($self, $c, $colors) = @_;

    $c->stash->{strings} = [ model($c, 'String')->search(
        { 
            -and => [
                the_key => { ($colors? '-like': '-not_like') => '%color%' },
                the_key => { '!=' => 'sys_last_config_date' },
                the_key => { '!=' => 'tt_today' },
                the_key => { '-not_like' => 'badge_%' },
            ]
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
    $c->stash->{type} = $the_key =~ m{_password}? 'password'
                       :                          'text'
                       ;
    my $value = $c->stash->{value} = uri_escape($s->value, '"');
    my $doc = RetreatCenterDB::String::doc_for()->{$the_key};
    $doc =~ s{\\}{}xmsg;
    $c->stash->{doc} = $doc;
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
    elsif ($the_key eq 'pr_max_nights') {
        _update_max_nights();
    }
    elsif ($the_key eq 'online_notify') {
        # need to send this string up to mountmadonna.org
        BLOCK: {
        open my $out, '>', '/tmp/online_notify.txt'
            or last BLOCK;
        print {$out} "$value\n";
        close $out;
        # MMC
        my $ftp = Net::FTP->new($string{ftp_site},
                                Passive => $string{ftp_passive})
            or last BLOCK;
        $ftp->login($string{ftp_login}, $string{ftp_password})
            or last BLOCK;
        $ftp->cwd($string{ftp_notify_dir})
            or last BLOCK;
        $ftp->ascii()
            or last BLOCK;
        $ftp->put("/tmp/online_notify.txt", "online_notify.txt")
            or last BLOCK;
        $ftp->quit();
        # MMI
        $ftp = Net::FTP->new($string{ftp_mmi_site},
                             Passive => $string{ftp_mmi_passive})
            or last BLOCK;
        $ftp->login($string{ftp_mmi_login}, $string{ftp_mmi_password})
            or last BLOCK;
        $ftp->cwd($string{ftp_notify_dir})
            or last BLOCK;
        $ftp->ascii()
            or last BLOCK;
        $ftp->put("/tmp/online_notify.txt", "online_notify.txt")
            or last BLOCK;
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

# we need to update the www.mountmadonna.org/pr/CT.txt file
#
sub _update_CT {
    my $fn = '/tmp/CT.txt';
    open my $ct, ">", $fn or return;
    print {$ct} "$string{center_tent_start}-$string{center_tent_end}\n";
    close $ct;
    my $ftp = Net::FTP->new($string{ftp_site},
                            Passive => $string{ftp_passive}) or return;
    $ftp->login($string{ftp_login}, $string{ftp_password}) or return;
    $ftp->cwd($string{ftp_pr_dir}) or return;
    $ftp->ascii() or return;
    $ftp->put($fn, "CT.txt") or return;
    $ftp->quit();
    unlink $fn;
}

# we need to update the www.mountmadonna.org/pr/max_nights.txt file
#
sub _update_max_nights {
    my $fn = '/tmp/max_nights.txt';
    open my $mn, ">", $fn or return;
    print {$mn} "$string{pr_max_nights}\n";
    close $mn;
    my $ftp = Net::FTP->new($string{ftp_site},
                            Passive => $string{ftp_passive}) or return;
    $ftp->login($string{ftp_login}, $string{ftp_password}) or return;
    $ftp->cwd($string{ftp_pr_dir}) or return;
    $ftp->ascii() or return;
    $ftp->put($fn, "max_nights.txt") or return;
    $ftp->quit();
    unlink $fn;
}

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

sub time_travel : Local {
    my ($self, $c) = @_;

    my ($str) = model($c, 'String')->search({
        the_key => 'tt_today',
    });
    my %date_for = $str->value() =~ m{(\w+) \s+ (\d+/\d+/\d+)}xmsg;
    my $user = $c->user->username();
    stash($c,
        time_travel_class($c),
        user => $user,
        date => $date_for{$user},
        template => 'string/time_travel.tt2',
    );
}

sub time_travel_do : Local {
    my ($self, $c) = @_;
    my ($str) = model($c, 'String')->search({
        the_key => 'tt_today',
    });
    my %date_for = $str->value() =~ m{(\w+) \s+ (\d+/\d+/\d+)}xmsg;
    my $user = $c->user->username();
    my $new_date = $c->request->params->{date};
    if (empty($new_date)) {
        delete $date_for{$user};
    }
    elsif (! date($new_date)) {
        error($c,
            "Invalid date: $new_date",
            'gen_error.tt2',
        );
        return;
    }
    else {
        $date_for{$user} = $new_date;
    }
    $str->update({
        value => join ' ', %date_for,
    });
    $c->forward('/person/search');
}

sub badge_settings : Local {
    my ($self, $c) = @_;
    my @badge_strs = model($c, 'String')->search({
                         the_key => { 'like' => 'badge_%' },
                     });
    my %hash;
    for my $bs (@badge_strs) {
        my $key = $bs->the_key();
        $key =~ s{\A badge_}{}xms;
        $hash{$key} = $bs->value();
    }
    stash($c,
        %hash,
        template => 'configuration/badge_settings.tt2',
    );
}

sub badge_settings_do : Local {
    my ($self, $c) = @_;
    my %P = %{ $c->request->params() };
    for my $k (keys %P) {
        my $bk = "badge_$k";
        model($c, 'String')->search({
            the_key => $bk,
        })->update({value => $P{$k}});
    }
    $c->forward('/rental/badge');
}
1;
