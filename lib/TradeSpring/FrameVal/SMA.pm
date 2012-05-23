package TradeSpring::FrameVal::SMA;
use Moose;
use Statistics::Basic qw(nofill);
use Statistics::Basic::Mean;

use methods-invoker;

extends 'TradeSpring::FrameVal';;

has n => (
    is => "ro",
    isa => 'Int',
);

has value => (
    is => "ro",
    isa => 'TradeSpring::FrameVal',
);


has mean => (
    is => "rw",
    lazy_build => 1
);

method _build_mean {
    Statistics::Basic::Mean->new()->set_size($->n);
}

method do_get {
    $->mean->insert( $->value->get );
    return $->mean->query;
    return;
}

__PACKAGE__->meta->make_immutable;
