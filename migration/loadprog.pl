#!/usr/bin/perl
use strict;
use warnings;
use DBI;
use File::Copy;

my $dbh = DBI->connect("dbi:SQLite:retreatcenter.db")
    or die "oh no\n";
$dbh->do("delete from program");
$dbh->do("delete from canpol");
$dbh->do("delete from housecost");
$dbh->do("delete from leader");
$dbh->do("delete from leader_program");

# first cancellation policies
my $cp_sql = "insert into canpol values (?, ?, ?)";
my $cp_sth = $dbh->prepare($cp_sql) or die "no prep cp";
open my $cp, "<", "new/canpol.txt"
    or die "no canpol: !\n";
my ($name, $policy);
my $id = 1;
my %canpol_id = ();
while (<$cp>) {
    s{\r?\n}{};
    my ($k, $v) = split m{\t};
    $v =~ s{^\s*|\s*$}{}g;
    if ($k eq 'text') {
        $policy = "";
        while (<$cp>) {
            s{\r?\n}{};
            last if m{^[.]$};
            $policy .= "$_\n";
        }
        # ready to insert
        $cp_sth->execute($id, $name, $policy) or die "no cp exec";
        $canpol_id{$name} = $id;
        ++$id;
    }
    else {
        $name = ($v eq 'MMC')? "Default": $v;
    }
}
close $cp;
$canpol_id{MMC} = $canpol_id{Default};

# housing costs
my $hc_sql = "insert into housecost values ("
    . (join ",", ("?") x 16)
    . ")";
my $hc_sth = $dbh->prepare($hc_sql) or die "no prep cp";
open my $hc, "<", "new/housing.txt"
    or die "no housing: $!\n";
my %data;
while (<$hc>) {
    s{\r?\n}{};
    my ($n, $type, $cost) = split m{\t};
    $type =~ s{[ ]}{_};
    $data{"HC$n"}{$type} = $cost;
}
close $hc;
for my $name (keys %data) {
    my ($hid) = $name =~ m{(\d+)};
    $hc_sth->execute(
        $hid+1,
        ($name eq 'HC0')? "Default": $name,
        $data{$name}{single} + $data{$name}{single_bath},
        $data{$name}{single},
        $data{$name}{double} + $data{$name}{double_bath},
        $data{$name}{double},
        $data{$name}{triple},
        $data{$name}{quad},
        $data{$name}{dormitory},
        $data{$name}{economy},
        $data{$name}{center_tent},
        $data{$name}{own_tent},
        $data{$name}{own_van},
        $data{$name}{commuting},
        $data{$name}{unknown},
        ($hid == 1 || $hid >= 7)? 'Perday': 'Total'
    );
}

my $per_sql = "select id from people where first = ? and last = ?";
my $per_sth = $dbh->prepare($per_sql) or die "no per_sql\n";
my $aper_sql = "insert into people (first, last, sex) values (?, ?, ?)";
my $aper_sth = $dbh->prepare($aper_sql) or die "no aper_sql\n";
# id
# person_id
# public_email
# url
# image
# biography
# l_order
my $le_sql = "insert into leader (id, person_id, url, image, biography, l_order) values (?, ?, ?, ?, ?, ?)";
my $le_sth = $dbh->prepare($le_sql) or die "no le_sql\n";

# leaders
# we can use the id from the file
# id	11
# last	Anderson
# first	Tenshin Reb
# puemail	                                        
# web	www.rebanderson.org                                         
# image	anderson.jpg        
# bio	-
#
my %gender;
open my $gender, "<", "sfirsts"
    or die "cannot open sfirsts: $!\n";
while (<$gender>) {
    s{\r?\n}{};
    my ($name, $sex) = split m{\t};
    $gender{$name} = $sex;
}
close $gender;

open my $ld, "<", "new/leaders.txt"
    or die "cannot open leaders.txt: $!\n";
my %hash = ();
while (<$ld>) {
    s{\r?\n}{};
    my ($k, $v) = split m{\t};
    $v =~ s{^\s*|\s*$}{}g;
    $hash{$k} = $v;
    if ($k eq 'bio') {
        $hash{bio} = "";
        while (<$ld>) {
            s{\r?\n}{};
            last if m{^.$};
            $hash{bio} .= "$_\n";
        }
        processLeader();
        %hash = ();
    }
}
close $ld;


sub processLeader {
    # find first, last in People or add them
    # - get an id for use when creating the Leader record.
    return unless $hash{first} =~ /\S/ && $hash{last} =~ /\S/;
    $per_sth->execute($hash{first}, $hash{last});
    my ($per_id) = $per_sth->fetchrow_array();
    if (!$per_id) {
        print "creating person $hash{first} $hash{last}\n";
        $aper_sth->execute($hash{first}, $hash{last}, $gender{$hash{first}});
        $per_sth->execute($hash{first}, $hash{last});
        ($per_id) = $per_sth->fetchrow_array();
    }
    my $image = "";
    if ($hash{image} =~ /\S/) {
        if (-f "new/images/$hash{image}" || -f "new/images/b-$hash{image}") {
            $image = "yes";
            my ($suf) = $hash{image} =~ m{[.](\w+)$};
            if (-f "new/images/$hash{image}") {
                copy("new/images/$hash{image}",
                     "../root/static/images/lo-$hash{id}.$suf");
            }
            else {
                copy("new/images/b-$hash{image}",
                     "../root/static/images/lo-$hash{id}.$suf");
            }
            chdir "../root/static/images";
            system("convert -scale 170x lo-$hash{id}.$suf lth-$hash{id}.$suf");
            system("convert -scale 600x lo-$hash{id}.$suf lb-$hash{id}.$suf");
            chdir "../../../migration";
        }
        else {
            print "could not find '$hash{image}'\n";
        }
    }
    $le_sth->execute($hash{id}, $per_id, $hash{web}, $image, $hash{bio}, 1);
}

