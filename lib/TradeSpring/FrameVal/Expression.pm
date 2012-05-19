package TradeSpring::FrameVal::Expression;
use Moose;
use methods-invoker;
extends 'TradeSpring::FrameVal';

has expression => (is => "ro", isa => "CodeRef");

method set {
    die "expression is readonly";
}

method get($offset) {
    my $i = $->i - ($offset || 0);
    $->cache->{ $i  } ||= do {
        local $->frame->{i} = $i;
        $->expression->($-);
    };
}

__PACKAGE__->meta->make_immutable;
no Moose;
