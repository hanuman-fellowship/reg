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

    my $people_ref = Person->search(<<"EOS");
select p.*
  from people p, affil_people ap, affils a
 where a.descrip like '%phone list%'
       and ap.a_id = a.id
       and ap.p_id = p.id
 order by sanskrit, first;
EOS
    # if no sanskrit name take the first name
    # ??? okay poking inside object?   not really.
    for my $p (@$people_ref) {
        if (!$p->{sanskrit}) {
            $p->{sanskrit} = $p->{first};
        }
    }

    # sort by sanskrit name
    $people_ref = [
        sort {
            $a->sanskrit() cmp $b->sanskrit();
        }
        @$people_ref
    ];

    # alternate css class from 1 to 0 and back
    my $class = 1;
    for my $p (@$people_ref) {
        $p->{class} = $class;
        $class = 1-$class;
    }

    $c->stash->{people} = $people_ref;
    $c->stash->{template} = "listing/phone.tt2";
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

1;
