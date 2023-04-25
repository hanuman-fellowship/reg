use strict;
use warnings;

package Stripe;
use base 'Exporter';
our @EXPORT_OK = qw/
    stripe_payment
    metadata
/;
use Template;
use JSON qw/
    decode_json
/;
use Util qw/
    styled
    JON
/;
use Data::Dumper;

# see Net::Stripe on CPAN
# https://stackoverflow.com/questions/43001753/add-extra-card-to-stripe-customer-in-curl
# very capable and very complicated. :(
# we won't use it as we don't need it. yet.

#
# There are 4 keys for account MMC Reg.
# test or live, publishable or secret
#
my %stripe_key;
open my $in, '<', 'stripe_keys';
while (my $line = <$in>) {
    chomp $line;
    my ($code, $key) = $line =~ m{\A (\w+) \s+ (.*) \z}xms;
    $stripe_key{$code} = $key;
}
close $in;
my $stripe_key = $stripe_key{live_secret};

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
# This routine might display an error message and exit!
#
# What about 'images' in the curl command?
# See: https://stripe.com/docs/payments/checkout/migrating-prices
# or: https://stripe.com/docs/videos
# SO complex!  We'll use just what we need then expand it if needed.
#
# Cancelling (aka voiding) a payment:
# https://stripe.com/docs/refunds#cancel-payment
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
    my $metadata = qq!-d "metadata[amount]"="$P{amount}" \\\n!;
    for my $k (keys %{$P{metadata}}) {
        $metadata .= qq!-d "metadata[$k]"="$P{metadata}{$k}" \\\n!;
    }

    # the current script name is in $0
    # use it to form the success_url
    my $script = $0;
    $script =~ s{\A .*/}{}xms;  # strip any leading directories
    my $cgi = 'https://akash.mountmadonna.org/cgi-bin';
    # a simple (but fragile) way to see if we are on akash2:
    if (-f 'akash2') {
        $cgi =~ s{akash}{akash2}xms;
    }
    my $success = "$cgi/${script}_hook?session_id={CHECKOUT_SESSION_ID}";
    if (-f 'akash2' || $P{metadata}{last} =~ m{\A zz}xmsi) {
        $stripe_key = $stripe_key{test_secret};
    }
    my $cmd = <<"EOH";
curl https://api.stripe.com/v1/checkout/sessions \\
  -u $stripe_key \\
  -d mode=payment \\
  -d            "line_items[0][price_data][unit_amount]"="$amount100" \\
  -d            "line_items[0][price_data][currency]"="usd" \\
  --data-binary "line_items[0][price_data][product_data][name]"="$P{name}" \\
  -d            "line_items[0][price_data][product_data][description]"="$P{description}" \\
  -d            "line_items[0][quantity]"="1" \\
  ${metadata}-d customer_email="$P{email}" \\
  -d success_url="$success" \\
  -d cancel_url="https://mountmadonna.org"
EOH
#JON "cmd = $cmd";
    my $json = `$cmd`;
#JON "json = $json";
    my $href = decode_json($json);
    if ($href->{url}) {
        return <<"EOH";
<form action="$href->{url}">
<button type=submit>Pay Securely with your Credit Card</button>
</form>
EOH
    }
    else {
        # could be an invalid email address...
        # or what?
        Template->new(INTERPOLATE => 1)->process(
            styled('err.tt2'),
            {
                back => 1,
                err  => $href->{error}{message},
            },
        );
        exit;
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
    $href->{metadata}{transaction_id} = substr($session_id, -12);
#JON Dumper($href);
    return %{$href->{metadata}};
}

1;
