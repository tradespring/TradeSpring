#!/usr/bin/perl -w
use Test::More;
use strict;
use Finance::GeniusTrader::Conf;
use Finance::GeniusTrader::Calculator;
use Finance::GeniusTrader::Eval;
use Finance::GeniusTrader::Tools qw(:conf :timeframe);
use Test::File::Contents;
use FindBin;
use File::Temp;
use TradeSpring;
use TradeSpring::Util qw(local_broker);
use lib "examples";

my $file;
BEGIN {
    unshift @INC, $FindBin::Bin;
    my $dir = File::Spec->catdir($FindBin::Bin,
                                 'gt');
    $file = File::Temp->new;
    my $db_path = $dir;
    print $file <<"EOF";
DB::module Text
DB::text::file_extension _\$timeframe.txt
DB::text::cache 1
DB::text::directory $db_path

Aliases::Indicators::EXX {I::G::Eval (#1 + ( (#2 - #1) *(1-({I:ADXR #3 #3} / 100))))}

EOF
    close $file;
    Finance::GeniusTrader::Conf::load($file->filename);
}

$ENV{GTINDICATOR_CACHE} = 1 unless exists $ENV{GTINDICATOR_CACHE};

my $db = create_db_object();
my ($calc, $first, $last) =
    find_calculator($db, 'TX', Finance::GeniusTrader::DateTime::name_to_timeframe('day'),
                    0, '2001-01-01 00:00:00', '2011-01-01 00:00:00');

TradeSpring::init_logging('log.conf');
my $lb = local_broker();

my $report = File::Temp->new;
local @ARGV = qw(--report_header);
my $daytrade = TradeSpring::load_strategy('DBO', $calc, $lb, $report);

for my $i ($first..$last) {
    TradeSpring::run_trade($daytrade, $i, 1);
}
$daytrade->end;

close $report;

my $reference = File::Spec->catfile($FindBin::Bin,
                                    'dbo-expected.csv');
file_contents_identical($report, $reference);

unless (Test::More->builder->is_passing) {
    $report->unlink_on_destroy(0);
    diag "see diff -u $reference $report";
}

done_testing();

