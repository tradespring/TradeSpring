#!/usr/bin/perl -w
use strict;
use Test::More;
use TradeSpring::Test
    ':extra_config' => 'Aliases::Indicators::EXX {I::G::Eval (#1 + ( (#2 - #1) *(1-({I:ADXR #3 #3} / 100))))}';

my $report = get_report_from_strategy(
    code => 'TX', tf => '5min',
    start => '2001-01-01 00:00:00',
    end => '2003-01-01 00:00:00',
    strategy => 'CB0',
);

is_report_identical($report, 'cb0-expected.csv');

done_testing();
