package TradeSpring::FrameVal::CrossOver;
use Moose;
use methods-invoker;

extends 'TradeSpring::FrameVal';;

has a => (
    is => "ro",
    isa => 'TradeSpring::FrameVal',
);

has b => (
    is => "ro",
    isa => 'TradeSpring::FrameVal',
);

method do_get {
    my ($av, $bv) = ($->a, $->b);
    return unless defined $av && $bv;
    return unless defined $->a->[1] && $->b->[1];
    if ($->a->[1] < $->b->[1] && $->a > $->b) {
        return 1
    }
    elsif ($->a->[1] > $->b->[1] && $->a < $->b) {
        return -1;
    }
    return 0;
}

__PACKAGE__->meta->make_immutable;
