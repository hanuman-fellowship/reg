use strict;
use warnings;

package Stripe;
use base 'Exporter';
our @EXPORT_OK = qw/
    stripe_payment
    metadata
/;
use JSON qw/
    decode_json
/;
use Util qw/
    JON
/;

my $stripe_key = "sk_test_CTgcxK02ela76EawraITgSdd00oyIH2lsp:";     # test

#
# create the button for payments
#
# required named parameters:
#
# name
# description
# amount
# metadata (hashref)
# email
#
sub stripe_payment {
    my (%P) = @_;

    # first check the parameters
    for my $k (qw/
        name description amount
        metadata email
    /) {
        if (! exists $P{$k}) {
            die "missing $k parameter to stripe_payment\n";
        }
    }
    if (ref $P{metadata} ne 'HASH') {
        die "metadata should be a hash ref\n";
    }
    my $amount100 = $P{amount}*100;    # dollars to cents

    # insert the amount value into the metadata
    my $metadata .= qq!-d "metadata[amount]"="$P{amount}" \\\n!;
    for my $k (keys %{$P{metadata}}) {
        $metadata .= qq!-d "metadata[$k]"="$P{metadata}->{$k}" \\\n!;
    }

    # the current script name is in $0
    # use it to form the success_url
    my $script = $0;
    $script =~ s{\A .*/}{}xms;  # strip any leading directories
    # ??? akash or akash2 ???
    my $cgi = 'https://akash2.mountmadonna.org/cgi-bin';
    my $success = "$cgi/${script}_hook?session_id={CHECKOUT_SESSION_ID}";

    my $cmd = <<"EOH";
curl https://api.stripe.com/v1/checkout/sessions \\
  -u $stripe_key \\
  --data-binary "line_items[0][name]"="$P{name}" \\
  -d "line_items[0][description]"="$P{description}" \\
  -d "line_items[0][amount]"="$amount100" \\
  -d "line_items[0][currency]"="usd" \\
  -d "line_items[0][quantity]"="1" \\
  ${metadata}-d customer_email="$P{email}" \\
  -d success_url="$success" \\
  -d cancel_url="https://mountmadonna.org"
EOH
JON "cmd = $cmd";
    my $json = `$cmd`;
JON "json = $json";
    my $href = decode_json($json);
    if ($href->{url}) {
        return <<"EOH";
    <form action="$href->{url}">
    <button type=submit>Pay Securely with your Credit Card</button>
    </form>
EOH
    }
    else {
        return $href->{error}{message};
    }
}

#
# metadata from the payment
# a hash is returned.
# key of amount is always there
#
sub metadata {
    my ($q) = @_;
    my $session_id = $q->param('session_id');
    if (!$session_id) {
        return error => 'no session id';
    }
    my $cmd = "curl https://api.stripe.com/v1/checkout/sessions/$session_id"
            . " -u $stripe_key";
    my $json = `$cmd`;
    my $href = decode_json($json);
    return %{$href->{metadata}};
}

1;
