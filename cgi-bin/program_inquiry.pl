#!/usr/bin/env perl
use strict;
use warnings;

use CGI;
my $q = CGI->new();
print $q->header();

use Template;

use lib '../lib';
use Date::Simple qw/
    today
/;
use Time::Simple qw/
    get_time
/;
use Util qw/
    db_init
    model
    email_letter
    rand6
/;
use Global qw/
    %string
    init_string
/;
my $c = db_init();
init_string($c);

sub add_update {
    my ($first, $last, $phone, $email) = @_;
    my @per = model($c, 'Person')->search({
        first => $first,
        last  => $last,
    });
    for my $per (@per) {
        if ($per->email eq $email
            ||
            (   $phone eq $per->tel_cell
             || $phone eq $per->tel_home
             || $phone eq $per->tel_work)
        ) {
            # this is the person
            # ensure their cell phone and email are current
            $per->update({
                tel_cell => $phone,
                email    => $email,
            });
            return $per->id();
        }
    }
    # we have either a brand new person
    # or a new person with the same name as one we already have.
    my $per = model($c, 'Person')->create({
        first => $first,
        last => $last,
        email => $email,
        tel_cell => $phone,
        e_mailings => 'yes',
        snail_mailings => 'yes',
        share_mailings => 'yes',
        deceased => '',
        inactive => '',
        secure_code => rand6($c),
        covid_vax => '',
        vax_okay => '',
    });
    return $per->id,
}

my %param = %{ $q->Vars() };
for my $n (qw/ description what_else /) {
    $param{$n} =~ s{\n}{<br>}xmsg;
}
if ($param{leader_name}) {
    for my $f (keys %param) {
        if ($param{$f} =~ m{\0}xms) {
            my @arr = split "\0", $param{$f};
            my $key = "other_$f";
            if ($param{$key}) {
                push @arr, $param{$key};
            }
            $param{$f} = join(', ', @arr);
        }
    }
    delete $param{other_needs};
    delete $param{other_retreat_type};

    # fix up the phone number
    my $phone = $param{phone};
    $phone =~ s{\D}{}xms;
    if (length $phone == 10) {
        $phone =~ s{\A(...)(...)(....)\z}{$1-$2-$3}xms;
        $param{phone} = $phone;
    }

    # ensure capitalized leader name
    my @terms = split ' ', $param{leader_name};
    my $last = ucfirst pop @terms;
    my $first = ucfirst join ' ', @terms;
    $param{leader_name} = "$first $last";

    # a Person record
    $param{person_id} = add_update($first, $last, $phone, $param{email});

    # and finally, in case you're adding a record yourself...
    my $no_email = 0;
    if ($param{what_else} =~ s{no\s*email}{}xms) {
        $no_email = 1;
    }
    my $inquiry = model($c, 'Inquiry')->create({
        the_date => today()->as_d8(),
        the_time => get_time->t24(),
        %param,
    });
    my $inq_id = $inquiry->id();
    $param{inquiry_id} = $inq_id;
    my $msg = "Program Inquiry by <a href='/inquiry/view/$inq_id'>$param{leader_name}</a>";
    if (! $no_email) {
        my $html;
        Template->new({INTERPOLATE => 1})->process(
            'program_inquiry2.tt2',
            \%param,
            \$html,
        );
        email_letter($c,
            from    => 'notifications@mountmadonna.org',
            to      => $string{program_inquiry_email},
            cc      => "$param{leader_name} <$param{email}>",
            subject => "Program Inquiry from $param{leader_name}",
            html    => $html,
            activity_msg => $msg,
        );
    }
    else {
        model($c, 'Activity')->create({
            message => $msg,
            cdate => today()->as_d8(),
            ctime => get_time->t24(),
        });
    }
    print "<div style='font-size: 18pt; margin: .5in; font-family: Arial'>Thank you.  We will be in touch.</div>\n";
}
else {
    Template->new({INTERPOLATE => 1})->process(
        'program_inquiry1.tt2',
        { 
            cgi => $string{cgi},
        }
    );
}
