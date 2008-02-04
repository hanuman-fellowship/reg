use strict;
use warnings;
package RetreatCenter::Controller::Listing;
use base 'Catalyst::Controller';

use Person;
use Util qw/valid_email model/;

sub index : Local {
    my ($self, $c) = @_;

    $c->stash->{template} = "listing/index.tt2";
}

#
# better way to do this the DBIx::Class way???
#
sub _phone_list {
    my @people = @{ Person->search(<<"EOS") };
select p.*
  from people p, affil_people ap, affils a
 where a.descrip like '%phone list%'
       and ap.a_id = a.id
       and ap.p_id = p.id
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
                  $a->{sanskrit} cmp $b->{sanskrit};
              }
              @people;
    return @people;
}

#
# in columns
#
sub phone_columns : Local {
    my ($self, $c) = @_;

    my @people = _phone_list();
    open my $ph, ">", "root/static/phone_columns.html"
        or die "cannot create phone_columns.html";
    print {$ph} <<"EOH";
<html>
<head>
<link rel="stylesheet" type="text/css" href="phone_columns.css" />
</head>
<body>
<span class=fl_heading>Hanuman Fellowship Phone List</span>
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
    $c->response->redirect($c->uri_for("/static/phone_columns.html"));
}

#
# no addr
#
sub phone_noaddr : Local {
    my ($self, $c) = @_;

    my @people = _phone_list();
    open my $ph, ">", "root/static/phone_noaddr.html"
        or die "cannot create phone_noaddr.html";
    print {$ph} <<"EOH";
<html>
<head>
<link rel="stylesheet" type="text/css" href="phone_noaddr.css" />
</head>
<body>
<span class=fl_heading>Hanuman Fellowship Phone List</span>
<table>
<tr class=fl_th>
    <th align=left>Sanskrit</th>
    <th align=left>Name</th>
    <th align=center>Home</th>
    <th align=center>Work</th>
    <th align=center>Cell</th>
</tr>
EOH
    my $class = 1;
    for my $p (@people) {
        print {$ph} <<"EOH";
<tr class=fl_row$class>
    <td class=fl_name>$p->{sanskrit}</td>
    <td class=fl_name>$p->{first} $p->{last}</td>
    <td class=fl_phone>&nbsp;&nbsp;$p->{tel_home}</td>
    <td class=fl_phone>&nbsp;&nbsp;$p->{tel_work}</td>
    <td class=fl_phone>&nbsp;&nbsp;$p->{tel_cell}</td>
</tr>
EOH
        $class = 1-$class;
    }
print {$ph} <<"EOH";
</table>
</body>
</html>
EOH
    $c->response->redirect($c->uri_for("/static/phone_noaddr.html"));
}

sub _tel_get {
    my ($fone, $let) = @_;
    $fone .= " $let " if $let && $fone;
    return $fone;
}
#
# in one line
#
sub phone_line : Local {
    my ($self, $c) = @_;

    open my $ph, ">", "root/static/phone_line.html"
        or die "cannot create phone_line.html";
    print {$ph} <<"EOH";
<html>
<head>
<link rel="stylesheet" type="text/css" href="phone_line.css" />
</head>
<body>
<span class=heading>Hanuman Fellowship Phone List</span>
EOH
    my @people = _phone_list();
    for my $p (@people) {
        my $fones = _tel_get($p->{tel_home}, 'h')
                  . _tel_get($p->{tel_work}, 'w')
                  . _tel_get($p->{tel_cell}, 'c');
        chop $fones;    # final space
        $fones =~ s{ [hwc]$}{} if length($fones) <= 14;
        my $addr = $p->address();
        print {$ph} <<"EOH";
<span class='person'>
<span class='sanskrit'>$p->{sanskrit}</span>
<span class='name'>$p->{first} $p->{last}</span>
<span class='phones'>$fones</span>
<span class='address'>$addr</span>
</span>
EOH
    }
print {$ph} <<"EOH";
</body>
</html>
EOH
    $c->response->redirect($c->uri_for("/static/phone_line.html"));
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
select last, first, id, ambiguous
  from people
order by last, first
EOS
    my ($prev_last, $prev_first, $prev_id, $prev_amb) = ("", "", 0);
    my ($last, $first, $id, $amb);
    my $p;
    print {$out} "Same Last, First Names\n";
    print {$out} "======================\n";
    my %dups;
    while ($p = Person->search_next($sth)) {
        $last  = $p->{last};
        $first = $p->{first};
        $id    = $p->{id};
        $amb   = $p->{ambiguous};
        if ($last eq $prev_last && $first eq $prev_first) {
            print {$out} "$last, $first\n";    
            # both people should be marked as 'ambiguous'
            $dups{$id}      = 1 if ! $amb;
            $dups{$prev_id} = 1 if ! $prev_amb;
        }
        $prev_last  = $last;
        $prev_first = $first;
        $prev_id    = $id;
        $prev_amb   = $amb;
    }
    $sth->finish();
    for my $id (keys %dups) {
        model($c, 'Person')->find($id)->update({
            ambiguous => 'yes',
        });
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
            && ($p->{id_sps} == 0 || $prev->{id_sps} == 0)
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
    $c->response->redirect($c->uri_for("/static/undup.txt"));
}

sub stale : Local {
    my ($self, $c) = @_;

    my $upload = $c->request->upload('stale_emails');
    my $n = 0;
    if ($upload) {
        my @emails = $upload->slurp =~ m{\S+\@\S+}g;
        $n = @emails;
        model($c, 'Person')->search(
            { email => { -in => \@emails } },
        )->update({
            email => '',
        });
    }
    $c->stash->{mess} = "$n emails purged.";
    $c->stash->{template} = "gen_error.tt2";
}

sub email_check : Local {
    my ($self, $c) = @_;

    my @people;
    my $email;
    for my $p (model($c, 'Person')->search(
        { email => { "!=", "" }},
        { order_by => 'email' },
    )) {
        if (($email = $p->email) && ! valid_email($email)) {
            push @people, $p;
        }
    }
    @people = sort {
                  $a->email cmp $b->email
              }
              @people;
    $c->stash->{people} = \@people;
    $c->stash->{template} = "listing/bad_email.tt2";
}

# temp
sub registrations : Local {
    my ($self, $c) = @_;

    $c->stash->{registrations} = [ model($c, 'Registration')->all() ];
    $c->stash->{programs}      = [ model($c, 'Program')->all() ];
    $c->stash->{bjs} = [
        model($c, 'Person')->search(
            {
                last => { like => 'Bj%'},
            },
        )
    ];
    $c->stash->{template} = "listing/registrations.tt2";
}

1;
