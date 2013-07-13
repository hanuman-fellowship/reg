use strict;
use warnings;
# ??? order - name, sanskrit, zip - not first, last, zip
package RetreatCenter::Controller::Report;
use base 'Catalyst::Controller';

use lib '../../';       # so you can do a perl -c here.

use Util qw/
    affil_table
    parse_zips
    empty
    trim
    model
    tt_today
    stash
    error
/;
use Date::Simple qw/
    date
    today
/;
use List::MoreUtils qw/
    none
/;
use Global qw/
    %string
/;
use Template;
use LWP::Simple;

sub index : Private {
    my ( $self, $c ) = @_;

    $c->forward('list');
}

my @format_desc = (
    '',
    'To CMS',
    'Name, Address, Email',
    'Name, Home, Work, Cell',
    'Email to VistaPrint',
    'Just Email',
    'Name, Address, Link',
    'First Sanskrit To CMS',
    'Raw',
    'To CMS - Those sans Email',
    'Last, First, Email',
    'Email, Code',
    'Address, Code',
);

use constant {
    TO_CMS              => 1,
    NAME_ADDR_EMAIL     => 2,
    NAME_HOME_WORK_CELL => 3,
    TO_VISTAPRINT       => 4,
    JUST_EMAIL          => 5,
    NAME_ADDR_LINK      => 6,
    FIRST_SANS_CMS      => 7,
    RAW                 => 8,
    CMS_SANS_EMAIL      => 9,
    LAST_FIRST_EMAIL    => 10,
    EMAIL_CODE          => 11,
    ADDR_CODE           => 12,
};

my $exp = "expiry_date.txt";
my $rst_exp = "root/static/$exp";
my $cgi = "http://www.mountmadonna.org/cgi-bin";

sub list : Local {
    my ($self, $c) = @_;

    my ($status, $expiry_date);
    if (-f $rst_exp) {
        open my $in, '<', $rst_exp;
        my $dt = date(<$in>);
        $expiry_date = $dt->format("%D");
        close $in;
        $status = get("$cgi/update_status");
    }
    $c->stash->{reports} = [
        model($c, 'Report')->search(
            undef,
            {
                order_by => 'descrip',
            },
        )
    ];
    stash($c,
        status      => $status,
        expiry_date => $expiry_date,
        template    => "report/list.tt2",
    );
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    model($c, 'Report')->search({id => $id})->delete();
    model($c, 'AffilReport')->search({report_id => $id})->delete();

    $c->forward('list');
}


sub view : Local {
    my ($self, $c, $id, $opt_inout) = @_;

    my $report = model($c, 'Report')->find($id);
    if (defined $opt_inout) {
        $c->stash->{mmc_report} = $opt_inout eq 'mmc';
        $c->stash->{mmi_report} = $opt_inout eq 'mmi';
        $c->stash->{none_report} = $opt_inout eq 'none';
    }
    else {
        $c->stash->{mmc_report} = 1;
    }
    my $fmt = $report->format();
    stash($c,
        report => $report,
        optin => (none { $_ == $fmt } (
                     ADDR_CODE,
                     EMAIL_CODE,
                     NAME_HOME_WORK_CELL,
                     NAME_ADDR_LINK,
                     RAW,
                     )),
        format_verbose => $format_desc[$fmt],
        affils => [
            $report->affils(
                undef,
                {order_by => 'descrip'}
            )
        ],
        last_run => date($report->last_run()) || "",
        template => "report/view.tt2",
    );
}

sub update : Local {
    my ($self, $c, $id) = @_;

    my $report = model($c, 'Report')->find($id);
    my $cur_fmt = $report->format;
    my $format_opts = "";
    for (my $i = 1; $i < @format_desc; ++$i) {
        $format_opts .= "<option value=$i"
                     .  (($i == $cur_fmt)? " selected": "")
                     .  ">$format_desc[$i]</option>\n"
                     ;
    }
    stash($c,
        report => $report,
        format_opts => $format_opts,
        'format_selected_' . $report->format() => 'selected',
        'rep_order_selected_' . $report->rep_order() => 'selected',
        affil_table => affil_table($c, $report->affils()),
        form_action => "update_do/$id",
        template    => "report/create_edit.tt2",
    );
}

