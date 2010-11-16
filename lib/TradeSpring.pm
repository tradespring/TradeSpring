package TradeSpring;

use strict;
use 5.008_001;
our $VERSION = '0.01';
use Finance::GeniusTrader::Prices;
use UNIVERSAL::require;
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
    if (-e $logconf) {
        Log::Log4perl::init_and_watch($logconf, 60);
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

    my $traits = ['Stop', 'Timed', 'Update', 'Attached', 'OCA'];
    unshift @$traits, 'Position', unless $args{daytrade};

    my $broker = TradeSpring::Broker::JFO->new_with_traits
        ( endpoint => $endpoint,
          params => {
              type => 'Futures',
              exchange => $c->exchange,
              code => $c->code,
              year => $near->year, month => $near->month,
          },
          traits => $traits );
    $logger->info("JFO broker created: ".join(' ', @$traits));
    return ($broker, $c);
}

sub load_calc {
    my ($code, $tf_name) = @_;
    my $tf = Finance::GeniusTrader::DateTime::name_to_timeframe($tf_name);
    find_calculator(create_db_object(), $code, $tf, 1);
}

sub load_strategy {
    my ($name, $calc, $broker) = @_;
    $name->require or die $@;
    $name->init;

    my @args = (broker => $broker);

    my $meta = Moose::Meta::Class->create_anon_class(
        superclasses => [$name],
        roles        => [qw(MooseX::SimpleConfig MooseX::Getopt)],
        cache        => 1,
    );

    if ($meta->find_attribute_by_name('dcalc')) {
        my $dcalc = Storable::dclone($calc);
        $dcalc->create_timeframe($Finance::GeniusTrader::DateTime::DAY);
        $dcalc->set_current_timeframe($Finance::GeniusTrader::DateTime::DAY);
        push @args, (dcalc => $dcalc);
    }

    return $meta->name->new_with_options( calc => $calc, @args );

}

use DateTime::Format::Strptime;
my $Strp = DateTime::Format::Strptime->new(
    pattern     => '%F',
#    time_zone   => 'Asia/Taipei',
);


sub run_trade {
    my ($strategy, $i, $sim) = @_;

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
    my $lb = $strategy->broker;

    if ($sim) {
        sim_prices($strategy, $lb);
    }
    else {
        my ($date, $time) = split(/ /, $strategy->calc->prices->at($i)->[$DATE]);
        my $dt = $Strp->parse_datetime($date);
        run_tick_until($strategy, $lb, $dt, $time)
            if (keys %{$lb->orders});
    }

    $strategy->run();
}

use POSIX qw(ceil floor);

sub sim_prices {
    my ($daytrade, $lb) = @_;
    if (keys %{$lb->orders}) {
        my @p;
        for my $o (grep { $_->{order}{type} eq 'stp' }
                values %{$lb->orders} ) {
            my $p = $o->{order}{price};
            $p = $o->{order}{dir} > 0 ? ceil($p) : floor($p);
            unshift @p, ($p)
                if $p < $daytrade->high && $p > $daytrade->low;
        }
        push @p, map { $daytrade->$_ } qw(high low);
        my @prices_down = sort { $b <=> $a } grep { $_ <= $daytrade->open } @p;
        my @prices_up   = sort { $a <=> $b } grep { $_ > $daytrade->open } @p;
        if ($daytrade->close > $daytrade->open) {
            @p = (@prices_down, @prices_up)
        }
        else {
            @p = (@prices_up, @prices_down)
        }
        my $d = $daytrade->date;
        $lb->on_price($_, undef, $d) for ($daytrade->open, @p, $daytrade->close);
    }
}



my $current_date;
my $continue;
my $cv;
my $source;
my $buffer;
sub run_tick_until {
    my ($daytrade, $lb, $date, $time) = @_;

    $logger->debug("run tick until: $time ".$daytrade->date);
    if (!$current_date || $current_date ne $date->ymd) {
        $buffer = [];
        $current_date = $date->ymd;
#        warn "==> new date: $current_date".$/;
        use Finance::TW::TAIFEX;
        my $taifex = Finance::TW::TAIFEX->new($date);

        my $contract = $taifex->product('TX')->near_term($taifex->context_date);
        use AnyEvent;

        use GTL::Source::File;
        my $rpt_f = Finance::GeniusTrader::Conf::get("GLT::taifex_rpt_dir")."/$current_date.rpt" or die " can't find $date.rpt";
        $cv = AE::cv;
        $source = GTL::Source::File->new(
            tick_delay => 0,
            second_delay => 0,
            rpt => $rpt_f,
            contract_name => 'TX', contract_month => $contract,
            cb_done => $cv,
        );
        my $done = 0;
        $continue = AE::cv;
        my (undef, $first) = split(/ /,$daytrade->date($daytrade->i - 1));
        $first =~ s/://g;
        $first =~ s/^0//;
        $source->start(
            sub {
                return if $done;
                return unless $_[0]{time} >= $first;

                push @$buffer, $_[0];
            });
        $cv->recv;
    }

    $time =~ s/://g;
    $time =~ s/^0//;
#    warn "=> pop buffer until $time ".(scalar @$buffer).' / '.$buffer->[0]{time};
    Carp::confess unless $buffer->[0]{time};

    my (undef, $first) = split(/ /,$daytrade->date($daytrade->i - 1));
    $first =~ s/://g;
    $first =~ s/^0//;

    while (scalar @$buffer && $buffer->[0]{time} < $time) {
        my $f = shift @$buffer;
        my ($date, $time) = @{$f}{qw(date time)};

        next unless $f->{time} >= $first;

        $date =~ s/(\d\d\d\d)(\d\d)(\d\d)/$1-$2-$3/;
        $time =~ s/(\d\d?)(\d\d)(\d\d)/$1:$2:$3/;
        $time = '0'.$time unless substr($time, 0, 1) eq '1';
        $lb->on_price($f->{price}, $f->{volume}, "$date $time");
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
