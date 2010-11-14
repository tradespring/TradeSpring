package TradeSpring::Frame;
use Moose;

use Finance::GeniusTrader::Prices;
use Method::Signatures::Simple;

method debug($message, $i) {
    warn $self->date($i).' '.$message.$/;
}

has i => (is => "rw", isa => "Int");

has calc => (is => "ro", isa => "Finance::GeniusTrader::Calculator",
             required => 1);

has day => (is => "ro", isa => "DateTime");

method hour {
    my ($hh, $mm) = $self->date(@_) =~ m/ (\d\d):(\d\d)/;
    return $hh*100+$mm;
}

method is_dstart {
    my $i = shift // $self->i;
    return 1 if $i == 0;
    $self->hour($i) < $self->hour($i-1);
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

1;
