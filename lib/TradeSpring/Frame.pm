package TradeSpring::Frame;
use Moose;

use Finance::GeniusTrader::Prices;
use Finance::GeniusTrader::DateTime;
use Method::Signatures::Simple;
use Number::Extreme;

method debug($message, $i) {
    warn $self->date($i).' '.$message.$/;
}

has i => (is => "rw", isa => "Int", trigger => method { $self->_set_i(@_) } );

has calc => (is => "ro", isa => "Finance::GeniusTrader::Calculator",
             required => 1);

has hour => (is => "rw");
has last_hour => (is => "rw");
has is_dstart => (is => "rw", default => sub { 1 });
has current_min => (is => "rw", isa => "Int");

has nmin => (
    is => "rw",
    isa => "Int",
    lazy_build => 1
);

method _build_nmin {
    Finance::GeniusTrader::DateTime::timeframe_ratio(
        $self->calc->prices->timeframe,
        $PERIOD_1MIN);
}

method _set_i($i) {
    my ($hh, $mm) = $self->date($i) =~ m/ (\d\d):(\d\d)/ or return;
    my $hour = $hh*100+$mm;
    my $old = $self->hour;
    $self->hour($hour);

    if (!$old || $hour < $old ) {
        $self->is_dstart(1)
    }
    else {
        $self->is_dstart(0);
    }

    $self->last_hour($old);

    $self->current_min($hh * 60 + $mm);
}

method prices {
    $self->calc->prices->at(shift // $self->i);
}

method open {
    $self->prices(@_)->[$OPEN]
}

method high {
    $self->prices(@_)->[$HIGH]
}

method low {
    $self->prices(@_)->[$LOW]
}

method close {
    $self->prices(@_)->[$CLOSE]
}

method date {
    $self->prices(@_)->[$DATE]
}

method volume {
    $self->prices(@_)->[$VOLUME]
}

method highest_high {
    my $p = $self->calc->prices->{prices};
    Number::Extreme->max(sub { $p->[$_][$HIGH] });
}

method lowest_low {
    my $p = $self->calc->prices->{prices};
    Number::Extreme->min(sub { $p->[$_][$LOW] });
}


1;
