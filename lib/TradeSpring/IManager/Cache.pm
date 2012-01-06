package TradeSpring::IManager::Cache;
use Method::Signatures::Simple;
use Moose;
use Set::IntSpan;
use Redis::hiredis;
use Finance::GeniusTrader::Prices;

extends 'TradeSpring::IManager';

has redis => (
    is => "rw",
    lazy_build => 1
);

has redis_host => (is => "rw", isa => "Str", default => sub { '127.0.0.1' });
has redis_port => (is => "rw", isa => "Int", default => sub { 6379 });
has redis_password => (is => "rw", isa => "Str", default => sub { '' });


method _build_redis {
    my $redis = Redis::hiredis->new();
    $redis->connect($self->redis_host, $self->redis_port);
    if (length $self->redis_password) {
        my $res = $redis->command([auth => $self->redis_password]);
        die unless $res eq 'OK';
    }

    return $redis;
}

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

method get_values($object, $start, $end, $use_cache) {
    my $object_name = $object->as_string;

    $object->{span} ||= Set::IntSpan->new([]);
    my $diff = Set::IntSpan->new([[$start, $end]])->diff($object->{span});
    for ($diff->spans) {
        my ($start, $end) = @$_;
        $self->populate_indicator($object, $start, $end, $use_cache);
        $object->{span}->U([[$start, $end]]);
    }
}

method calculate_interval($object, $start, $end) {
    for my $i ($start..$end) {
        $self->frame->i($i);
        $object->do_calculate;
    }
}

method populate_indicator($object, $start, $end, $use_cache) {
    my $object_name = $object->as_string;

    return $self->calculate_interval($object, $start, $end) unless $use_cache;

    $self->retrieve_cache('tscache', $object, $start, $end);
}

method prepare($start, $end, $use_cache) {
    for my $object (@{ $self->order }) {
        if ($use_cache) {
            $self->populate_cache('tscache', $object, $end);
        }
        else {
            $self->get_values($object, $start, $end);
        }
    }
}

use constant TSCACHE_VERSION => 1;

method cache_key($prefix, $object) {
    my $calc = $self->frame->calc;
    my $tf = Finance::GeniusTrader::DateTime::name_of_timeframe($calc->prices->timeframe);

    return join(':', $prefix, $calc->code, $tf, $object->as_string);
}

method retrieve_cache($prefix, $object, $start, $end) {
    $self->log->info("retrieve @{[$object->as_string]} from cache: $start..$end");

    my $redis = $self->redis;
    my $key = $self->cache_key($prefix, $object);

    my $info = { @{ $redis->command([hgetall => "$key:meta"]) } };

    $self->log->info("loading from cache: $key: $start..$end");
    my $vals = $redis->command([lrange => $key,  $start, $end]);
    for (0..$#{$vals}) {
        $object->cache->{$_+$start} = $vals->[$_] eq '' ? undef : [ map { 0+$_} split/,/, $vals->[$_] ];
    }
}

method populate_cache($prefix, $object, $end) {
    my $object_name = $object->as_string;
    my $calc = $self->frame->calc;
    $end ||= $calc->prices->count-1;
    my $redis = $self->redis;
    my $key = $self->cache_key($prefix, $object);
    $self->log->info("verifying cache for $key");

    my $info = { @{ $redis->command([hgetall => "$key:meta"]) } };
    my ($start_d, $end_d) = map { $calc->prices->at($_)->[$DATE] } 0, $end;
    my ($cache_start, $cache_end) = (0, $end);

    my $i_version = $object->version || '0.0';

    if (%$info) {
        if ($info->{version} && $info->{version} != TSCACHE_VERSION) {
            $self->log->warn("version mismatch, discard");
            $info = {};
            $redis->command(["del" => $key]);
        }
        elsif (!$info->{iversion} || $info->{iversion} != $i_version) {
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
    }

    unless (%$info) {
        $self->calculate_interval($object, $cache_start, $cache_end);
        $object->{span} ||= Set::IntSpan->new([]);
        $object->{span}->U([[$cache_start, $cache_end]]);

        my $info = {
            version => TSCACHE_VERSION,
            iversion => $i_version,
            count => $cache_end,
            start => $start_d,
            end   => $end_d,
        };

        $redis->command([hmset => "$key:meta", %$info]);

        for ($cache_start .. $cache_end) {
            no warnings 'uninitialized';
            $redis->command([rpush =>
                             $key => join(',', @{$object->cache->{$_}}) // '']);
        }
    }
}


__PACKAGE__->meta->make_immutable;
no Moose;
1;
