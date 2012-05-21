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

has loose => (is => "ro", isa => "Bool", default => sub { 0 });

method do_get {
    my ($av, $bv) = ($->a, $->b);
    return unless defined $av && $bv;
    return unless defined $->a->[1] && $->b->[1];
    if ($->a->[1] <= $->b->[1] && $->a > $->b) {
        return $->a->[1] < $->b->[1] || $->loose ? 1 : 0;
    }
    elsif ($->a->[1] >= $->b->[1] && $->a < $->b) {
        return $->a->[1] > $->b->[1] || $->loose ? -1 : 0;
    }
    return 0;
}

__PACKAGE__->meta->make_immutable;
