package TradeSpring::OrderReport;
use Moose::Role;
use methods;

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

method format_order($order, $filled_price, $qty, $order_price) {
    return unless $self->order_report_fh;
    $order_price ||= $order->{orig_order} ? $order->{orig_order}{price} : $self->broker->{last_price};
    syswrite $self->order_report_fh,
        join(',',
             $self->date,
             $order->{dir},
             $qty,
             $order_price,
             $filled_price,
             0, # triggering time
             0, # submission time
             AnyEvent->now, # report time
         ).$/;
}

1;
