use strict;
use warnings;
package RetreatCenter::Controller::Configuration;
use base 'Catalyst::Controller';

use lib '../../';
use Util qw/
    stash
    model
    time_travel_class
    tt_today
    slurp
    JON
    put_pr_dir
/;
use Date::Simple qw/
    date
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
# Info Sheet.pdf
# Kaya Kalpa Brochure.pdf
# Main Area Map.pdf
# MMC Food.pdf
# MMC Guest Packet.pdf
# Program Guest Confirmation Letter.pdf
# Program Registration Guidelines.pdf
#
sub documents : Local {
    my ($self, $c) = @_;
    stash($c,
        pg_title => "Documents for Reg",
        template => 'configuration/documents.tt2',
    );
}

# 'our' so we can reference it from elsewhere...
our %file_named = (
    a_info        => 'Info Sheet.pdf',
    b_kaya        => 'Kaya Kalpa Brochure.pdf',
    c_main_map    => 'Main Area Map.pdf',
    d_food        => 'MMC Food.pdf',
    e_packet      => 'MMC Guest Packet.pdf',
    f_rental_conf => 'Program Guest Confirmation Letter.pdf',
    g_rental_reg  => 'Program Registration Guidelines.pdf',
    h_me_guest    => 'Guest-Packet_MountainExperience.pdf',
);

sub documents_do : Local {
    my ($self, $c) = @_;
    my @mess;
    my %uploads;
    for my $k (sort keys %file_named) {
        my $fname = $file_named{$k};
        if (my $upload = $c->request->upload($k)) {
            if ($upload->filename() ne $fname) {
                push @mess, "The file '" . $upload->filename
                          . "' should be named '$fname'."
                          ;
            }
            else {
                $uploads{$fname} = $upload;
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
    if (%uploads) {
        my $dir = '/var/Reg/documents';
        my $now = get_time();
        my $now_t24 = $now->t24;
        my $today = tt_today($c);
        my $today_d8 = $today->as_d8();
        for my $fname (sort keys %uploads) {
            copy("$dir/$fname", "$dir/$fname-$today_d8-$now_t24");
            $uploads{$fname}->copy_to("$dir/$fname");
            model($c, 'Activity')->create({
                message => "Uploaded document '$fname'",
                ctime   => $now_t24,
                cdate   => $today_d8,
            });
        }
        $c->flash->{files_uploaded} = join('<br>', sort keys %uploads);
    }
    $c->response->redirect('/configuration/index');
}

my $dr_file = "$words/date_ranges.txt";
sub date_ranges : Local {
    my ($self, $c) = @_;

    my $date_ranges = "";
    if (-f $dr_file) {
        $date_ranges = slurp($dr_file);
    }
    stash($c,
        date_ranges => $date_ranges,
        template => 'configuration/date_ranges.tt2',
    );
}

sub date_ranges_do : Local {
    my ($self, $c) = @_;

    my @lines = grep { /\S/ }   # skip blank lines
                split "\cM\n", $c->request->params->{date_ranges};
    my $mess = "";
    LINE:
    for my $line (@lines) {
        my ($type, $range, $max) = split ' ', $line;
        if (! ($type && $range && $max)) {
            $mess .= "Invalid format: $line<br>";
            next LINE;
        }
        if ($range !~ m{\d{8}[-]\d{8}}xms) {
            $mess .= "Illegal date range: $range<br>";
            next LINE;
        }
        my ($start, $end) = split '-', $range;
        if ($type !~ m{\A ME|PR \z}xms) {
            $mess .= "Illegal type: $type<br>";
        }
        my $st = date($start);
        if (! $st) {
            $mess .= "Illegal date: $start<br>";
        }
        my $en = date($end);
        if (! $en) {
            $mess .= "Illegal date: $end<br>";
        }
        if ($st && $en && $st > $en) {
            $mess .= "Start date $start is after the End date $end<br>";
        }
        if ($max !~ m{\A \d+ \z}xms) {
            $mess .= "Max value is not numeric: $max";
        }
    }
    if ($mess) {
        stash($c,
            mess     => $mess,
            template => 'listing/error.tt2',
        );
        return;
    }
    open my $out, '>', $dr_file;
    print {$out} map { "$_\n" } @lines;
    close $out;
    put_pr_dir($dr_file, "date_ranges.txt");
    $c->response->redirect('/configuration/index');
}

1;
