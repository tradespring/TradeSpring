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
    my $dir = File::Spec->catdir($FindBin::Bin, '..', '..', 'xt', 'smoke',
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

__END__


use strict;
use Test::More;
use Graph;

use ok 'TradeSpring::I::SMA';
use ok 'TradeSpring::I::Range';
use ok 'TradeSpring::I::M9';
use ok 'TradeSpring::I::M9Z';

my $g = Graph->new;

sub expand_tree {
    my ($g, $i) = @_;
    $g->add_vertex($i);
    for my $attr (grep {$_->has_value($i) &&
                            UNIVERSAL::isa($_->get_value($i), 'TradeSpring::I') }
                      $i->meta->get_all_attributes) {

        my $i_child = $attr->get_value($i);
        $g->add_vertex($i_child);
        $g->add_edge($i, $i_child);
        expand_tree($g, $i_child);
    }
}

#use Graph::Traversal::DFS;
#my @order = Graph::Traversal::DFS->new($g)->dfs;

use File::Temp;
use Finance::GeniusTrader::Conf;
use Finance::GeniusTrader::Calculator;
use Finance::GeniusTrader::Eval;
use Finance::GeniusTrader::Tools qw(:conf :timeframe);
use FindBin;

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

ok($calc);

use TradeSpring::Frame;

my $f = TradeSpring::Frame->new( calc => $calc, i => 0 );


my $i = TradeSpring::I::SMA->new( n => 4,
                                  arg => TradeSpring::I::Range->new( frame => $f), frame => $f );

my $i2 = TradeSpring::I::M9->new( n => 9, frame => $f );

my $i3 = TradeSpring::I::M9Z->new( m9 => $i2, frame => $f );

use TradeSpring::I::OPC;
my $i4 = TradeSpring::I::OPC->new( n => 9, frame => $f );

#my $t = Tree::Simple->new($i);

expand_tree($g, $i);

warn $i->as_string;
use Data::Dumper;
for (0..1000) {
    $f->i($_);
    warn '===> '.$f->date;
#    warn $i->do_calculate;
#    warn join(',', $i2->do_calculate);
#    warn join(',', $i3->do_calculate);
    my $v = $i4->do_calculate;
    warn "OPC: $v" if $v;
#    warn Dumper($i2->calculate);
}

done_testing;
