package TradeSpring::Util;
use strict;
use warnings;
use 5.008_001;
use base 'Exporter';

our @EXPORT = our @EXPORT_OK =
    qw(parse_broker_spec
       broker_args_from_spec
       init_quote
       local_broker
  );

use Log::Log4perl;
use Log::Log4perl::Level;

my $logger;

sub logger {
    unless (Log::Log4perl->initialized()) {
        Log::Log4perl->easy_init($INFO);
    }
    $logger ||= Log::Log4perl->get_logger("TradeSpring.Util");
}

sub local_broker {
    require TradeSpring::Broker::Local;
    TradeSpring::Broker::Local->new_with_traits(
        traits => ['Stop', 'Timed', 'Update', 'Attached', 'OCA'],
        hit_probability => 1,
    );
}

sub parse_broker_spec {
    my $broker_spec = shift;
    my ($class, $broker_name, $args) =
        $broker_spec =~ m/^(\w+)\[(\w+)(?:,(.*?))?\]$/x;
    return ($class, $broker_name, $args ? map { split /=/ } split /,/, $args : ());
}

sub broker_args_from_spec {
    my $broker_spec = shift;
    my ($class, $broker_name, %args) = parse_broker_spec($broker_spec)
        or die "failed to parse broker spec: $broker_spec";
    return ( class => $class,
             name => $broker_name,
             %args );
}

sub init_quote {
    my %args = @_;
    my $calc;

    my $bus = $args{bus};

    my $myself = $bus->topic("livespring-$$");
    my $client = $bus->new_listener($myself);
    $client->on_error(sub {
                          logger->fatal(join(',',@_));
                      });

    my $pagm = $args{pagm} || $bus->topic({name => 'pagmctrl.'.$args{node}});

    my $session;
    $client->poll(
        sub {
            my $msg = shift;

            if ($msg->{type} eq 'pagm.session') {
                $session = $msg;
                if ($args{loadcnt}) {
                    $pagm->publish({type => 'pagm.history', code => $args{code},
                                    timeframe => $args{tf}, count => $args{loadcnt} || 300,
                                    reply => $myself->name });
                }
                else {
                    $args{on_load}->($session);
                }
            }
            elsif ($msg->{type} eq 'history') {
                my $prices = $msg->{prices};
                logger->info("loaded ".(scalar @{$prices})." items for $args{code}/$args{tf} from pagm: $prices->[0][5] - $prices->[-1][5]");
                my $p = Finance::GeniusTrader::Prices->new;
                my $timeframe = Finance::GeniusTrader::DateTime::name_to_timeframe($args{tf});
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
                logger->error("unhandled message: ".Dumper($msg)); use Data::Dumper;
            }
            return 1;
        });

    $pagm->publish({ type => 'pagm.session',
                     code => $args{code},
                     reply => $myself->name });
}


1;
