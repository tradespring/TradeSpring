package TradeSpring::Config;
use strict;
use methods;
use base qw(Config::GitLike);
use Finance::Instrument;
use Finance::GeniusTrader::Conf;

Finance::GeniusTrader::Conf::load();

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
                              : $global->load_default_instrument($yml);
        my $attr = $self->get_regexp( key => "instrument.$name.");
        for (keys %$attr) {
            my $key = $_;
            my $val = $attr->{$key};
            $key =~ s/instrument\.\Q$name\E\.//;
            $instrument->attr($key => $val);
        }
    }
    return $instrument;
}

1;
