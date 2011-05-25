use strict;
use Test::More;
use ok 'TradeSpring::I::SMA';
use Test::Exception;

use Finance::GeniusTrader::Conf;
use Finance::GeniusTrader::Calculator;
use Finance::GeniusTrader::Eval;
use Finance::GeniusTrader::Tools qw(:conf :timeframe);
use FindBin;
use File::Temp;

my $file;
BEGIN {
    unshift @INC, $FindBin::Bin;
    my $dir = File::Spec->catdir($FindBin::Bin, '..', '..', 'xt',
                                 'gt');
    $file = File::Temp->new;
    my $db_path = $dir;
    print $file <<"EOF";
DB::module Text
DB::text::file_extension _\$timeframe.txt
DB::text::cache 1
DB::text::directory $db_path

EOF
    close $file;
    Finance::GeniusTrader::Conf::load($file->filename);
}

my $db = create_db_object();
my ($calc, $first, $last) =
    find_calculator($db, 'TX', Finance::GeniusTrader::DateTime::name_to_timeframe('5min'),
                    0, '2001-01-01 00:00:00', '2011-01-01 00:00:00');

use TradeSpring::Frame;

my $f = TradeSpring::Frame->new( calc => $calc, i => 0 );


my $i = TradeSpring::I::SMA->new( n => 8,
                                  arg => 'close',
                                  frame => $f,
                              );

use TradeSpring::I::Range;
my $i2 = TradeSpring::I::SMA->new( n => 4,
                                   arg => TradeSpring::I::Range->new( frame => $f), frame => $f );

is( $i->as_string, 'TradeSpring::I::SMA(8,close)');

{
    my (@res, @res2);
    for (0..10) {
        $f->i($_);
        push @res2, $i2->do_calculate;
        push @res, $i->do_calculate;
    }

    is_deeply(\@res, [ undef, undef, undef, undef, undef, undef,
                       undef, '4763.25', '4762.125', '4757', '4755.75']);

    is_deeply(\@res2, [ undef, undef, undef, '33.5', '28.25', '32.25',
                        '39.75', '27.75', '35.5', '40.5', '36.75' ]);

}

my $loader = TradeSpring::I->new(frame => $f);

{
    my $i5 = $loader->load('SMA', arg => 'close', n => 8);

    my (@res);
    for (0..10) {
        $f->i($_);
        push @res, $i5->do_calculate;
    }

    is_deeply(\@res, [ undef, undef, undef, undef, undef, undef,
                       undef, '4763.25', '4762.125', '4757', '4755.75']);
}

use TradeSpring::IManager;
my $loader2 = TradeSpring::IManager->new(frame => $f, indicator_traits => ['Strict']);
{
    my $i5 = $loader2->load('TradeSpring::I::SMA', arg => 'close', n => 8);
    is($i5->as_string, 'TradeSpring::I::SMA(8,close)');
    my @res;
    $f->i(0);
    push @res, $i5->do_calculate();
    throws_ok {
        push @res, $i5->do_calculate();
    } qr'TradeSpring::I::SMA\(8,close\) not called with incremental i: 0, was: 0';
}

done_testing;
