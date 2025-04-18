use strict;
use warnings;
package USState;
use base 'Exporter';
our @EXPORT = qw/usa valid_state/;

my %valid_state;
while (<DATA>) {
    chomp;
    if (my ($st) = m{([A-Z]{2})$}) {
        $valid_state{$st} = 1;
    }
}

sub usa {
    my ($country) = @_;

    $country =~ s{[ .]}{}g;
    $country = lc $country;
    return    $country eq ''
           || $country eq 'us'
           || $country eq 'usa'
           || $country eq 'united states';
}

sub valid_state {
    my ($st) = @_;
    return exists $valid_state{$st};
}

1;

#
# from http://www.usps.com/ncsc/lookups/abbr_state.txt
#
__DATA__
State/Possession        Abbreviation

ALABAMA                         AL
ALASKA                          AK
AMERICAN SAMOA                  AS
ARIZONA                         AZ
ARKANSAS                        AR
CALIFORNIA                      CA
COLORADO                        CO
CONNECTICUT                     CT
DELAWARE                        DE
DISTRICT OF COLUMBIA            DC
FEDERATED STATES OF MICRONESIA  FM
FLORIDA                         FL
GEORGIA                         GA
GUAM                            GU
HAWAII                          HI
IDAHO                           ID
ILLINOIS                        IL
INDIANA                         IN
IOWA                            IA
KANSAS                          KS
KENTUCKY                        KY
LOUISIANA                       LA
MAINE                           ME
MARSHALL ISLANDS                MH
MARYLAND                        MD
MASSACHUSETTS                   MA
MICHIGAN                        MI
MINNESOTA                       MN
MISSISSIPPI                     MS
MISSOURI                        MO
MONTANA                         MT
NEBRASKA                        NE
NEVADA                          NV
NEW HAMPSHIRE                   NH
NEW JERSEY                      NJ
NEW MEXICO                      NM
NEW YORK                        NY
NORTH CAROLINA                  NC
NORTH DAKOTA                    ND
NORTHERN MARIANA ISLANDS        MP
OHIO                            OH
OKLAHOMA                        OK
OREGON                          OR
PALAU                           PW
PENNSYLVANIA                    PA
PUERTO RICO                     PR
RHODE ISLAND                    RI
SOUTH CAROLINA                  SC
SOUTH DAKOTA                    SD
TENNESSEE                       TN
TEXAS                           TX
UTAH                            UT
VERMONT                         VT
VIRGIN ISLANDS                  VI
VIRGINIA                        VA
WASHINGTON                      WA
WEST VIRGINIA                   WV
WISCONSIN                       WI
WYOMING                         WY


Military "State"        Abbreviation

Armed Forces Africa             AE
Armed Forces Americas           AA
(except Canada)
Armed Forces Canada             AE
Armed Forces Europe             AE
Armed Forces Middle East        AE
Armed Forces Pacific            AP
