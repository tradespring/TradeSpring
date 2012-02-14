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
use YAML::Syck;

use TradeSpring::Config;
use TradeSpring::Broker::Local;

sub local_broker {
   TradeSpring::Broker::Local->new_with_traits
        (traits => ['Stop', 'Timed', 'Update', 'Attached', 'OCA'],
         hit_probability => 1,
     );
}

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

my $config;

sub config {
    $config ||= TradeSpring::Config->new;
}

# XXX: deprecated
my $jfo_config;

sub jfo_config {
    warn "deprecated";
    $jfo_config ||= YAML::Syck::LoadFile('config.yml') or die "Can't load config.yml";
}

sub raw_jfo_broker_args {
    eval {
        require TradeSpring::Broker::JFO;
        require TradeSpring::Broker::JFO::EndPoint;
    } or die 'jfo required '.$@;
    require Finance::TW::TAIFEX;

    my ($c, $port) = @_;
    my $contract = Finance::TW::TAIFEX->new->product('TX');
    my $now = DateTime->now;
    my $near = $contract->_near_term($now);

    my $account = jfo_config->{accounts}{$c->{account}} or die "$c->{account} not found";
    my $uri = URI->new(jfo_config->{notify_uri}."/".$c->{account});
    if ($port) {
        my $address = Net::Address::IP::Local->connected_to(URI->new($account->{endpoint}{address})->host);

        $uri->host($address);
        $uri->port($port);
    }

    my $ep = TradeSpring::Broker::JFO::EndPoint->new({
        address => $account->{endpoint}{address},
        notify_uri => $uri->as_string });

    $logger->info("JFO endpoint: @{[ $ep->address ]}, notification address: @{[ $ep->notify_uri ]}");

    my $raw_args = {
        name => $c->{account},
        endpoint => $ep,
        params => {
            type => 'Futures',
            exchange => $c->{exchange},
            code => $c->{code},
            year => $near->year, month => $near->month,
        }
    };
    return $raw_args;
}

