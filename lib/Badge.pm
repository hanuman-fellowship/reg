use strict;
use warnings;
package Badge;

use Util qw/
    empty
    model
    get_grid_file
    normalize
    kid_badge_names
/;
use Global qw/
    %house_name_of
    %string
/;

my $html;
my $tt;
sub initialize {
    my ($class, $c) = @_;
    my @badge_strs = model($c, 'String')->search({
                         the_key => { 'like' => 'badge_%' },
                     });
    my %hash;
    for my $bs (@badge_strs) {
        my $bk = $bs->the_key();
        $bk =~ s{\A badge_}{}xms;
        $hash{$bk} = $bs->value();
    }
    $html = undef;
    $tt = Template->new({
              INCLUDE_PATH => 'root/src',
              INTERPOLATE => 1,
          }) or die Template->error();
    $tt->process(
        'registration/badge_top.tt2',
        \%hash,
        \$html,
    );
}

sub add_group {
    my ($class, $program, $code, $data_aref) = @_;
    for (1 .. 8) {
        unshift @$data_aref, {
            first   => '&nbsp;',
            last    => '&nbsp;',
            name    => '&nbsp;',
            room    => '&nbsp;',
            dates   => '&nbsp;',
            code    => '&nbsp;',
            program => '&nbsp;',
        };
    }
    for my $d_href (@$data_aref) {
        # mess with the name
        my $name = $d_href->{name};
        if (index($name, ' ') != -1) {
            my ($first, $last) = $name =~ m{\A (\S+) \s+ (.*) \z}xms;
            $d_href->{first} = $first;
            $d_href->{last} = $last;
        }
        else {
            $d_href->{first} = $name;
            $d_href->{last} = '';
        }
        if (length($d_href->{first}) > 12) {
            $d_href->{name_class} = 'long_name';
        }
    }
    my $stash = {
        program => $program,
        code    => $code,
    };
    for (my $i = 0; $i <= $#$data_aref; $i += 8) {
        $stash->{data}  = [ @{$data_aref}[$i .. $i+7] ];

        # we now fill in any of the undefined slots
        # so that we will print blank badges.
        # we can write in information by hand to make
        # a SOMEwhat official looking badge...
        #
        # UNdoing this - they want the blank paper
        # for scrap paper instead.  
        #
        #for my $href (@{$stash->{data}}) {
        #    if (! defined $href) {
        #        # the iterating variable is an *alias*
        #        $href = {
        #            first   => '&nbsp;',
        #            last    => '&nbsp;',
        #            name    => '&nbsp;',
        #            room    => '&nbsp;',
        #            dates   => '&nbsp;',
        #            code    => '&nbsp;',
        #            program => '&nbsp;',
        #        };
        #    }
        #}
        $tt->process(
            'registration/badge.tt2',
            $stash,
            \$html,
        ) or die Template->error();
    }
}

sub finalize {
    $html =~ s{<div style='page-break-after:always'></div>\n\z}{};
    $html .= <<'EOH';
</body> 
<script>
window.print();
</script>
</html>
EOH
    return $html;
}

# returns $mess, $title, $code
sub get_title_code {
    my ($class, $event) = @_;
    my $title = $event->badge_title();
    if (empty($title)) {
        $title = $event->title();
    }
    $title =~ s{\A .* (Special \s+ Guest) .*}{$1}xms;
    $title =~ s{\A .* (Personal \s+ Retreat) .*}{$1}xms;
    my $code = $event->gate_code();
    my $name = $event->name;
    my $mess;
    if (empty($title)) {
       $mess = "<br>$name - Need a Badge Title"; 
    }
    if (length($title) > 30) {
        $mess .= "<br>$name - Badge Title is too long to properly fit.";
    }
    if (empty($code)) {
        $mess .= "<br>$name - Missing Gate Code - add it in the Summary";
    }
    return ($mess, $title, $code);
}

sub get_badge_data_from_program {
    my ($class, $c, $program, $only_unbadged) = @_;

    my ($mess, $title, $code) = $class->get_title_code($program);
    if ($mess) {
        # cannot proceed
        return $mess;
    }
    my @regs = model($c, 'Registration')->search(
        {
            program_id     => $program->id,
            cancelled      => '',
            $only_unbadged? (badge_printed => ''): (),
        },
        {
            join     => [qw/ person /],
            prefetch => [qw/ person /],   
        }
    );
    if (! @regs) {
        return "No badges to print.";
    }
    my @data;
    for my $reg (@regs) {
        my $dates = $reg->dates();
        my $room  = $reg->house_name();
        my $pronouns = $reg->person->pronouns;
        push @data, 
             map {
                +{  # href
                    name  => $_,
                    pronouns => $pronouns,
                    dates => $dates,
                    room  => $room,
                }
            }
            $reg->person->badge_name(), kid_badge_names($reg);
            # kids pronouns??
        $reg->update({
            badge_printed => 'yes',
        });
    }
    @data = sort { $a->{name} cmp $b->{name} } @data;
    return ($mess, $title, $code, \@data);
}

