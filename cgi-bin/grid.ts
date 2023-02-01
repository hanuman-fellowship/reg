Test Suite for Grid

filling in someone's name causes all nights to be selected
    erasing the name removes the selections
    some hesitancy but it seems to work

Ram 1 cottage rooms and whole Ram 1 - conflict detection
    with name of person in whole Ram 1
'Amy & Dan' in tent - both charged - red
'Amy / Dan' - both charged - not on same days - both get badges
                                                but their dates are unknown
Amy & Lola child - child half charge - red
    if total computed cost ends in .50 others DON'T have .00
    child is 12 or under, right?
    actually <= 4 year olds are free so don't put them in the field at all
Fixed cost house - green
    ignores the occupancy

Parenthesized name is the nickname - for badge.
Like this:
    Jonathan Gruber (Jonny)

Amy Smith
Smith, Amy

Only one person in a double room - charged for single
    w or w/o bath
diff cost for the above in Ram 1 rooms

In triple - have people come and go
    so one is charged for single, double, and triple
        for various nights

email is required or 'no email' in field
    otherwise get the error screen with everyone's name
    or use grid_ne script instead of grid script.

ReEdit

By Name - sorted by name
    -b suffix on rooms with bath
    with non standard dates shown

Zero cost housecost types are not shown

Bath - b
Tent - o (own tent)
No center tents - ever again?

okay to have other things in the Notes field
    aside from email

House cost MUST be Per Day.

Can suffix the name field with -1 or -2 or -7
    to force the number of people calculation
    why would this be needed?  Not shown in Helpful Hints

error if unknown code

Helpful hint popup - look ok?

TODO:
    badges
    pronouns in notes field with some punctuation
    invoice
    number of people on land in calendar - see below
    add activity message for editing the grid
    what else??
    after grid runs
        update counts, grid_max, and housing_charge
        and balance (after refreshing)
            in the Rental
