#!/usr/bin/perl
use 5.12.1;
use DateTime;
use List::Util qw(max min);

my $cp;
my $last;
my $last_dt;

sub flush {
    # normalize to friday even the week closes on saturday
    $last_dt->subtract(days => 1)
        if $last_dt->day_of_week == 6;
    print join("\t", @$cp, $last_dt->ymd, ).$/;
    die $last_dt if $last_dt->day_of_week == 6;
    undef $cp;
}

while (<>) {
    chomp;
    my ($o, $h, $l, $c, $v, $date) = split /\t/;
    my ($y, $m, $d) = split /-/, $date;
    my $dt = DateTime->new(year => $y, month => $m, day => $d);
    my ($year, $week) = $dt->week;
    my $yw = join('-', $year, $week);
    $last ||= $yw;
    if ($last ne $yw) {
        flush($cp);
        $last = $yw;
    }

    $cp ||= [$o, $h, $l, $c, $v];

    $cp->[1] = max($cp->[1], $h);
    $cp->[2] = min($cp->[2], $l);
    $cp->[3] = $c;
    $cp->[4] += $v;
    $last_dt = $dt;
}

flush($cp) if $cp;