my %hash;
my @mess;
sub _get_data {
    my ($c) = @_;

    %hash = %{ $c->request->params() };
    for my $k (keys %hash) {
        delete $hash{$k} if $k =~ m{^aff\d+$};
    }
    @mess = ();
    if (empty($hash{descrip})) {
        push @mess, "The report description cannot be blank.";
    }
    my $zips = parse_zips($hash{zip_range});
    if (! ref($zips)) {
        push @mess, $zips;
    }

    my $dt;
    if ($hash{update_cutoff}) {
        $dt = date($hash{update_cutoff});   
        if (!$dt) {
            push @mess, "illegal cutoff date: $hash{update_cutoff}";
        }
    }
    $hash{update_cutoff} = $dt? $dt->as_d8(): '';

    if ($hash{end_update_cutoff}) {
        $dt = date($hash{end_update_cutoff});   
        if (!$dt) {
            push @mess, "illegal end_cutoff date: $hash{end_update_cutoff}";
        }
    }
    $hash{end_update_cutoff} = $dt? $dt->as_d8(): '';

    if ($hash{nrecs} && $hash{nrecs} !~ m{^\s*\d*\s*$}) {
        push @mess, "illegal Number of Records: $hash{nrecs}";
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "report/error.tt2";
    }
}

#
# currently there's no way to know which fields changed
# so assume they all did.  DBIx::Class is smart about this.
# can we be smart about affils???  yes, see ZZ below.
#
# check for dups???
#
sub update_do : Local {
    my ($self, $c, $id) = @_;

    _get_data($c);
    return if @mess;

    model($c, 'Report')->find($id)->update(\%hash);

    #
    # which affiliations are checked?
    #
    model($c, 'AffilReport')->search(
        { report_id => $id },
    )->delete();

    my @cur_affils = grep { s/^aff(\d+)/$1/ }
                     $c->request->param();
    for my $ca (@cur_affils) {
        model($c, 'AffilReport')->create({
            affiliation_id => $ca,
            report_id => $id,
        });
    }
    #$c->forward("view/$id");
    $c->response->redirect($c->uri_for("/report/view/$id"));
}

sub create : Local {
    my ($self, $c) = @_;

    $c->stash->{affil_table} = affil_table($c);
    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "report/create_edit.tt2";
}

#
# check for dups???
#
sub create_do : Local {
    my ($self, $c) = @_;

    _get_data($c);
    return if @mess;

    my $report = model($c, 'Report')->create({
        %hash,
        last_run  => '',
    });


    my $id = $report->id();
    #
    # which affiliations are checked?
    #
    my @cur_affils = grep { s/^aff(\d+)/$1/ }
                     $c->request->param();
    for my $ca (@cur_affils) {
        model($c, 'AffilReport')->create({
            affiliation_id => $ca,
            report_id => $id,
        });
    }
    $c->forward("view/$id");
}

