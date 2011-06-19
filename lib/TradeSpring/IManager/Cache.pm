package TradeSpring::IManager::Cache;
use Method::Signatures::Simple;
use Moose;
use Set::IntSpan;
use Redis::hiredis;
use Finance::GeniusTrader::Prices;

extends 'TradeSpring::IManager';

with 'MooseX::Log::Log4perl';

around 'indicator_traits' => sub {
    my ($next, $self) = @_;
    my $traits = $self->$next;
    $traits = [ @{ $traits || [] }, 'Cached' ];
    return $traits;
};

around 'load' => sub {
    my ($next, $self, $name, %args) = @_;
    $self->$next($name, %args);
};

method get_values($name, $start, $end, $use_cache) {
    my $ix = $self->indicators->{$name};
    my $object_name = $ix->as_string;

    $ix->{span} ||= Set::IntSpan->new([]);
    my $diff = Set::IntSpan->new([[$start, $end]])->diff($ix->{span});
    for ($diff->spans) {
        my ($start, $end) = @$_;
        $self->populate_indicator($ix, $object_name, $start, $end, $use_cache);
        $ix->{span}->U([[$start, $end]]);
    }
}

method populate_indicator($object, $object_name, $start, $end, $use_cache) {

    my $do_calc = sub {
        my ($start, $end ) = @_;
        for my $i ($start..$end) {
            $self->frame->i($i);
            $object->do_calculate;
        }
    };

    return $do_calc->($start, $end) unless $use_cache;

    $self->populate_cache(
        'tscache', $object_name, $start, $end,
        $do_calc,
        sub {
            # XXX: this stringifies thing
            [map { ref $object->cache->{$_} ? join(',', @{$object->cache->{$_}}) : $object->cache->{$_} }
                 ($_[0] .. $end) ]
        },
        sub {
            my $vals = $_[0];
            for (0..$#{$vals}) {
                $object->cache->{$_+$start} = $vals->[$_] eq '' ? undef : [ map { 0+$_} split/,/, $vals->[$_] ];
            }
        }
    );
}

use constant TSCACHE_VERSION => 1;

method populate_cache($prefix, $object_name, $start, $end, $calculate, $vals, $restore) {
    $self->log->info("populating cache for $object_name till $end");
    my $calc = $self->frame->calc;

    my $tf = Finance::GeniusTrader::DateTime::name_of_timeframe($calc->prices->timeframe);
    my $code = $calc->code;

    my $key = join(':', $prefix, $code, $tf, $object_name);

    my $redis = Redis::hiredis->new();
    $redis->connect('127.0.0.1', 6379);

    my $info = { @{ $redis->command([hgetall => "$key:meta"]) } };
    my ($start_d, $end_d) = map { $calc->prices->at($_)->[$DATE] } 0, $end || $calc->prices->count-1;
    my ($cache_start, $cache_end) = (0, $end || $calc->prices->count-1);
    if (%$info) {
        if ($info->{version} && $info->{version} != TSCACHE_VERSION) {
            $self->log->warn("version mismatch, discard");
            $info = {};
            $redis->command(["del" => $key]);
        }

        my $cache_len = $redis->command([llen => $key]);
        if ($info && $start_d eq $info->{start} && $info->{count}+1 == $cache_len ) {
            unless ($end_d eq $info->{end}) {
                $cache_start = $calc->prices->date($info->{end}) + 1;
                $self->log->info("updating cache from $cache_start");
                $info = {};
            }
        }
        else {
            $self->log->warn("$key start or cnt mismatch, discarded. $start_d / $cache_len".Dumper($info));use Data::Dumper;
            $info = {};
            $redis->command(["del" => $key]);
        }

        $self->log->info("loading from cache: $key: $start..$end");
        $restore->($redis->command([lrange => $key,  $start, $end]) );
    }

    unless (%$info) {
        $calculate->($cache_start, $cache_end);
        my $info = {
            version => TSCACHE_VERSION,
            count => $cache_end,
            start => $start_d,
            end   => $end_d,
        };

        $redis->command([hmset => "$key:meta", %$info]);

        for my $val (@{ $vals->($cache_start) }) {
            $redis->command([rpush => $key, $val // '']);
        }
    }
}


__PACKAGE__->meta->make_immutable;
no Moose;
1;
