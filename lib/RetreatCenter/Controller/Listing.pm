use strict;
use warnings;
package RetreatCenter::Controller::Listing;
use base 'Catalyst::Controller';

use Person;

sub index : Local {
    my ($self, $c) = @_;

    $c->stash->{template} = "listing/index.tt2";
}

#
#
#
sub phone : Local {
    my ($self, $c) = @_;

    # better way to do this??? DBIx::Class way?
    my @people = @{ Person->search(<<"EOS") };
select p.*
  from people p, affil_people ap, affils a
 where a.descrip like '%phone list%'
       and ap.a_id = a.id
       and ap.p_id = p.id
 order by sanskrit, first;
EOS
    # if no sanskrit name take the first name
    # ??? okay poking inside object?   not really.
    for my $p (@people) {
        if (!$p->{sanskrit}) {
            $p->{sanskrit} = $p->{first};
        }
    }

    # sort by sanskrit name
    @people = sort {
                  $a->sanskrit() cmp $b->sanskrit();
              }
              @people;

    open my $ph, ">", "root/static/phone1.html"
        or die "cannot create phone1.html";
    print {$ph} <<"EOH";
<html>
<head>
<link rel="stylesheet" type="text/css" href="phone.css" />
</head>
<body>
<center>
<span class=fl_heading>Hanuman Fellowship Phone List</span>
</center>
<table>
<tr class=fl_th>
    <th align=left>Sanskrit</th>
    <th align=left>Name</th>
    <th align=center>Home</th>
    <th align=center>Work</th>
    <th align=left>&nbsp;&nbsp;Address</th>
</tr>
EOH
    my $class = 1;
    my $address;
    for my $p (@people) {
        $address = $p->address();      # method call
        print {$ph} <<"EOH";
<tr class=fl_row$class>
    <td class=fl_name>$p->{sanskrit}</td>
    <td class=fl_name>$p->{first} $p->{last}</td>
    <td class=fl_phone>&nbsp;&nbsp;$p->{tel_home}</td>
    <td class=fl_phone>&nbsp;&nbsp;$p->{tel_work}</td>
    <td class=fl_address>&nbsp;&nbsp;$address</td>
</tr>
EOH
        $class = 1-$class;
    }
print {$ph} <<"EOH";
</table>
</body>
</html>
EOH
    $c->response->redirect($c->uri_for("/static/phone1.html"));
}

sub undup : Local {
    my ($self, $c) = @_;

    my $fname = "root/static/undup.txt";
    open my $out, ">", $fname
        or die "cannot create $fname: $!\n";
    #
    # name dup
    # need both addresses as well???
    #
    my $sth = Person->search_start(<<"EOS");
select last, first
  from people
order by last, first
EOS
    my ($prev_last, $prev_first) = ("", "");
    my ($p, $last, $first);
    print {$out} "Same Last, First Names\n";
    print {$out} "======================\n";
    while ($p = Person->search_next($sth)) {
        $last  = $p->{last};
        $first = $p->{first};
        if ($last eq $prev_last && $first eq $prev_first) {
            print {$out} "$last, $first\n";    
        }
        $prev_last  = $last;
        $prev_first = $first;
    }
    #
    # address dup
    #
    $sth = Person->search_start(<<"EOS");
select *
  from people
 where akey != ''
order by akey
EOS
    my ($prev);
    print {$out} "\n\n";
    print {$out} "Same Address (and not partnered)\n";
    print {$out} "============\n";
    while ($p = Person->search_next($sth)) {
        if ($prev
            && $p->{akey} eq $prev->{akey}
            && $p->{last} ne $prev->{last}
            && ($p->{id_sps} != 0 || $prev->{id_sps} != 0)
        ) {
            print {$out} "$p->{last}, $p->{first}\n";    
            if ($p->{addr1} ne $prev->{addr1} 
                ||
                $p->{zip_post} ne $prev->{zip_post}
             ) {
                print {$out} "    $p->{addr1} $p->{zip_post}\n";
            }
            print {$out} "$prev->{last}, $prev->{first}\n";    
            print {$out} "    $prev->{addr1} $prev->{zip_post}\n";
            print {$out} "\n";
        }
        $prev = $p;
    }
    close $out;
    $fname =~ s{root/}{};
    $c->stash->{filename} = $fname;
    $c->stash->{template} = "listing/undup.tt2";
}

sub stale : Local {
    my ($self, $c) = @_;

    my $upload = $c->request->upload('stale_emails');
    my $n = 0;
    if ($upload) {
        my @emails = $upload->slurp =~ m{\S+\@\S+}g;
        $n = @emails;
        $c->model("RetreatCenterDB::Person")->search(
            { email => { -in => \@emails } },
        )->update({
            email => '',
        });
    }
    $c->stash->{mess} = "$n emails purged.";
    $c->stash->{template} = "gen_error.tt2";
}

1;