#
# execute the report generating the proper output
# for the people that match the conditions.
#
sub run : Local {
    my ($self, $c, $id) = @_;

    my $report = model($c, 'Report')->find($id);
    my $format = $report->format();
    my $share    = $c->request->params->{share};
    my $count    = $c->request->params->{count};
    my $collapse = $c->request->params->{collapse};
    my $incl_mmc = $c->request->params->{incl_mmc};
    my $opt_inout = $c->request->params->{report_type} || "";
    my $append    = $c->request->params->{append} || "";
    my $expiry_date = $c->request->params->{expiry_date} || "";

    if (($format == EMAIL_CODE || $format == ADDR_CODE)
        && ! $expiry_date
    ) {
        error($c,
            "missing Expiry Date",
            "gen_error.tt2",
        );
        return;
    }
    if ($expiry_date) {
        my $dt = date($expiry_date);
        if (!$dt) {
            error($c,
                "illegal date format: $expiry_date",
                "gen_error.tt2",
            );
            return;
        }
        $expiry_date = $dt->as_d8();
    }

    my $pref = "none";
    if ($opt_inout eq 'mmi') {
        $pref = "mmi_";
    }
    elsif ($opt_inout eq 'mmc') {
        $pref = "";
    }

    my $order = $report->rep_order();
    my $fields = "p.*";

    # restrictions apply?
    # have people said they want to be included?
    # ??? or is not null?
    my $restrict = "inactive != 'yes' and ";
    if ($report->update_cutoff) {
        $restrict .= "date_updat >= " . $report->update_cutoff . " and ";
    }
    if ($report->end_update_cutoff) {
        $restrict .= "date_updat <= " . $report->end_update_cutoff . " and ";
    }
    # if we have ADDR_CODE or EMAIL_CODE do not
    # restrict it by opt_inout.   We're asking them to
    # update their demographics.  We're not pestering them with ads.
    #
    if ($pref ne 'none' &&
        (   $format == TO_CMS
         || $format == NAME_ADDR_EMAIL
         || $format == TO_VISTAPRINT
         || $format == FIRST_SANS_CMS
         || $format == CMS_SANS_EMAIL
        )
    ) {
        $restrict .= "${pref}snail_mailings = 'yes' and ";
    }
    if ($pref ne 'none' &&
        (   $format == NAME_ADDR_EMAIL
         || $format == JUST_EMAIL
         || $format == LAST_FIRST_EMAIL
        )
    ) {
        $restrict .= "${pref}e_mailings = 'yes' and ";
    }
    if ($share) {
        $restrict .= "share_mailings = 'yes' and ";
    }
    if (! $incl_mmc) {
        $restrict .= "akey != '44595076SUM' and ";
    }

    my $just_email = "";
    if ($format == JUST_EMAIL) {
        # we only want non-blank emails
        $just_email = "email != '' and ";
        $order = "email";
        $fields = "email";
    }
    elsif ($format == EMAIL_CODE) {
        # we only want non-blank emails
        $just_email = "email != '' and ";
    }
    elsif ($format == CMS_SANS_EMAIL || $format == ADDR_CODE) {
        $just_email = "email = '' and ";    # sans Email (misnamed, oh well)
    }
    elsif ($format == LAST_FIRST_EMAIL) {
        # we only want non-blank emails
        $just_email = "email != '' and ";
        $order = "last";
        $fields = "last, first, email";
    }

    my $range_ref = parse_zips($report->zip_range);
    # cannot return a scalar... else the edit would have failed...
    my $zip_bool;
    if (@$range_ref) {
        for my $r (@$range_ref) {
            $zip_bool .= "(p.zip_post between '$r->[0]' and '$r->[1]') or ";
        }
        $zip_bool =~ s{ or $}{};
        $zip_bool = "($zip_bool)";
        # we need the parens in case we have an 'or' inside
        # without parens here we get infinite looping in sql server???
        # why?
    }
    else {
        $zip_bool = "1";     # true
    }

    my $affils = join ',', map { $_->id() } $report->affils();
    my $ap = "";
    my $affil_bool = "";
    if ($affils) {
        $ap = ", affil_people ap";
        $affil_bool = "and (ap.p_id = p.id and ap.a_id in ($affils))";
    }

# ??? without the distinct below???
# we get a row for each person and each affil that matches
# i need an sql expert to explain this to me.

    my $sql = <<"EOS";

select distinct $fields
  from people p $ap
 where $restrict $just_email
       $zip_bool $affil_bool
 order by $order;

EOS
    # mimic DBIx::Class tracing    - it is worth the energy to
    #                                figure out how to do the above
    #                                in Abstract::SQL???
    if ($ENV{DBIC_TRACE}) {
        $c->log->info($sql);
    }
    my @people = @{ Person->search($sql) };
    for my $p (@people) {
        if ($format == FIRST_SANS_CMS) {
            $p->{name} = $p->{first} . " "
                       . (($p->{sanskrit} && $p->{sanskrit} ne $p->{first})?
                              $p->{sanskrit} . " " : "")
                       . $p->{last};
        }
        elsif ($format != JUST_EMAIL) {      # not just email
            $p->{name} = $p->{first} . " " . $p->{last};
        }
    }
    #
    # now to take care of two people in the report
    # who are partners.   this is tricky!  wake up.
    #
    # if we are asking for "Just Email" this won't really apply.
    # no id_sps field so...
    #
    my %partner_index = ();
    my $i = 0;
    for my $p (@people) {
        if ($p->{id_sps}) {
            $partner_index{$p->{id}} = $i;
        }
        ++$i;
    }
    my $ndel = 0;
    for my $p (@people) {
        if ($p->{id_sps}
            && (my $pi = $partner_index{$p->{id_sps}})
        ) {
            my $ptn = $people[$pi];
            if ($p->addr1() eq $ptn->addr1()) {
                # good enough match of address...
                # modify $p so that their 'name' is both of them
                # direct access... :(
                # treating this as an arrayref of hashrefs
                # or an arrayref of objects as convenient.
                $p->{name} = ($p->last eq $ptn->last)?
                                $p->first." & ".$ptn->first." ".$ptn->last:
                                $p->name." & ".$ptn->name; 
                #
                # and modify the data so the partner is not shown
                # nor even considered.
                #
                delete $partner_index{$p->id};
                delete $partner_index{$ptn->id};
                $ptn->{deleted} = 1;
                ++$ndel;
            }
        }
    }

    #
    # if we should collapse records with the same address, do so.
    #
    if ($collapse && ! $just_email) {
        # sort to get same addresses together
        @people = map {
                      $_->[1]
                  }
                  sort {
                      $a->[0] cmp $b->[0]
                  }
                  map {
                      [ $_->{akey}, $_ ]
                  }
                  @people;
        my $prev;
        my $prev_akey = "";
        for my $p (@people) {
            # if not deleted already (due to partnering) and the
            # address is the same as the previous person...
            #
            if (! $p->{deleted} && $p->{akey} eq $prev_akey) {
                $prev->{name} .= " et. al." unless $prev->{deleted};
                $p->{deleted} = 1;
                ++$ndel;
            }
            $prev = $p;
            $prev_akey = $p->{akey};
        }
        # resort
        @people = map {
                      $_->[1]
                  }
                  sort {
                      $a->[0] cmp $b->[0]
                  }
                  map {
                      [ $_->{$order}, $_ ]
                  }
                  @people;
    }

    #
    # filter out the ones we marked for deletion above.
    # wasteful of memory???
    # yes, but memory is cheap, right?
    # if you have a better way of doing this please suggest it!
    #
    if ($ndel) {
        @people = grep { ! $_->{deleted} } @people;
    }
    #
    # a random selection of nrecs?
    # keep it in the same order as before.
    #
    my $nrecs = $report->nrecs();
    if ($nrecs && $nrecs > 0 && $nrecs < @people) {
        my @nums = 0 .. $#people;
        my @subset = ();
        for (1 .. $nrecs) {
            push @subset, splice(@nums, rand(@nums), 1);
        }
        @subset = sort { $a <=> $b } @subset;
        @people = @people[@subset];    # slice!
    }
    if ($count) {
        stash($c,
            message  => "Record count = " . scalar(@people),
            share    => $share,
            collapse => $collapse,
            incl_mmc => $incl_mmc,
            append   => $append,
            expiry_date => date($expiry_date)->format("%D"),
        );
        view($self, $c, $id, $opt_inout);
        return;
    }
    #
    # mark the report as having been run today.
    #
    $report->update({
        last_run => tt_today($c),
    });
    if ($format == TO_VISTAPRINT) {
        for my $p (@people) {
            # accomodate partners
            if ($p->{name} =~ m{(.*)(\&.*)}) {
                $p->{first} = trim($1);
                $p->{last}  = $2;
            }
        }
    }

    my $fname = "report$format";
    my $suf = "txt";
    if (open my $in, "<", "root/src/report/$fname.tt2") {
        my $line = <$in>;
        if ($line =~ m{^<}) {
            # it is likely HTML
            $suf = "html";
        }
    }
    # use the template toolkit outside of the Catalyst mechanism
    my $tt = Template->new({
        INTERPOLATE  => 1,
        INCLUDE_PATH => 'root/src/report',
        EVAL_PERL    => 0,
    });
    $tt->process(
        "$fname.tt2", 
         { people => \@people },
         "root/static/$fname.$suf",
    ) or die "error in processing template: "
             . $tt->error();
    if ($format == EMAIL_CODE || $format == ADDR_CODE) {
        if (my $status = _gen_and_send_data_for_www(
                             \@people,
                             $append,
                             $expiry_date
                         )
        ) {
            error($c,
                $status,
                "gen_error.tt2",
            );
            return;
        }
    }
    $c->response->redirect($c->uri_for("/static/$fname.$suf"));
}

