package TradeSpring;

use strict;
use 5.008_001;
our $VERSION = '0.01';
use Finance::GeniusTrader::Prices;
use UNIVERSAL::require;
use Try::Tiny;
use Finance::GeniusTrader::Eval;
use Finance::GeniusTrader::Tools qw(:conf :timeframe);
use Finance::GeniusTrader::DateTime;

use TradeSpring::Broker::Local;
sub local_broker {
   TradeSpring::Broker::Local->new_with_traits
        (traits => ['Stop', 'Timed', 'Update', 'Attached', 'OCA'],
         hit_probability => 1,
     );
}

use TradeSpring::Broker::JFO;
use JFO::Config;
use Net::Address::IP::Local;
use Log::Log4perl;
use Log::Log4perl::Level;
our $logger;
sub init_logging {
    my $logconf = shift;
    my $watch = shift;
    if (-e $logconf) {
        if ($watch) {
            Log::Log4perl::init_and_watch($logconf, 60);
        }
        else {
            Log::Log4perl::init($logconf);
        }
    }
    else {
        Log::Log4perl->easy_init($INFO);
    }
    $logger = Log::Log4perl->get_logger("tradespring");
}

our $Config;
sub jfo_broker {
    my $cname = shift;
    my $port = shift;
    my %args = @_;
    $Config ||= JFO::Config->load('config.yml') or die;
    my $contract = Finance::TW::TAIFEX->new->product('TX');
    my $now = DateTime->now;
    my $near = $contract->_near_term($now);

    my $c = $Config->{commodities}{$cname} or die ;

    my $endpoint = $c->account->endpoint;
    my $address = Net::Address::IP::Local->connected_to(URI->new($endpoint->address)->host);

    my $uri = URI->new($Config->{notify_uri}."/".$c->account->name);
    $uri->host($address);
    $uri->port($port);
    $logger->info("JFO endpoint: @{[ $endpoint->address ]}, notification address: $uri");
    $endpoint->notify_uri($uri->as_string);

    my $traits = ['Position', 'Stop', 'Timed', 'Update', 'Attached', 'OCA'];

    my $broker = TradeSpring::Broker::JFO->new_with_traits
        ( endpoint => $endpoint,
          params => {
              type => 'Futures',
              exchange => $c->exchange,
              code => $c->code,
              year => $near->year, month => $near->month,
          },
          traits => $traits,
          $args{daytrade} ? (position_effect_open => '') : (),
      );
    $logger->info("JFO broker created: ".join(' ', @$traits));
    return ($broker, $c);
}

sub load_calc {
    my ($code, $tf_name) = @_;
    my $tf = Finance::GeniusTrader::DateTime::name_to_timeframe($tf_name);
    find_calculator(create_db_object(), $code, $tf, 1);
}

sub load_ps {
    my ($name, $store, $cb_argv) = @_;
    my $ps;

    $name->require or die $@;

    if ($store && $name->can('load') && -e $store) {
        $logger->info("$name: loading $store");
        $ps = $name->load($store);
    }
    else {
        my $meta = Moose::Meta::Class->create_anon_class(
            superclasses => [$name],
            roles        => [qw(MooseX::SimpleConfig MooseX::Getopt)],
            cache        => 1,
        );

        $ps = $meta->name->new_with_options;
        $cb_argv->($ps->extra_argv) if $cb_argv;
        $ps = $name->new(%$ps);
    }
    return $ps;
}

sub load_strategy {
    my ($name, $calc, $broker, $fh, $load_day_from_db) = @_;
    $fh ||= \*STDOUT;
    try { eval $name->meta }
    catch {
        $name->require or die $@;
    };
    $name->init;

    my @args = (broker => $broker);

    my $meta = Moose::Meta::Class->create_anon_class(
        superclasses => [$name],
        roles        => [qw(MooseX::SimpleConfig MooseX::Getopt)],
        cache        => 1,
    );

    if ($meta->find_attribute_by_name('dcalc')) {
        my $dcalc;
        if ($load_day_from_db) {
            eval {
            ($dcalc) = load_calc($calc->code, 'day');
            my ($f, $l) = map { $dcalc->prices->date($_.' 00:00:00') }
                map {
                    $calc->prices->at($_)->[$DATE] =~ m/^([\d-]+)/;
                } (0, $calc->prices->count-1);
            unless (defined $f && defined $l) {
                $logger->error("day db not up-to-date.");
                undef $dcalc;
            }
        }
        }

        if (!$dcalc) {
            $dcalc = Storable::dclone($calc);
            $dcalc->create_timeframe($Finance::GeniusTrader::DateTime::DAY);
            $dcalc->set_current_timeframe($Finance::GeniusTrader::DateTime::DAY);
        }
        push @args, (dcalc => $dcalc);
    }

    my $strategy = $meta->name->new_with_options( report_fh => $fh, calc => $calc, @args );

    @ARGV = @{$strategy->extra_argv};
    syswrite $fh,
        join(",", qw(id date dir open_date close_date open_price close_price profit),
             sort keys %{$name->attrs}).$/
                 if $strategy->report_header;


    return $strategy;
}

