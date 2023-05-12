#!/usr/bin/env perl
use strict;
use warnings;

use CGI;
my $q = CGI->new();
print $q->header();

use Template;
my $tt = Template->new(INTERPOLATE => 1);

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
    styled
    JON
/;
use Global qw/
    %string
    init_string
/;
my $c = db_init();
init_string($c);

sub add_update {
    my ($first, $last, $phone, $email, $on_list) = @_;

    # we have either a brand new person
    # or a new person with the same name as one we already have.
    my @per = model($c, 'Person')->search({
        first => $first,
        last  => $last,
    });
    my $person_id;
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
                e_mailings => $on_list,
            });
            $person_id = $per->id();
        }
    }
    if (! $person_id) {
        my $per = model($c, 'Person')->create({
            first => $first,
            last => $last,
            email => $email,
            tel_cell => $phone,
            e_mailings => $on_list,
            snail_mailings => '',
            share_mailings => '',
            deceased => '',
            inactive => '',
            secure_code => rand6($c),
            covid_vax => '',
            vax_okay => '',
        });
        $person_id = $per->id();
    }
    # does this person have the affiliation named
    # MMC Proposal Submitter?
    my ($affil) = model($c, 'Affil')->search({
                      descrip => 'MMC Proposal Submitter',
                  });
    if (my ($ap) = model($c, 'AffilPerson')->search({
                       a_id => $affil->id,
                       p_id => $person_id,
                   })
    ) {
        # yes, it's okay
    }
    else {
        model($c, 'AffilPerson')->create({
            a_id => $affil->id,
            p_id => $person_id,
        });
    }
    return $person_id;
}

my %param = %{ $q->Vars() };
for my $n (qw/ description optdates what_else /) {
    $param{$n} =~ s{\n}{<br>}xmsg;
}
if ($param{first}) {
    # process the form
    eval {
    for my $f (keys %param) {
        if ($param{$f} =~ m{\0}xms) {
            # multiple checkboxes were checked
            $param{$f} = join ', ', split "\0", $param{$f};
        }
    }

    # special handling of the two Other checkboxes
    if ($param{other_needs}) {
        $param{needs} = join ', ', $param{needs}, $param{other_needs};
        delete $param{on};
    }
    if ($param{other_services}) {
        $param{services} = join ', ', $param{services}, $param{other_services};
        delete $param{os};
    }

    # these two are radio not checkbox
    if ($param{other_group_type}) {
        $param{group_type} = $param{other_group_type};
    }
    if ($param{other_retreat_type}) {
        $param{retreat_type} = $param{other_retreat_type};
    }
    delete $param{other_needs};
    delete $param{other_services};
    delete $param{other_group_type};
    delete $param{other_retreat_type};

    # fix up the phone number
    my $phone = $param{phone};
    $phone =~ s{\D}{}xms;
    if (length $phone == 10) {
        $phone =~ s{\A(...)(...)(....)\z}{$1-$2-$3}xms;
        $param{phone} = $phone;
    }

    # ensure capitalized leader name
    my $first = ucfirst lc $param{first};
    my $last  = ucfirst lc $param{last};

    # a Person record
    $param{person_id} = add_update($first, $last,
                                   $phone, $param{email},
                                   $param{mailing_list});

    # in case you're adding a record yourself...
    # and don't want an email about it
    my $no_email = 0;
    if ($param{what_else} =~ s{no\s*email}{}xms) {
        $no_email = 1;
    }

    $param{leader_name} = ''; # obsoleted
    my $inquiry = model($c, 'Inquiry')->create({
        the_date => today()->as_d8(),
        the_time => get_time->t24(),
        %param,
    });

    my $inq_id = $inquiry->id();

    my $msg = "Program Inquiry by <a href='/inquiry/view/$inq_id'>$first $last</a>";

    if (! $no_email) {
        my $html;
        $tt->process(
            styled('program_inquiry2.tt2'),
            \%param,
            \$html,
        );
        # confirmation to the person
        email_letter($c,
            from    => 'notifications@mountmadonna.org',
            to      => "$param{first} $param{last} <$param{email}>",
            subject => 'MMC Program Inquiry',
            html    => $html,
            activity_msg => "$msg - notify submitter",
        );
        # and to the office - with a link
        $param{inquiry_id} = $inq_id;
        $param{reg} = $string{cgi};
        $param{reg} =~ s{/cgi-bin}{}xms;
        my $html2;
        $tt->process(
            styled('program_inquiry2.tt2'),
            \%param,
            \$html2,
        );
        email_letter($c,
            from    => 'notifications@mountmadonna.org',
            to      => $string{program_inquiry_email},
            subject => "Program Inquiry from $param{first} $param{last}",
            html    => $html2,
            activity_msg => "$msg - notify staff",
        );
    }
    else {
        model($c, 'Activity')->create({
            message => $msg,
            cdate => today()->as_d8(),
            ctime => get_time->t24(),
        });
    }
    $tt->process(
        styled('program_inquiry3.tt2'),
        {},     # no stash
    );
    };  # end of eval
    if ($@) {
        JON "failure: $@";
    }
}
else {
    # show the form to be filled in
    Template->new({INTERPOLATE => 1})->process(
        styled('program_inquiry1.tt2'),
        { 
            cgi => $string{cgi},
        }
    );
}
