package TradeSpring::BracketOrder;
use Moose::Role;
use Method::Signatures::Simple;

has 'position' => (is => "rw", isa => "TradeSpring::Position", clearer => 'clear_position');

before 'cleanup' => method {
    $self->clear_position;
};

method pending_order {
    my $p = $self->position or return 0;

    $p->qty - $p->position_entered;
}

method position_entered {
    my $p = $self->position or return 0;
    return $p->position_entered;
}

method update_stp_price($price, $cb) {
    my $stp = $self->broker->get_order($self->position->stp_id);

    $self->broker->update_order($self->position->stp_id, $price,
                                undef, $cb)
        if $self->bt($price, $stp->{order}{price});
}

method new_bracket_order ($entry_order, $stp, $tp, %args) {
    my $on_exit = delete $args{on_exit};
    my $p = TradeSpring::Position->new(
        broker => $self->broker, %args,
        on_exit => sub {
            $on_exit->(@_);
            $self->clear_position;
        },
        direction => $entry_order->{dir}, # deprecate later
    );

    $p->create($entry_order, $stp, $tp);
    $self->position($p);
}

method cancel_pending_order {
    $self->broker->cancel_order( $self->position->entry_id, sub {
                                     $self->log->info("order @{[ $self->entry_id]} cancelled: ".join(',', @_) );
                                 });
    $self->clear_position unless $self->position_entered;
}

1;
