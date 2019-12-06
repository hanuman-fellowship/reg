use strict;
use warnings;
package RetreatCenter::Controller::Configuration;
use base 'Catalyst::Controller';

use Util qw/
    stash
    model
    time_travel_class
    tt_today
/;
use Time::Simple qw/
    get_time
/;
use File::Copy qw/
    copy
/;

use Global;
use File::stat;
my $words = "/var/Reg/words";

sub index : Local {
    my ($self, $c) = @_;

    stash($c,
        time_travel_class($c),
        pg_title => "Configuration",
        files_uploaded => $c->flash->{files_uploaded}||'',
        template => "configuration/index.tt2",
    );
}

sub mark_inactive : Local {
    my ($self, $c) = @_;

    my ($date_last) = $c->request->params->{date_last};
    my $dt = date($date_last);
    if (! $dt) {
        stash($c,
            mess     => "Invalid date: $date_last",
            template => 'listing/error.tt2',
        );
        return;
    }
    my $dt8 = $dt->as_d8();
    my $n = model($c, 'Person')->search({
        inactive => '',
        date_updat => { "<=", $dt8 },
    })->count();
    stash($c,
        date_last => $dt,
        count     => $n,
        template  => 'listing/inactive.tt2',
    );
}

sub mark_inactive_do : Local {
    my ($self, $c, $date_last) = @_;
}

sub counts : Local {
    my ($self, $c) = @_;

    my @classes = map {
                      +{
                          name  => $_,
                          count => scalar(model($c, $_)->search),
                                # scalar context gives the count
                      }
                  }
                  sort
                  @{RetreatCenterDB->classes()};
    stash($c,
        classes  => \@classes,
        template => 'configuration/counts.tt2',
    );
}

sub _get_words {
    my ($file, $aref) = @_;
    open my $in, '<', $file;
    @$aref = <$in>;
    close $in;
    chomp @$aref;
}

sub spellings : Local {
    my ($self, $c, $reg_id) = @_;
    my (@okay, @maybe);
    _get_words("$words/okaywords.txt",  \@okay);
    _get_words("$words/maybewords.txt", \@maybe);
    stash($c,
        reg_id   => $reg_id,
        okay     => \@okay,
        maybe    => \@maybe,
        template => 'configuration/spellings.tt2',
    );
}
sub spellings_do : Local {
    my ($self, $c, $reg_id) = @_;

    my %P = %{ $c->request->params() };
    my (@okay, %not_okay);
    _get_words("$words/okaywords.txt", \@okay);
    for my $k (sort keys %P) {
        my ($type, $w) = $k =~ m{ \A (maybe|okay)_(\S+) \z }xms;
        if ($type eq 'maybe') {
            push @okay, $w;
        }
        else {
            $not_okay{$w} = 1;
        }
    }
    open my $out, '>', "$words/okaywords.txt";
    # need to sort case insensitively
    for my $w (
        map { $_->[0] } 
        sort { $a->[1] cmp $b->[1] }
        map { [ $_, lc $_ ] }
        @okay
    ) {
        print {$out} "$w\n" unless exists $not_okay{$w};
    }
    close $out;
    open my $empty, '>', "$words/maybewords.txt";
    close $empty;
    $c->response->redirect("/registration/view/$reg_id");
}

#
# for updating these few special 'fixed' documents:
#
# CURRENT INFO SHEET.doc
# MMC_Guest_Packet.pdf
# Kaya Kalpa Brochure.pdf
# Rental Guest Confirmation Letter.doc
# Main Area Map 2014.pdf
# Rental Registration Guidelines.pdf
# MMC Food.doc
#
sub documents : Local {
    my ($self, $c) = @_;
    stash($c,
        template => 'configuration/documents.tt2',
    );
}

my %file_named = (
    a_info        => 'CURRENT INFO SHEET.doc',
    b_kaya        => 'Kaya Kalpa Brochure.pdf',
    c_main_map    => 'Main Area Map 2014.pdf',
    d_food        => 'MMC Food.doc',
    e_packet      => 'MMC_Guest_Packet.pdf',
    f_rental_conf => 'Rental Guest Confirmation Letter.doc',
    g_rental_reg  => 'Rental Registration Guidelines.pdf',
);

sub documents_do : Local {
    my ($self, $c) = @_;
    my @mess;
    for my $k (sort keys %file_named) {
        my $fname = $file_named{$k};
        if (my $upload = $c->request->upload($k)) {
            if ($upload->filename() ne $fname) {
                push @mess, "The file '" . $upload->filename
                          . "' should be named '$fname'."
                          ;
            }
        }
    }
    if (@mess) {
        stash($c,
            mess     => join('<br>', @mess),
            template => 'gen_error.tt2',
        );
        return;
    }
    my @uploaded;
    my $dir = '/var/Reg/documents';
    my $now = get_time();
    my $now_t24 = $now->t24;
    my $today = tt_today($c);
    my $today_d8 = $today->as_d8();
    for my $k (sort keys %file_named) {
        my $fname = $file_named{$k};
        if (my $upload = $c->request->upload($k)) {
            copy("$dir/$fname", "$dir/$fname-$today_d8-$now_t24");
            $upload->copy_to("$dir/$fname");
            model($c, 'Activity')->create({
                message => "Uploaded document '$fname'",
                ctime   => $now_t24,
                cdate   => $today_d8,
            });
            push @uploaded, $fname;
        }
    }
    if (@uploaded) {
        $c->flash->{files_uploaded} = join('<br>', @uploaded);
    }
    $c->response->redirect('/configuration/index');
}

1;