use DateTime::Format::Strptime;
my $Strp = DateTime::Format::Strptime->new(
    pattern     => '%F',
    time_zone   => 'Asia/Taipei',
);

my $Strp_time = DateTime::Format::Strptime->new(
    pattern     => '%F %T',
    time_zone   => 'Asia/Taipei',
);


sub run_trade {
    my ($strategy, $i, $sim, $fitf) = @_;

    my @frame_attrs = $strategy->frame_attrs;

    my $date = $strategy->calc->prices->at($i)->[$DATE];
    for (@frame_attrs) {
        my $frame = $strategy->$_;
        if (!$frame->i) {
            my $fdate = $frame->calc->prices->find_nearest_following_date($date);
            $frame->i( $frame->calc->prices->date($fdate) );
        }
        else {
            while ($frame->date($frame->i+1) le $date) {
                $frame->i($frame->i+1);
            }
        }
    }

    $strategy->i($i);
    run_prices($strategy, $date, $i, $sim, $fitf);
    $strategy->run();
}

use List::MoreUtils qw(none);

sub run_prices {
    my ($strategy, $datetime, $i, $sim, $fitf) = @_;

    return unless $strategy->can('broker');
    my $lb = $strategy->broker;

    if (keys %{$lb->orders}) {
        my ($date, $time) = split(/ /, $strategy->calc->prices->at($i)->[$DATE]);

        # XXX current_date is not set properly for the first bar, but
        # right now run_prices is unlikely to be called before the first bar
        my $dt = $strategy->can('current_date') ?
            $strategy->current_date : $Strp->parse_datetime($date);

        my ($h, $m, $s) = split(/:/, $time);
        my $ds = $h * 3600 + $m * 60 + $s;

        return if
            none { $_->{order}{timed}
                   ? $dt->epoch + $ds >= $_->{order}{timed}
                   : _order_effective($strategy, $_->{order}) }
                    values %{$lb->orders};

        if ($sim) {
            sim_prices($strategy, $lb, $dt, $time);
        }
        elsif ($fitf) {
            run_tick_fitf($strategy, $lb, $dt, $time);
        }
        else {
            warn "not sure what to do";
        }
    }
}

sub _order_effective {
    my ($strategy, $order) = @_;

    return 1 if $order->{type} eq 'mkt';

    if ($order->{type} eq 'stp') {
        if (exists $order->{effective}) {
            return $order->{effective} <= $strategy->high &&
                   $order->{effective} >= $strategy->low;
        }
        return 1 if $order->{trail};
        return $order->{dir} * ( $order->{dir} > 0 ? $strategy->high : $strategy->low)
            >= $order->{price} * $order->{dir};
    }

    if ($order->{price}) {
        return $order->{price} <= $strategy->high &&
               $order->{price} >= $strategy->low;
    }
}

use POSIX qw(ceil floor);

sub sim_prices {
    my ($strategy, $lb, $dt, $time) = @_;

    $logger->debug("simulate prices for bar: ".$strategy->date);

    my @p;
    for my $o (grep { $_->{order}{type} eq 'stp' }
                   values %{$lb->orders} ) {
        my $p = $o->{order}{price};
        $p = $o->{order}{dir} > 0 ? ceil($p) : floor($p);
        unshift @p, ($p)
            if $p < $strategy->high && $p > $strategy->low;
    }
    push @p, map { $strategy->$_ } qw(high low);
    my @prices_down = sort { $b <=> $a } grep { $_ <= $strategy->open } @p;
    my @prices_up   = sort { $a <=> $b } grep { $_ > $strategy->open } @p;
    if ($strategy->close > $strategy->open) {
        @p = (@prices_down, @prices_up)
    }
    else {
        @p = (@prices_up, @prices_down)
    }

    my $nsecs = Finance::GeniusTrader::DateTime::timeframe_ratio($strategy->calc->prices->timeframe, $PERIOD_1MIN) * 60;
    my ($h, $m, $s) = split /:/, $time;
    my $ts = $dt->epoch + $h * 3600 + $m * 60 + $s;
    my $d = $strategy->date; # XXX: fix for timed orders
    @p = ($strategy->open, @p);
    my %seen = map { $_ => 1 } @p;
    while (my $tick = shift @p) {
        $lb->on_price($tick, undef, { timestamp => $ts - $nsecs});
        for my $o (grep { $_->{order}{type} eq 'stp' }
                       values %{$lb->orders} ) {
            my $p = $o->{order}{price};
            $p = $o->{order}{dir} > 0 ? ceil($p) : floor($p);
            if ($p < $strategy->high && $p > $strategy->low && !$seen{$p}++) {
                unshift @p, $p;
            }
        }
    }
    $lb->on_price($strategy->close, undef, { timestamp => $ts - 2 });
}