sub get_badge_data_from_rental2 {
    my ($class, $c, $rental) = @_;
    my ($mess, $title, $code) = $class->get_title_code($rental);
    if ($mess) {
        # cannot proceed
        return $mess;
    }
    my $d = $rental->sdate_obj();
    my $ed = $rental->edate_obj();

    my @data;
    GRID:
    for my $g (model($c, 'Grid')->search({
                   rental_id => $rental->id,
               })
    ) {
        my $cost = $g->cost;
        my $house_id = $g->house_id;
        if (!$cost) {
            # no one is in that room
            # shouldn't be a record...
            next GRID;
        }
        my $room = ($house_id == 1001)? 'Own Van'
                  :($house_id == 1002)? 'Commuting'
                  :               $house_name_of{$house_id}
                  ;
        my $name = $g->name;
        my @nights = $g->occupancy =~ m{(\d)}xmsg;

        # for 'child', '&', and 'and', see below

        # what nights?
        my $this_d = $d;
        my $this_ed = $ed;
        while ($nights[0] == 0) {
            shift @nights;
            ++$this_d;
        }
        while ($nights[-1] == 0) {
            pop @nights;
            --$this_ed;
        }
        my $dates = $this_d->format("%b %e")
                  . ' - '
                  . $this_ed->format("%b %e")
                  ;
        my @names = split m{ \s*
                             (?: [&] | \band\b | [/])    # and /
                             \s*
                           }xmsi, $name;
        for my $n (@names) {
            $n =~ s{ \b child \s* \z}{}xmsi;
            if ($n =~ m{ [(] (.*) [)] }xms) {
                # a parenthesized name is the nickname
                # they want to be called by - perhaps
                # an adopted Sanskrit name or a shortened name
                # they prefer over their formal legal name.
                $n = $1;
            }
            push @data, {
                name  => normalize($n),
                dates => $dates,
                room  => $room,
            };
        }
    }

    # could use Schwartzian transform below
    @data = sort {
                lc $a->{name} cmp lc $b->{name}
            }
            @data;
    return ($mess, $title, $code, \@data);
}

sub get_badge_data_from_rental {
    my ($class, $c, $rental) = @_;
        # $c is unused here - but we include it
        # to keep symmetry with the above sub for programs...
    my ($mess, $title, $code) = $class->get_title_code($rental);
    if ($mess) {
        # cannot proceed
        return $mess;
    }
    my $d = $rental->sdate_obj();
    my $ed = $rental->edate_obj();

    # get the most recent edit from the global web
    #
    my $fgrid = get_grid_file($rental->grid_code());

    my $in;
    if (! open $in, "<", $fgrid) {
        my $name = $rental->name();
        $mess = "$name - Cannot get the current local grid!";
        # cannot proceed
        return $mess;
    }
    my @data;
    LINE:
    while (my $line = <$in>) {
        chomp $line;
        my ($id, $bed, $name, @nights) = split m{\|}, $line;
        my $cost = pop @nights;
        if (!$cost) {
            # no one is in that room
            next LINE;
        }
        my $room = ($id == 1001)? 'Own Van'
                  :($id == 1002)? 'Commuting'
                  :               $house_name_of{$id}
                  ;

        # trim any extra info after the delimiter ~~
        $name =~ s{ ~~ .* }{}xms;

        # for 'child', '&', and 'and', see below

        # what nights?
        my $this_d = $d;
        my $this_ed = $ed;
        while ($nights[0] == 0) {
            shift @nights;
            ++$this_d;
        }
        while ($nights[-1] == 0) {
            pop @nights;
            --$this_ed;
        }
        my $dates = $this_d->format("%b %e")
                  . ' - '
                  . $this_ed->format("%b %e")
                  ;
        my @names = split m{ \s*
                             (?: [&] | \band\b | [/])    # and /
                             \s*
                           }xmsi, $name;
        for my $n (@names) {
            $n =~ s{ \b child \s* \z}{}xmsi;
            if ($n =~ m{ [(] (.*) [)] }xms) {
                # a parenthesized name is the nickname
                # they want to be called by - perhaps
                # an adopted Sanskrit name or a shortened name
                # they prefer over their formal legal name.
                $n = $1;
            }
            push @data, {
                name  => normalize($n),
                dates => $dates,
                room  => $room,
            };
        }
    }
    close $in;
    @data = sort {
                lc $a->{name} cmp lc $b->{name}
            }
            @data;
    return ($mess, $title, $code, \@data);
}

1;
