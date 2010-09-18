package TradeSpring::Frame;
use Moose::Role;

use Finance::GeniusTrader::Eval;
use Finance::GeniusTrader::Prices;
use Finance::GeniusTrader::Calculator;
use Finance::GeniusTrader::Eval;
use Method::Signatures::Simple;

sub has_indicator {
    my ($name, $spec) = @_;
    my $pkg = (caller())[0];
    my $meta = $pkg->meta;
    my ($mod, $arg) = split(/ /, $spec, 2);

    my $which = $mod =~ s#/(\d+)## ? $1-1 : 0;
    my $object = create_standard_object($mod, $arg // ());
    my $object_name = $object->get_name($which);
    if ($object->isa('Finance::GeniusTrader::Indicators')) {
        $meta->add_method(
            $name =>
                sub {
                    my ($self, $i) = @_;
                    $i //= $self->i;
                    my $indicators = $self->calc->indicators;
                    $object->calculate( $self->calc, $i )
                        unless $indicators->is_available( $object_name, $i );
                    $indicators->get( $object_name, $i );
                }
            )
    }
    elsif ($object->isa('Finance::GeniusTrader::Signals')) {
        $meta->add_method(
            $name =>
                sub {
                    my ($self, $i) = @_;
                    $object->detect( $self->calc, $i // $self->i);
                    $self->calc->signals->get( $object_name, $i // $self->i );
                }
            )
    }
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
