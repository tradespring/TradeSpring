package TradeSpring::BracketOrder;
use Moose::Role;
use Method::Signatures::Simple;

has 'position' => (is => "rw", isa => "TradeSpring::Position", clearer => 'clear_position');

before 'cleanup' => method {
    $self->clear_position;
};

has order_report => (is => "rw", isa => "Str");

has order_report_fh => (
    is => "rw",
    lazy_build => 1
);

method _build_order_report_fh {
    $self->order_report or return;

    open my $fh, '>>', $self->order_report
        or die "can't open @{[ $self->order_report ]} for write";
    return $fh;
}

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

method update_order_price($type, $price, $cb) {

    my $id = $self->position->exit_id_map->{$type};

    $self->broker->update_order($id, $price,
                                undef, $cb);
}

method format_order($order, $price, $qty) {
    return unless $self->order_report_fh;
    syswrite $self->order_report_fh,
        join(',',
             $self->date,
             $order->{dir},
             $qty,
             $order->{price} || $self->broker->{last_price},
             $price,
             0, # triggering time
             0, # submission time
             AnyEvent->now, # report time
         ).$/;
}

method new_bracket_order ($entry_order, $stp, $tp, %args) {
    my $on_exit = delete $args{on_exit};
    my $on_entry = delete $args{on_entry};
    my $entry_annotation = delete $args{entry_annotation} || sub {};
    my $submit_i = $self->i;
    my $p = TradeSpring::Position->new(
        broker => $self->broker, %args,
        on_entry => sub {
            my ($pos, $price, $qty) = @_;
            $self->format_order($entry_order, $price, $qty);
            $self->fill_position($pos->direction, $price, $qty, $submit_i,
                                 $entry_annotation->());
            $on_entry->(@_) if $on_entry;
        },
        on_exit => sub {
            my ($pos, $type, $price, $qty) = @_;
            my $o = $self->broker->get_order( $pos->exit_id_map->{$type} );
            $self->format_order($o->{order}, $price, $qty);
            $self->fill_position($pos->direction*-1, $price, $qty, $self->i, exit_type => $type);
            $on_exit->(@_) if $on_exit;
            $self->clear_position;
        },
        direction => $entry_order->{dir}, # deprecate later
    );

    $p->create($entry_order, $stp, $tp);
    $self->position($p);
}

method cancel_pending_order {
    $self->position->cancel;
    $self->clear_position unless $self->position_entered;
}

1;
