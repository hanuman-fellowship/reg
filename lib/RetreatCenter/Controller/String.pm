use strict;
use warnings;
use lib '../../';

package RetreatCenter::Controller::String;
use base 'Catalyst::Controller';
use RetreatCenterDB::String;

use Global qw/
    %string
/;
use Util qw/
    model
    stash
    error
    empty
    time_travel_class
    set_cache_timestamp
    get_string
    put_string
    read_only
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
                the_key => { '!=' => 'tt_today' },
                the_key => { '-not_like' => 'badge_%' },
                the_key => { '-not_like' => 'sys_%' },
                # for meal requests:
                the_key => { '-not_like' => 'breakfast_cost%' },
                the_key => { '-not_like' => 'lunch_cost%' },
                the_key => { '-not_like' => 'dinner_cost%' },
                the_key => { '-not_like' => '%daily_max%' },
                the_key => { '-not_like' => '%while_here%' },
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

    if (read_only()) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
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
    set_cache_timestamp($c);
    $string{$the_key} = $value;
    if ($the_key eq 'default_date_format') {
        Date::Simple->default_format($value);
    }
    elsif ($the_key eq 'housing_log') {
        hlog_toggle($c, $value);
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

sub access_denied : Private {
    my ($self, $c) = @_;

    $c->stash->{mess}  = "Authorization denied!";
    $c->stash->{template} = "gen_error.tt2";
}

sub time_travel : Local {
    my ($self, $c) = @_;

    if (read_only()) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
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
        $date_for{$user} = date($new_date)->format('%m/%d/%Y');;
    }
    $str->update({
        value => join ' ', %date_for,
    });
    $c->forward('/person/search');
}

sub while_here : Local {
    my ($self, $c) = @_;

    if (read_only()) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
    stash($c,
        while_here => get_string($c, 'while_here'),
        template => 'string/while_here.tt2',
    );
}

sub while_here_do : Local {
    my ($self, $c) = @_;
    my $while_here = $c->request->params->{while_here};
    put_string($c, 'while_here', $while_here);
    $c->forward('/configuration/index');
}

sub badge_settings : Local {
    my ($self, $c) = @_;

    if (read_only()) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
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

sub meal_requests : Local {
    my ($self, $c) = @_;

    stash($c,
        S        => \%string,
        template => 'configuration/meal_requests.tt2',
    );
}

sub meal_requests_update : Local {
    my ($self, $c) = @_;

    if (read_only()) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
    stash($c,
        S        => \%string,
        template => 'configuration/meal_requests_update.tt2',
    );
}

sub meal_requests_update_do : Local {
    my ($self, $c) = @_;

    my $changed = 0;
    my %P = %{ $c->request->params() };
    for my $k (keys %P) {
        if ($P{$k} ne $string{$k}) {
            put_string($c, $k, $P{$k});
            $string{$k} = $P{$k};
            $changed = 1;
        }
    }
    if ($changed) {
        set_cache_timestamp($c);
    }
    $c->forward("/string/meal_requests");
}

1;
