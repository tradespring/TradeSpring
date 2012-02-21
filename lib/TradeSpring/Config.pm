package TradeSpring::Config;
use strict;
use methods;
use base qw(Config::GitLike);
use Finance::Instrument;
use TradeSpring::Util;

unless ($ENV{TRADESPRING_NO_GT}) {
    eval { require Finance::GeniusTrader::Conf; 1 }
        and Finance::GeniusTrader::Conf::load();
}

use Log::Log4perl;
use Log::Log4perl::Level;

my $logger;

sub logger {
    unless (Log::Log4perl->initialized()) {
        Log::Log4perl->easy_init($INFO);
    }
    $logger ||= Log::Log4perl->get_logger("TradeSpring.Config");
}

my $global = Finance::Instrument::Domain->global;
$global->load_default_exchanges;

method new($class:) {
    my $self = $class->SUPER::new( confname => 'tradespring', @_);
    $self->init;

    return $self;
}

method init {
    my $flat = $self->get_regexp( key => "exchange\.");
    my $attr = {};
    for (keys %$flat) {
        my $val = $flat->{$_};
        s/exchange\.(.*?)\.// or die;
        $attr->{$1}{$_} = $val;
    }
    for my $name (keys %$attr) {
        if (my $exchange = $global->get_exchange($name)) {
            $exchange->attr($_ => $attr->{$name}{$_}) for keys %{$attr->{$name}};
        }
    }
}

method get_instrument($name) {
    my $instrument = $global->get($name);
    unless ($instrument) {
        my $yml = $self->get( key => "instrument.$name.config");
        $instrument = -e $yml ? $global->load_instrument_from_yml($yml)
                              : $global->load_default_instrument("futures/$name");
        my $attr = $self->get_children( "instrument.$name" );
        for my $key (keys %$attr) {
            my $val = $attr->{$key};
            $instrument->attr($key => $val);
        }
    }
    return $instrument;
}

method get_children($prefix) {
    my $attr = $self->get_regexp( key => "$prefix\\." );
    return unless keys %$attr;
    return $self->subsection($attr, $prefix);
}

method subsection($attr, $prefix) {
    my $config = { map {
        my $key = $_;
        s/\Q$prefix\E\.//
            ? ( $_ => $attr->{$key} ) : ()
    } keys %$attr };
    keys %$config ? $config : undef;
}

method get_deployment($name) {
    my $d = $self->get_children("deployment.$name");
    $d->{strategy} = [$d->{strategy}] unless ref $d->{strategy};
    return $d;
}


method load_broker($config, $deployment, $instrument) {
    my $contract = $instrument->near_term_contract(DateTime->now);
    $self->load_broker_by_contract($contract, $config, $deployment);
}

method load_broker_by_contract($contract, $config, $deployment) {
    if ($config->{class} eq 'IB') {
        return $self->load_ib_broker($contract, $config, $deployment);
    }
    elsif ($config->{class} eq 'JFO') {
        return $self->load_jfo_broker($contract, $config, $deployment);
    }
    elsif ($config->{class} eq 'SYNTH') {
        return $self->load_synth_broker($contract, $config, $deployment);
    }
    else {
        die "unknown broker class: $config->{class}";
    }
}

method load_synth_broker($contract, $config, $deployment) {
    my $jfo = $self->get_children( "synth.$config->{name}" )
        or die "SYNTH config $config->{name} not found";

    my $brokers = $jfo->{broker};
    $brokers = [$brokers] unless ref $brokers;
    my $backends = [];
    my @loops;
    for my $broker_spec (@$brokers) {
        my ($class, $broker_name, %args) = parse_broker_spec($broker_spec)
            or die "failed to parse broker spec: $broker_spec";

        my ($broker, $loop) =  $self->load_broker_by_contract($contract,
                                                             {%$config,
                                                              class => $class,
                                                              name => $broker_name,
                                                              wrapped => 1,
                                                              %args
                                                          }, $deployment);
        push @$backends, { %args,
                           broker => $broker
                       };
        push @loops, $loop;
    }

    require TradeSpring::Broker::Partition;
    (TradeSpring::Broker::Partition->new_with_traits
        ( backends => $backends,
          traits => ['Position', 'Stop', 'Timed', 'Update', 'Attached', 'OCA'],
      ), @loops);
}

method load_jfo_broker($contract, $config, $deployment) {
    require TradeSpring::Broker::JFO;
    require TradeSpring::Broker::JFO::EndPoint;
    my $jfo = $self->get_children( "jfo.$config->{name}" )
        or die "JFO config $config->{name} not found";
    my $broker_name = $jfo->{broker};

    my $symbol = $config->{symbol} || $contract->attr($broker_name.'.symbol') || $contract->futures->code;
    my $exchange = $contract->exchange->attr($broker_name.'.exchange') or die;

    my $uri = URI->new($jfo->{notify_uri}."/".$config->{name});

    if ((my $port = $config->{port}) && !$config->{keepaddress}) {
        require Net::Address::IP::Local;
        my $address = Net::Address::IP::Local->connected_to(URI->new($jfo->{endpoint})->host);

        $uri->host($address);
        $uri->port($port);
    }

    my $ep = TradeSpring::Broker::JFO::EndPoint->new({
        address => $jfo->{endpoint},
        notify_uri => $uri->as_string });

    logger->info("JFO endpoint: @{[ $ep->address ]}, notification address: @{[ $ep->notify_uri ]}");

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

    logger->info("[$config->{name}] ". $contract->code." as $exchange $symbol");

    my $traits = ['Position'];
    push @$traits, ('Stop', 'Timed', 'Update', 'Attached', 'OCA')
        unless $config->{wrapped};

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
                TradeSpring::Broker::JFO->app_loader($app, $file, $config->{port} || 5019);
            });
}

my %tws;
method load_ib_broker($contract, $config) {
    require TradeSpring::Broker::IB;

    my $ib = $self->get_children( "ib.$config->{name}" )
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
