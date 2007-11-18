package Validate;
use strict;
use warnings;

sub zip_range {
    my ($zip_range) = @_;
    my $errors = [];

    $zip_range =~ s/\s+//g;

    # Check for zip range validity

    if ($zip_range =~ m/[^0-9,-]/) {
        return "Only digits, commas, spaces and hyphen allowed in the zip range field";
    }

    my $zip_fields = [ split /,/, $zip_range, -1 ];

    foreach my $field (@$zip_fields) {
        # Field must be either a zip or a zip range
        if ($field =~ m/^(\d{5})-(\d{5})$/) {
            my ($startzip, $endzip) = ($1, $2);

            if ($startzip > $endzip) {
                return "Zip range start is greater than end";
            }
        } 
        else {
            if ($field !~ m/^\d{5}$/) {
                return "Please provide a valid 5 digit zip code (xxxxx) or zip range (xxxxx-yyyyy)";
            }
        }
    }
    return;
}

1;