my $fitf;
sub run_tick_fitf {
    require Finance::FITF;
    my ($daytrade, $lb, $date, $time) = @_;

    $logger->debug("run tick until: $time ".$daytrade->date)
        if $logger->is_debug;
    if (!$fitf || $fitf->header->{date} ne $date->ymd('')) {
        $fitf = Finance::FITF->new_from_file(
            fitf_store($date)) or die;
    }

    my $start = $Strp_time->parse_datetime($daytrade->date($daytrade->i-1))->epoch;
    my $end =   $Strp_time->parse_datetime($daytrade->date)->epoch;

    my $start_b = $fitf->bar_at($start);
    my $end_b = $fitf->bar_at($end);

    my $date_base = $date->epoch;
    my $ymd = $date->ymd;
    my $last_price;
    my $last_time;
    my $broker_update;
    my %prices_seen;
    $fitf->run_ticks($start_b->{index} + $start_b->{ticks},
                     $end_b->{index}   + $end_b->{ticks}-1,
                     sub {
                         my ($timestamp, $price, $volume) = @_;
                         if ($last_price && $price == $last_price &&
                             $last_time && $last_time == $timestamp
                         ) {
                             return;
                         }
                         if ($broker_update && $broker_update != $lb->{timestamp} && 1) {
                             %prices_seen = ();
                             $broker_update = $lb->{timestamp};
                         }
#                         return if $prices_seen{$price}++;
                         $lb->on_price($price, $volume, { timestamp => $timestamp });
                         $last_price = $price; $last_time = $timestamp;
                     });

}

sub fitf_store {
    my $date = shift;
    return '/Users/clkao/work/trade/XTAF.TX/'.$date->year.'/XTAF.TX-'.$date->ymd.'.fitf';
}

use Finance::GeniusTrader::Calculator;

sub live_handler {
    my ($pagm, $client, $myself, $code, $tf, $logger, $strategy_name, $broker, $daytrade) = @_;
    my $timeframe = Finance::GeniusTrader::DateTime::name_to_timeframe($tf);

    my $calc;
    my ($tick_channel, $ag_channel);
    my $strategy;
    sub {
        my $msg = shift;
        no warnings 'uninitialized';
        if ($msg->{type} eq 'pagm.session') {
            $pagm->publish({type => 'pagm.history', code => $code,
                            timeframe => $tf, count => 300,
                            reply => $myself->name});
            $tick_channel = $msg->{tick_channel};
            $ag_channel = $msg->{ag_channel}.$tf;
        }
        elsif ($msg->{type} eq 'history') {
            my $prices = $msg->{prices};
            $logger->info("loaded ".(scalar @{$prices})." items for $code/$tf from pagm: $prices->[0][5] - $prices->[-1][5]");
            my $p = Finance::GeniusTrader::Prices->new;
            $p->{prices} = $prices;
            $p->set_timeframe($timeframe);
            $calc = Finance::GeniusTrader::Calculator->new($p);

            local $_; # XXX: something is modifying $_ and cause anymq topic reaper trouble
            $strategy = TradeSpring::load_strategy($strategy_name, $calc, $broker);

            $client->subscribe($myself->bus->topic($tick_channel));
            $client->subscribe($myself->bus->topic($ag_channel));

            if ($daytrade) {
                # XXX: load existing position?
                my $start = $calc->prices->count-1;
                my $dt = DateTime->now(time_zone => 'Asia/Taipei');

                while (($p->at($start-1)->[$DATE] =~ m/^([\d-]+)/)[0] eq $dt->ymd ) {
                    --$start;
                }
                if ($start != $calc->prices->count-1) {
                    for my $i ($start..$calc->prices->count-1) {
                        $strategy->i($i);
                        $strategy->run();
                    }
                }
            }
        }
        elsif ($msg->{type} eq 'agbar') { # bar
            next unless $calc;
            my $prices = $msg->{data};

            use Term::ANSIScreen qw(:color :screen);
            print clline;
            print (color 'white');
            print $prices->[$DATE].' = ';
            print color $prices->[$CLOSE] > $prices->[$OPEN] ? 'red' : 'green';
            print join('',map { sprintf("%5d", $_) } @{$prices}[0..3]);
            printf (" V: %6d", $prices->[4]);
            print color 'reset';
            print $/;

            $calc->prices->add_prices($prices);
            $strategy->i($calc->prices->count-1);
            $strategy->run();
        }
        elsif ($msg->{price}) { # tick
            return unless $calc;
            my $time = $msg->{time};

            print clline;
            print (color 'white');
            print $time.' = ';
            my $pp = $calc->prices->at($calc->prices->count-1);
            my $c = $msg->{price}> $pp->[$CLOSE] ? 'red' : 'green';
            print colored [$c], sprintf(" P: %5d V: %6d", $msg->{price}, $msg->{volume} );
            print "\r";

            $broker->on_price($msg->{price}, $msg->{volume}, { timestamp => $msg->{timestamp} } );
        }
        else {
            $logger->error("unhandled message: ".Dumper($msg)); use Data::Dumper;
        }
        return 1;
    }
}

1;
__END__

=encoding utf-8

=for stopwords

=head1 NAME

TradeSpring -

=head1 SYNOPSIS

  use TradeSpring;

=head1 DESCRIPTION

TradeSpring is

=head1 AUTHOR

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

=cut
