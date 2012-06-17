package TradeSpring::Test;
use strict;

use Test::More;
use Test::File::Contents;

use Finance::GeniusTrader::Conf;
use Finance::GeniusTrader::Calculator;
use Finance::GeniusTrader::Eval;
use Finance::GeniusTrader::Tools qw(:conf :timeframe);

use Log::Log4perl;
use Log::Log4perl::Level;

use FindBin;
use Path::Class;
use File::Temp;

use TradeSpring;
use TradeSpring::Util qw(local_broker);

use base 'Exporter';

our @EXPORT = our @EXPORT_OK =
    qw(find_calc
       get_report_from_strategy
       is_report_identical
  );

sub import {
    my ($class, @args) = @_;

    my $file;
    my $extra_config = '';
    if (@args && $args[0] eq ':extra_config') {
        shift @args;
        $extra_config = shift @args;
    }
    unshift @INC, $FindBin::Bin;
    my $dir = Path::Class::File->new($INC{'TradeSpring.pm'})
        ->dir->parent->subdir('xt/smoke/gt');
    $file = File::Temp->new;
    my $db_path = $dir;
    print $file <<"EOF";
DB::module Text
DB::text::file_extension _\$timeframe.txt
DB::text::cache 1
DB::text::directory $db_path

$extra_config
EOF
    close $file;

    Finance::GeniusTrader::Conf::load($file->filename);
    $ENV{GTINDICATOR_CACHE} = 1 unless exists $ENV{GTINDICATOR_CACHE};
    $ENV{TRADESPRING_NO_GT} = 1;

    Log::Log4perl->easy_init($FATAL);
    TradeSpring::init_logging;

    $class->export_to_level(1, @args);
}

sub find_calc {
    my (%args) = @_;
    my $db = create_db_object();
    return find_calculator($db, $args{code},
                           Finance::GeniusTrader::DateTime::name_to_timeframe($args{tf}),
                           0, @args{'start', 'end'});
}

sub get_report_from_strategy {
    my (%args) = @_;
    my $args = delete $args{args} || [];
    my $db = create_db_object();
    my ($calc, $first, $last) = find_calc(%args);
    my $lb = local_broker();
    my $report = File::Temp->new;
    local @ARGV = (@$args, '--report_header');
    my $strategy = TradeSpring::load_strategy($args{strategy}, $calc, $lb, $report, undef, [$first, $last]);

    for my $i ($first..$last) {
        TradeSpring::run_trade($strategy, $i, 1);
    }
    $strategy->end;
    close $report;
    return $report;
}

sub is_report_identical {
    my ($report, $expected) = @_;
    my $reference = File::Spec->catfile($FindBin::Bin,
                                        $expected);
    file_contents_identical($report, $reference);

    unless (Test::More->builder->is_passing) {
        $report->unlink_on_destroy(0);
        diag "see diff -u $reference $report";
    }
}

1;
