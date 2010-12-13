#!perl -w
package TestStrategy;
use Moose;
extends 'TradeSpring::Strategy';
with 'TradeSpring::BracketOrder';

has i => (is => "rw", isa => "Int", default => sub { 0 });
has date => (is => "rw", isa => "Str", default => sub { '2010-12-13 11:20:00' });

package main;
use strict;
use Test::More;
use Test::Log::Log4perl;

# test bracket order position
use TradeSpring::Broker::Local;
use TradeSpring::Position;

Log::Log4perl->get_logger();

my $broker = TradeSpring::Broker::Local->new_with_traits
     (traits => ['Stop', 'Update', 'Attached', 'OCA']);

sub mk_cb {
    my $log = shift;
    my @cb = @_;
    map { my $name = $_;
          ("on_$name" => sub { shift; push @$log, [$name, @_] }) } @cb;
}

my $ts = '2010-12-13 11:20:00';
{
    my $log = [];

#    my $tl = Test::Log::Log4perl->expect(['TradeSpring.Position',
#                                          info => 'position entered: (1) 7000 x 1 @ 2010-12-13 11:20:00']);
    my $t = TestStrategy->new( broker => $broker );
    $t->new_bracket_order
        ({ price => 7000,
           type => 'lmt',
           dir => 1,
           qty => 3 },
         { price => 6990,
           type => 'stp',
         },
         { price => 7010,
           type => 'lmt',
       },
         mk_cb($log, qw(entry exit error))
     );

    $broker->on_price(7010);

    is $t->position->status, 'submitted';

    $broker->on_price(7000, 1, $ts);
    is_deeply($log, []);
    is $t->pending_order, 2;
    is $t->position_entered, 1;

    $broker->on_price(7000, 1, $ts);
    is $t->pending_order, 1;
    is $t->position_entered, 2;
    is_deeply($log, []);

    $broker->on_price(7000, 1, $ts);
    is $t->pending_order, 0;
    is $t->position_entered, 3;
    is_deeply($log, [['entry', 7000, 3]]);

    @$log = ();
    $broker->on_price(6991);
    is_deeply($log, []);
    is $t->position_entered, 3;

    $broker->on_price(6990);
    is_deeply($log, [['exit', 'stp', 6990, 3]]);
    is $t->position_entered, 0;
    is $t->pending_order, 0;


}


{
    my $log = [];

    my $tl = Test::Log::Log4perl->expect(
        ['TradeSpring.Position',
         info => 'position entered: (1) 7000 x 1 @ 2010-12-13 11:20:00']);

    my $tl2 = Test::Log::Log4perl->expect(ignore_everything => 1, ['order']);

    my $t = TestStrategy->new( broker => $broker );
    $t->new_bracket_order
        ({ price => 7000,
           type => 'lmt',
           dir => 1,
           qty => 3 },
         { price => 6990,
           type => 'stp',
         },
         { price => 7010,
           type => 'lmt',
       },
         mk_cb($log, qw(entry exit error))
     );

    $broker->on_price(7010);

    is $t->position->status, 'submitted';

    $broker->on_price(7000, 1, $ts);
    is_deeply($log, []);
    is $t->pending_order, 2;
    is $t->position_entered, 1;

    $t->cancel_pending_order;

    is_deeply($log, [['entry', 7000, 1]]);

    @$log = ();
    $broker->on_price(6991);
    is_deeply($log, []);
    is $t->position_entered, 1;

    $broker->on_price(6990, 10, $ts);
    is_deeply($log, [['exit', 'stp', 6990, 1]]);
    is $t->position_entered, 0;
    is $t->pending_order, 0;


}



done_testing;