my @fields = qw/
    id
    name
    title
    subtitle
    glnum
    housecost_id
    retreat
    sdate
    edate
    tuition
    confnote
    url
    webdesc
    brdesc
    webready
    image
    kayakalpa
    canpol_id
    extradays
    full_tuition
    deposit
    collect_total
    linked
    unlinked_dir
    ptemplate
    cl_template
    sbath
    quad
    economy
    footnotes
    reg_start
    reg_end
    prog_start
    prog_end
    school
    level
/;
my $p_sql = "insert into program ("
    . (join ",", @fields)
. ") values ("
    . (join ",", ("?") x @fields)
. ")";
my $p_sth = $dbh->prepare($p_sql) or die "no prep affil\n";

my $lp_sql = "insert into leader_program values (?, ?)";
my $lp_sth = $dbh->prepare($lp_sql) or die "no prep lp\n";

open my $in, "<", "new/curprogr.txt"
    or die "no curprog: $!\n";
# got the order of names backwards so ...
# reverse to the rescue.
my %lookup = reverse qw/
    name          pname
    title         desc
    subtitle      subdesc
    economy       econ
    collect_total colltot
    extradays     extdays
    full_tuition  fulltuit
    url           weburl
    glnum         num
    ptemplate     template
/;
my %init = (
    reg_start  => '4:00 pm',
    reg_end    => '7:00 pm',
    prog_start => '7:00 pm',
    prog_end   => '12:30 pm',
);
%hash = %init;
my $pid = 1;            # explicit rather than auto assigned...
while (<$in>) {
    s{\r?\n$}{};
    my ($k, $v) = split m{\t};
    $v =~ s{^\s*|\s*$}{}g;
    if ($v eq '-') {
        $v = "";
        while (<$in>) {
            s{\r?\n$}{};
            s{^\s*|\s*$}{}g;
            last if m{^\.$};
            $v .= "$_\n";
        }
    }
    $k = $lookup{$k} || $k;
    $hash{$k} = $v;
    if ($k eq 'collect_total') {
        processProg();
        %hash = %init;
    }
}
close $in;

sub processProg {
    return if $hash{name} =~ m{ FULL$};
    $hash{id} = $pid++;
    for my $f (qw/ sdate edate /) {
        $hash{$f} =~ s{(..)/(..)/(....)}{$3$1$2}g;
        $hash{$f} =~ s{[/\s]}{}g;
    }
    if (! $hash{linked}) {
        $hash{unlinked_dir} = 't-'      # to not clobber the cur reg
                              . lc(substr($hash{name}, 0, 3)
                              . "-"
                              . substr($hash{name}, -3, 3));
    }
    $hash{ptemplate} =~ s{[.]html}{};
    $hash{ptemplate} = "default" if $hash{ptemplate} =~ m{^\s*$};
    $hash{cl_template} = "default";
    if (! -f "../root/static/templates/web/$hash{ptemplate}.html") {
        print "*** could not open web template $hash{ptemplate}\n";
    }
    $hash{canpol_id} = $canpol_id{$hash{canpol}};
    $hash{housecost_id} = $hash{housing}+1;
    # images???
    my $image = "";
    if ($hash{image} =~ /\S/) {
        if (-f "new/images/$hash{image}" || -f "new/images/b-$hash{image}") {
            $image = "yes";
            my ($suf) = $hash{image} =~ m{[.](\w+)$};
            if (-f "new/images/$hash{image}") {
                copy("new/images/$hash{image}",
                     "../root/static/images/po-$hash{id}.$suf");
            }
            else {
                copy("new/images/b-$hash{image}",
                     "../root/static/images/po-$hash{id}.$suf");
            }
            chdir "../root/static/images";
            system("convert -scale 170x po-$hash{id}.$suf pth-$hash{id}.$suf");
            system("convert -scale 600x po-$hash{id}.$suf pb-$hash{id}.$suf");
            chdir "../../../migration";
        }
        else {
            print "could not find '$hash{image}'\n";
        }
    }
    $p_sth->execute(@hash{@fields}) or die "no exec";      # yay!
    if ($hash{pres1} != 0) {
        addLeader($hash{pres1}, $hash{id});
    }
    if ($hash{pres2} != 0) {
        addLeader($hash{pres2}, $hash{id});
    }
}

sub addLeader {
    my ($l_id, $p_id) = @_;
    $lp_sth->execute($l_id, $p_id);
}