sub _gen_and_send_data_for_www {
    my ($people_aref, $append, $expiry_date) = @_;

    open my $exp_out, '>', $rst_exp
        or return "no $rst_exp";
    print {$exp_out} "$expiry_date\n";
    close $exp_out;

    my $fname = "people_data.sql";
    open my $out, '>', "/tmp/$fname"
        or return "no open: $!";
    print {$out} <<'EOF' if ! $append;
drop table if exists people_data;
create table people_data (
    first text, last text, addr1 text, addr2 text, city text,
        st_prov text, zip_post text, country text,
    tel_cell text, tel_home text, tel_work text,
    email text, sex text, id integer,
    e_mailings text, snail_mailings text, mmi_e_mailings text,
        mmi_snail_mailings text,
    share_mailings text,
    secure_code text,
    akey text,
    status text default ''
);
EOF
    # there are no double quotes anywhere in the data, right?
    # I added sub dquote_clear in Listing.pm to ensure this.
    #
    for my $p (@$people_aref) {
        print {$out} "insert into people_data values (";
        for my $f (qw/
            first last addr1 addr2 city st_prov zip_post country
            tel_cell tel_home tel_work
            email sex id
            e_mailings snail_mailings mmi_e_mailings mmi_snail_mailings
            share_mailings secure_code akey
        /) {
            my $val = $p->{$f};
            if (! defined $val) {
                $val = "";
            }
            print {$out} qq["$val",];
        }
        print {$out} qq["");\n];
    }
    close $out;
    my $ftp = Net::FTP->new($string{ftp_site},
                            Passive => $string{ftp_passive})
        or return "no Net::FTP->new";
    $ftp->login($string{ftp_login}, $string{ftp_password})
        or return "no login";
    $ftp->cwd('www/cgi-bin')
        or return "no cd";
    $ftp->ascii()
        or return "no ascii";
    $ftp->put("/tmp/$fname", $fname)
        or return "no put 1";
    $ftp->put($rst_exp, $exp)
        or return "no put 2";
    $ftp->quit();
    if (get("$cgi/load_people_data") ne "done\n"
    ) {
        return "no load";
    }
    return '';   # all okay
}

sub get_updates : Local {
    my ($self, $c) = @_;

    if (my $status = _get_updates()) {
        error($c,
            $status,
            "gen_error.tt2",
        );
        return;
    }
    $c->forward('list');
}

sub _get_updates {
    if (get("$cgi/get_updates") ne 'gotten') {
        return "no get";
    }
    my $ftp = Net::FTP->new($string{ftp_site},
                            Passive => $string{ftp_passive})
        or return "no Net::FTP->new";
    $ftp->login($string{ftp_login}, $string{ftp_password})
        or return "no login";
    $ftp->cwd('www/cgi-bin')
        or return "no cd";
    $ftp->ascii()
        or return "no ascii";
    $ftp->get("updates.sql", "root/static/updates.sql")
        or return "no ftp get";
    $ftp->quit();
    if (-d "/Users") {
        system("/usr/local/bin/sqlite3"
               . " $ENV{HOME}/Reg/retreatcenter.db"
               . " <$ENV{HOME}/Reg/root/static/updates.sql");
    }
    else {
        system("/usr/bin/mysql --user=sahadev --password=JonB --database=reg2"
               . " <$ENV{HOME}/Reg/root/static/updates.sql");
    }
    return '';      # all okay
}

1;
