package TradeSpring::I::Range;
use Moose;

extends 'TradeSpring::I';

sub do_calculate {
    my $self = shift;

    $self->high - $self->low;
}

1;
