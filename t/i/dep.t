use strict;
use Test::More;
use TradeSpring::Test;
use TradeSpring::Frame;

my ($calc, $first, $last) = find_calc( code => 'TX',
                                       tf => '5min',
                                       start => '2001-01-01 00:00:00',
                                       end => '2011-01-01 00:00:00');

my $f = TradeSpring::Frame->new( calc => $calc, i => 0 );

use TradeSpring::IManager;
my $im = TradeSpring::IManager->new(frame => $f);
{
    my $range = $im->load('TradeSpring::I::Range');
    my $range4 = $im->load('TradeSpring::I::SMA', arg => $range, n => 4);
    is_deeply( $im->order, [ $range, $range4 ]);
}

my $im2 = TradeSpring::IManager->new(frame => $f);
{
    my $range4 = $im->load('TradeSpring::I::SMA', arg => $im->load('TradeSpring::I::Range'), n => 4);
    my $range = $im->load('TradeSpring::I::Range');
    is_deeply( $im->order, [ $range, $range4 ]);
}

done_testing;
