use strict;
use Test::More;
use TradeSpring::Test;
use TradeSpring::Frame;
use TradeSpring::FrameVal::Expression;

use methods-invoker;
my ($calc, $first, $last) = find_calc( code => 'TX',
                                       tf => '5min',
                                       start => '2001-01-01 00:00:00',
                                       end => '2011-01-01 00:00:00');

my $f = TradeSpring::Frame->new( calc => $calc, i => 0 );

my $midprice = TradeSpring::FrameVal::Expression->new(
    frame => $f,
    expression => method {
        ($->high + $->low) / 2;
    });

my $bucket = TradeSpring::FrameVal->new(
    frame => $f,
);

$bucket->set($midprice->get);
is($midprice->get, 4722);
is($bucket->get, 4722);
is($bucket, 4722);

$f->i($f->i + 1);
$bucket->set($midprice->get);

is($midprice->get(1), 4722);
is($bucket->get(1), 4722);
is($bucket->[1], 4722);

is($midprice->get, 4733);
is($bucket->get, 4733);
is($bucket, 4733);


done_testing;
