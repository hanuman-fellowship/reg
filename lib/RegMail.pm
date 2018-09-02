use strict;
use warnings;
package RegMail;
use base 'Exporter';
our @EXPORT_OK = qw/
    email_letter
/;

use Mail::Sender;
my $mail_sender;

my %string;
sub _init {
    my ($schema) = @_;
    my @auth = ();
    my @strings = $schema->resultset('String')->search({
        -or => [
            the_key => { -like => 'smtp%' },
            the_key => 'redirect_email',
        ],
    });
    for my $s (@strings) {
        $string{$s->the_key} = $s->value;
    }
    if ($string{smtp_auth}) {
        @auth = (
            auth    => $string{smtp_auth},
            authid  => $string{smtp_user},
            authpwd => $string{smtp_pass},
        );
    }
    $mail_sender = Mail::Sender->new({
        smtp => $string{smtp_server},
        port => $string{smtp_port},
        @auth,
    }) or my_die("no mail sender");
}

#
# must have args of to, from, subject, html,
# and schema.
#
sub email_letter {
    my (%args) = @_;

    _init($args{schema}) if !$mail_sender;
    $args{to} =~ s{mountmadonna.org}{mountmadonnainstitute.org}; 
    my @bcc;
    if ($args{bcc}) {
        push @bcc, $args{bcc},
    }

    # redirect of all emails
    if ($string{redirect_email} =~ /\S/) {
        $html = <<"EOM";
This email has been <b>redirected</b>.<br>
The original recipients were:<br>
To: $args{to}<br>
Bcc: @bcc<br>
<hr style="color: red">
<p>
$html
EOM
        $args{to} = $string{redirect_email};
        @bcc = ();
    }
    $mail_sender->Open({
        to       => $args{to},
        from     => $args{from},
        @bcc,
        subject  => $args{subject},
        ctype    => "text/html",
        encoding => "7bit",
    }) or die("no mail sender Open");
    $mail_sender->SendLineEnc($args{html});
    $mail_sender->Close() or die("no mail sender Close");
}

1;
