use strict;
use warnings;
package RetreatCenter::Controller::Book;
use base 'Catalyst::Controller';

use lib '../..';
use Util qw/
    trim
    empty
    model
    tt_today
    stash
    error
    read_only
/;
use Date::Simple qw/
    date
    today
/;
use Global qw/
    %string
/;

sub index : Private {
    my ($self, $c) = @_;

    $c->forward('search');
}

sub search : Local {
    my ($self, $c, $pattern, $field, $nrecs) = @_;

    if ($pattern) {
        $c->stash->{message}  = "No book found matching '$pattern'.";
    }
    $c->stash->{pattern} = $pattern;
    if (! $field) {
        $c->stash->{title_selected} = "selected";
    }
    for my $f (qw/ 
        title author description subject 
    /) {
        if (defined $field && $field eq $f) {
            $c->stash->{"$f\_selected"} = "selected";
        }
    }
    stash($c,
        pg_title => "Book Search",
        template => "book/search.tt2",
    );
}

sub search_do : Local {
    my ($self, $c) = @_;

    my $pattern = trim($c->request->params->{pattern});
    my $orig_pattern = $pattern;
    $pattern =~ s{\*}{%}g;
    # % in a web form messes with url encoding... :(
    # even when method=post?

    my $field   = $c->request->params->{field};
    my $nrecs = 15;
    if ($pattern =~ s{\s+(\d+)\s*$}{}) {
        $nrecs = $1;
    }
    my $offset  = $c->request->params->{offset} || 0;
    my $search_ref = {
        $field => { 'like', "%$pattern%" },
    };

    my @books = model($c, 'Book')->search(
        $search_ref,
        {
            order_by => (($field eq 'author')? 'author': 'title'),
            rows     => $nrecs+1,       # +1 so we know if there are more
                                        # to be seen.  the extra one is
                                        # popped off below.
            offset   => $offset,
        },
    );
    if (@books == 0) {
        # None found.
        $c->response->redirect($c->uri_for("/book/search/$orig_pattern/$field/$nrecs"));
        return;
    }
    if (@books == 1) {
        # just one so show their Book recrod
        view($self, $c, $books[0]);
        return;
    }
    if ($offset) {
        $c->stash->{N} = $nrecs;
        $c->stash->{prevN} = $c->uri_for('/book/search_do')
                            . "?" 
                            . "pattern=$orig_pattern"
                            . "&field=$field"
                            . "&nrecs=$nrecs"
                            . "&offset=" . ($offset-$nrecs);
    }
    if (@books > $nrecs) {
        pop @books;
        $c->stash->{N} = $nrecs;
        $c->stash->{nextN} = $c->uri_for('/book/search_do')
                            . "?" 
                            . "pattern=$orig_pattern"
                            . "&field=$field"
                            . "&nrecs=$nrecs"
                            . "&offset=" . ($offset+$nrecs);
    }
    $c->stash->{books} = \@books;
    $c->stash->{field} = ucfirst $field;
    $c->stash->{pattern} = $orig_pattern;
    $c->stash->{template} = "book/search_result.tt2";
}

sub delete : Local {
    my ($self, $c, $id) = @_;

    if (read_only($c) == 1) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
    my $b = model($c, 'Book')->find($id);
    my $title = $b->title();
    my $author = $b->author();

    model($c, 'Book')->search(
        { id => $id }
    )->delete();

    $c->flash->{message} = "'$title' by $author was deleted.";
    $c->response->redirect($c->uri_for('/book/search'));
}

sub view : Local {
    my ($self, $c, $id) = @_;

    my $b;
    if (ref($id)) {
        # called with Book object
        $b = $id;
    }
    else {
        # called with numeric id
        $b = model($c, 'Book')->find($id);
    }
    if (! $b) {
        $c->stash->{mess} = "Book not found - sorry.";
        $c->stash->{template} = "gen_error.tt2";
        return;
    }
    $c->stash->{book} = $b;
    $c->stash->{media} =  $b->media() == 1? "Book"
                         :$b->media() == 2? "VHS"
                         :$b->media() == 3? "DVD"
                         :                  "CD"
                         ;
    $c->stash->{template} = "book/view.tt2";
}

sub create : Local {
    my ($self, $c) = @_;

    if (read_only($c) == 1) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
    $c->stash->{media_opts} = <<"EOO";
<option value=1>Book
<option value=2>VHS
<option value=3>DVD
<option value=4>CD
EOO
    $c->stash->{form_action} = "create_do";
    $c->stash->{template}    = "book/create_edit.tt2";
}

my %hash;
my @mess;
sub _get_data {
    my ($c) = @_;

    @mess = ();
    %hash = %{ $c->request->params() };
    if (empty($hash{title})) {
        push @mess, "Title cannot be blank: '$hash{title}'.";
    }
    if (@mess) {
        $c->stash->{mess} = join "<br>\n", @mess;
        $c->stash->{template} = "book/error.tt2";
    }
}

#
#
#
sub create_do : Local {
    my ($self, $c) = @_;

    if (read_only($c) == 1) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
    _get_data($c);
    return if @mess;

    my $p = model($c, 'Book')->create({
        %hash,
    });
    my $id = $p->id();
    $c->flash->{message} = "Created " . $hash{title};
    $c->response->redirect($c->uri_for('/book/search'));
}

sub update : Local {
    my ($self, $c, $id) = @_;

    if (read_only($c) == 1) {
        stash($c,
            template => 'read_only.tt2',
        );
        return;
    } 
    my $b = model($c, 'Book')->find($id);
    my $cur_media = ($b->media() == 1)? "Book"
                   :($b->media() == 2)? "VHS"
                   :($b->media() == 3)? "DVD"
                   :                    "CD"
                   ;
    my $opts = "";
    my $n = 1;
    for my $m (qw/
        Book
        VHS
        DVD
        CD
    /) {
        $opts .= "<option value=$n"
              .  (($cur_media eq $m)? " selected": "")
              .  ">$m\n"
              ;
        ++$n;
    }
    stash($c,
        template    => "book/create_edit.tt2",
        media_opts  => $opts,
        book        => $b,
        form_action => "update_do/$id",
    );
}

sub update_do : Local {
    my ($self, $c, $id) = @_;

    _get_data($c);
    return if @mess;

    my $p = model($c, 'Book')->find($id);
    $p->update({
        %hash,
    });
    $c->response->redirect($c->uri_for("/book/view/$id"));
}

1;