sub jfo_broker {
    my ($cname, $port, %args) = @_;
    my $c = jfo_config->{commodities}{$cname} or die "$cname not found in config";
    my $traits = ['Position', 'Stop', 'Timed', 'Update', 'Attached', 'OCA'];

    if ($c->{backends}) {
        require TradeSpring::Broker::Partition;
        my $backends = [map {
            { %$_,
               broker => TradeSpring::Broker::JFO->new_with_traits(
                   %{raw_jfo_broker_args(jfo_config->{commodities}{$_->{broker}}, $port)},
                   traits => ['Position'],
                   $args{daytrade} ? (position_effect_open => '') : ())
           }
        } @{$c->{backends}}];
        my $broker = TradeSpring::Broker::Partition->new_with_traits
            ( backends => $backends,
              traits => $traits,
              $args{daytrade} ? (position_effect_open => '') : (),
          );
        return $broker;
    }

    my $raw_args = raw_jfo_broker_args($c, $port);
    my $broker = TradeSpring::Broker::JFO->new_with_traits
        ( %$raw_args,
          traits => $traits,
          $args{daytrade} ? (position_effect_open => '') : (),
      );
    $logger->info("JFO broker created: ".join(' ', @$traits));
    return $broker;
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
    my ($name, $calc, $broker, $fh, $load_day_from_db, $range, $use_cache) = @_;
    $fh ||= \*STDOUT;
    try { eval $name->meta }
    catch {
        $name->require or die $@;
    };
    $name->init;

    my @args = (broker => $broker, use_cache => $use_cache,
                $range ? (range => $range) : ());

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

    my ($first, $last) = @{$range || []};
    $strategy->load((defined $first ? $first-1 : $calc->prices->count-1),
                    $first, $last);

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
        my $ds = $dt->epoch + $strategy->current_min * 60;

        return if
            none { $_->{order}{timed}
                   ? $ds >= $_->{order}{timed}
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
        return $order->{dir} * ( $order->{dir} > 0 ? $strategy->low : $strategy->high)
            <= $order->{price} * $order->{dir};
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
    my $ts = $dt->epoch + $strategy->current_min * 60;
    my $d = $strategy->date; # XXX: fix for timed orders
    @p = ($strategy->open, @p);
    my %seen = map { $_ => 1 } @p;
    while (my $tick = shift @p) {
        my $bts = $lb->{timestamp};
        $lb->on_price($tick, undef, { timestamp => $ts - $nsecs});
        for my $o (grep { $_->{order}{type} eq 'stp' || $_->{order}{type} eq 'lmt' }
                       values %{$lb->orders} ) {
            my $p = $o->{order}{price};
            $p = $o->{order}{dir} > 0 ? ceil($p) : floor($p);
            if ($bts != $lb->{timestamp}) { # some new order happened
                unshift @p, $tick;
            }
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
            fitf_store($daytrade->calc->code, $date)) or die;
    }


    my ($start, $end);
    if ($daytrade->calc->prices->timeframe == $Finance::GeniusTrader::DateTime::DAY) {
        $start = $fitf->header->{start}[0];
        $end = $fitf->header->{end}[0];
    }
    else {
        $start = $Strp_time->parse_datetime($daytrade->date($daytrade->i-1))->epoch;
        $end =   $Strp_time->parse_datetime($daytrade->date)->epoch;
    }

    my $start_b = $fitf->bar_at($start);
    my $end_b = $fitf->bar_at($end);

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

my $fitf_format;
sub fitf_store {
    my $code = shift;
    my $date = shift;
    unless ($fitf_format) {
        my $contract = TradeSpring->config->get_instrument($code)
            or die "instrument $code not found";
        my $db_path = $contract->attr('fitf.archive')
            or die "fitf.archive not found for instrument $code";
        $db_path =~ s/\%c/$code/g;
        $fitf_format = DateTime::Format::Strptime->new(
            pattern     => $db_path,
            time_zone   => $contract->time_zone );
    }
    Carp::croak "fitf_store must be called with date" unless $date;
    return $fitf_format->format_datetime($date);
}

use Finance::GeniusTrader::Calculator;
use Term::ANSIScreen qw(:color :screen);

sub livespring {
    my ($pagm, $client, $myself, $code, $tf,
        $logger, $strategy_name, $broker, $daytrade, $init_cb, $loadcnt) = @_;

    my $session_cb = sub {
        my $session = shift;
        my $start = $session->{session_start};
        if ($init_cb) {
            if ($start - 450 > AnyEvent->time) {
                my $w; $w = AnyEvent->timer(
                    after => $start - 450 - AnyEvent->time,
                    cb => sub {
                        $init_cb->($session);
                        undef $w;
                    });
            }
            else {
                $init_cb->($session);
            }
        }
    };

    my $strategy;
    my $calc;
    $client->poll(sub {
        my $msg = shift;

        if (!exists $msg->{type} && $msg->{price}) { # tick
            $broker->on_price($msg->{price}, $msg->{volume}, { timestamp => $msg->{timestamp} } );
        }
        else {
            $logger->error("unhandled message: ".Dumper($msg)); use Data::Dumper;
        }
        return 1;

    });

    init_quote(
        code => $code,
        tf => $tf,
        bus => $pagm->bus,
        pagm => $pagm,
        loadcnt => $loadcnt,
        on_load => sub {
            my ($session, $_calc) = @_;
            my $end = $session->{session_end};
            if ($end > AnyEvent->time) {
                my $w; $w = AnyEvent->timer(
                    after => $end - AnyEvent->time,
                    cb => sub {
                        $strategy->end;
                        undef $w;
                    });
            }
            $session_cb->($session);

            local $_; # XXX: something is modifying $_ and cause anymq topic reaper trouble
            $calc = $_calc;
            $strategy = TradeSpring::load_strategy($strategy_name, $calc, $broker);

            eval { pre_run_strategy($session, $strategy) } if $daytrade;

            $client->subscribe($myself->bus->topic($session->{tick_channel}));

            init_terminal($pagm->bus, $session, $calc, $tf);
        },
        on_bar => sub {
            $strategy->i($calc->prices->count-1);
            $strategy->run();
        }
    );
}

sub init_terminal {
    my ($bus, $session, $calc, $tf) = @_;

    my $client = $bus->new_listener;
    $client->on_error(sub {
                          $logger->fatal(join(',',@_));
                      });

    $client->poll(sub {
        my $msg = shift;

        if (!exists $msg->{type} && $msg->{price}) { # tick
            my $time = $msg->{time};

            {
                no warnings 'uninitialized';
                local ($^W) = 0;
                print clline;
                print (color 'white');
                print $time.' = ';
                my $pp = $calc->prices->at($calc->prices->count-1);
                my $c = $msg->{price}> $pp->[$CLOSE] ? 'red' : 'green';
                print colored [$c], sprintf(" P: %5d V: %6d", $msg->{price}, $msg->{volume} );
                print "\r";
            }
        }
        elsif ($msg->{type} eq 'agbar') { # bar
            my $prices = $msg->{data};

            {
                no warnings 'uninitialized';
                local ($^W) = 0;

                print clline;
                print (color 'white');
                print $prices->[$DATE].' = ';
                print color $prices->[$CLOSE] > $prices->[$OPEN] ? 'red' : 'green';
                print join('',map { sprintf("%5d", $_) } @{$prices}[0..3]);
                printf (" V: %6d", $prices->[4]);
                print color 'reset';
                print $/;
            }
        }
        else {
            $logger->error("unhandled message: ".Dumper($msg)); use Data::Dumper;
        }
        return 1;

    });

    $client->subscribe($bus->topic($session->{tick_channel}));
    $client->subscribe($bus->topic($session->{ag_channel}.$tf));
}

sub pre_run_strategy {
    my ($session, $strategy) = @_;
    # XXX: load existing position?
    my $calc = $strategy->calc;
    my $p = $calc->prices;
    my $start = $calc->prices->count-1;
    my $dt = DateTime->now(time_zone => $session->{timezone});
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

sub init_quote {
    my %args = @_;
    my $timeframe = Finance::GeniusTrader::DateTime::name_to_timeframe($args{tf});
    my $calc;

    my $bus = $args{bus};

    my $myself = $bus->topic("livespring-$$");
    my $client = $bus->new_listener($myself);
    $client->on_error(sub {
                          $logger->fatal(join(',',@_));
                      });

    my $pagm = $args{pagm} || $bus->topic({name => 'pagmctrl.'.$args{node}});

    my $session;
    $client->poll(
        sub {
            my $msg = shift;

            if ($msg->{type} eq 'pagm.session') {
                $pagm->publish({type => 'pagm.history', code => $args{code},
                                timeframe => $args{tf}, count => $args{loadcnt} || 300,
                                reply => $myself->name });
                $session = $msg;
            }
            elsif ($msg->{type} eq 'history') {
                my $prices = $msg->{prices};
                $logger->info("loaded ".(scalar @{$prices})." items for $args{code}/$args{tf} from pagm: $prices->[0][5] - $prices->[-1][5]");
                my $p = Finance::GeniusTrader::Prices->new;
                $p->{prices} = $prices;
                $p->set_timeframe($timeframe);
                $calc = Finance::GeniusTrader::Calculator->new($p);
                $client->subscribe($bus->topic($session->{ag_channel}.$args{tf}));
                $args{on_load}->($session, $calc);
            }
            elsif ($msg->{type} eq 'agbar') {
                my $prices = $msg->{data};
                $calc->prices->add_prices($prices);
                $args{on_bar}->();
            }
            else {
                $logger->error("unhandled message: ".Dumper($msg)); use Data::Dumper;
            }
            return 1;
        });

    $pagm->publish({ type => 'pagm.session',
                     code => $args{code},
                     reply => $myself->name });
}

sub load_broker {
    my ($config, $deployment, $instrument) = @_;
    my $contract = $instrument->near_term_contract(DateTime->now);
    load_broker_by_contract($contract, $config, $deployment);
}

sub load_broker_by_contract {
    my ($contract, $config, $deployment) = @_;

    if ($config->{class} eq 'IB') {
        return load_ib_broker($contract, $config, $deployment);
    }
    elsif ($config->{class} eq 'JFO') {
        return load_jfo_broker($contract, $config, $deployment);
    }
    elsif ($config->{class} eq 'SYNTH') {
        return load_synth_broker($contract, $config, $deployment);
    }
    else {
        die "unknown broker class: $config->{class}";
    }
}

sub parse_broker_spec {
    my $broker_spec = shift;
    my ($class, $broker_name, $args) =
        $broker_spec =~ m/^(\w+)\[(\w+)(?:,(.*?))?\]$/x;
    return ($class, $broker_name, $args ? map { split /=/ } split /,/, $args : ());
}

sub load_synth_broker {
    my ($contract, $config, $deployment) = @_;
    my $jfo = TradeSpring->config->get_children( "synth.$config->{name}" )
        or die "SYNTH config $config->{name} not found";

    my $brokers = $jfo->{broker};
    $brokers = [$brokers] unless ref $brokers;
    my $backends = [];

    for my $broker_spec (@$brokers) {
        my ($class, $broker_name, %args) = parse_broker_spec($broker_spec);
        push @$backends, { %args,
                           broker => load_broker_by_contract($contract, {%$config,
                                                                         class => $class,
                                                                         name => $broker_name, %args}, {})
                       };
    }

    require TradeSpring::Broker::Partition;
    TradeSpring::Broker::Partition->new_with_traits
        ( backends => $backends,
          traits => ['Position', 'Stop', 'Timed', 'Update', 'Attached', 'OCA'],
      );
}

sub load_jfo_broker {
    my ($contract, $config, $deployment) = @_;
    require TradeSpring::Broker::JFO;
    require TradeSpring::Broker::JFO::EndPoint;
    my $jfo = TradeSpring->config->get_children( "jfo.$config->{name}" )
        or die "JFO config $config->{name} not found";
    my $broker_name = $jfo->{broker};

    my $symbol = $config->{symbol} || $contract->attr($broker_name.'.symbol') || $contract->futures->code;
    my $exchange = $contract->exchange->attr($broker_name.'.exchange') or die;

    my $uri = URI->new($jfo->{notify_uri}."/".$config->{name});

    if ((my $port = $config->{port}) && !$config->{keepaddress}) {
        my $address = Net::Address::IP::Local->connected_to(URI->new($jfo->{endpoint})->host);

        $uri->host($address);
        $uri->port($port);
    }

    my $ep = TradeSpring::Broker::JFO::EndPoint->new({
        address => $jfo->{endpoint},
        notify_uri => $uri->as_string });

    $logger->info("JFO endpoint: @{[ $ep->address ]}, notification address: @{[ $ep->notify_uri ]}");

    my $raw_args = {
        name => $config->{name},
        endpoint => $ep,
        params => {
            type => 'Futures',
            exchange => $exchange,
            code => $symbol,
            year => $contract->expiry_year, month => $contract->expiry_month,
        }
    };

    $logger->info("[$config->{name}] ". $contract->code." as $exchange $symbol");

    my $traits = ['Position', 'Stop', 'Timed', 'Update', 'Attached', 'OCA'];

    my $broker = TradeSpring::Broker::JFO->new_with_traits
        ( %$raw_args,
          traits => $traits,
          $deployment->{daytrade} ? (position_effect_open => '') : (),
      );
    return ($broker,
            sub {
                my ($file, $ready_cv) = @_;
                use Plack::Builder;
                my $app = builder {
                    TradeSpring::Broker::JFO->mount_instances({ ready_cv => $ready_cv,
                                                                check => 90 });
                    mount '/' => sub {
                        return [404, ['Conetent-Type', 'text/plain'], ['not found']];
                    };
                };
                local @ARGV = split(/\s+/, $config->{opts});
#die $config->{port}.join(',',@ARGV);

                TradeSpring::Broker::JFO->app_loader($app, $file, $config->{port} || 5019);
            });
}

my %tws;
sub load_ib_broker {
    my ($contract, $config) = @_;
    require TradeSpring::Broker::IB;

    my $ib = TradeSpring->config->get_children( "ib.$config->{name}" )
        or die "IB config $config->{name} not found";

    my $tws = $tws{$config->{name}} ||= AE::TWS->new(host => $ib->{host}, port => $ib->{port},
                                                     client_id => $config->{client_id}+9);
    my $symbol = $config->{symbol} || $contract->attr('ib.symbol') || $contract->futures->code;
    my $exchange = $contract->exchange->attr('ib.exchange') or die;

    TradeSpring::Broker::IB->new(
        tws => $tws,
        exchange => $exchange,
        symbol => $symbol,
        expiry => $contract->expiry,
        tz => $contract->time_zone,
        divisor => 1 / $contract->tick_size,
    );
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
