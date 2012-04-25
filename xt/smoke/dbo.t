#!/usr/bin/perl -w
use strict;
use Test::More;
use TradeSpring::Test;

my $report = get_report_from_strategy(
    code => 'TX', tf => 'day',
    start => '2001-01-01 00:00:00',
    end => '2011-01-01 00:00:00',
    strategy => 'DBO',
);

is_report_identical($report, 'dbo-expected.csv');

done_testing();

