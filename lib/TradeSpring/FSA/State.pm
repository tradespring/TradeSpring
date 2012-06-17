package TradeSpring::FSA::State;
use Moose;
use FSA::Rules;
use methods-invoker;
use MooseX::ClassAttribute;
extends 'FSA::State';
with 'MooseX::Alien';
with 'TradeSpring::OrderReport';
with 'TradeSpring::PositionReport';

has frame => (is => "rw", isa => "TradeSpring::Frame",
              handles => [qw(i calc date open high highest_high low lowest_low close hour last_hour is_dstart debug position_closed)],
);
has broker => (is => "ro");

with 'TradeSpring::Directional';
with 'MooseX::Log::Log4perl';

method start_state { 'pending' }

method position_attributes($c) {
    $->frame->with_direction($->direction, sub {
                                 map { $->frame->attrs->{$_}->($->frame, $c) } sort keys %{$->frame->attrs}
                             });
}

method new_machine($pkg: %args) {
    my $fsa = FSA::Rules->new(
        { state_class  => $pkg,
          state_params => \%args },
        %{ $pkg->build_rules },
    );
    return $fsa;
}

class_has rules => (
    is => "ro",
    lazy_build => 1
);

method build_rules($pkg:) {
    my $rules = {};
    for my $method ($pkg->meta->get_all_methods) {
        my ($name) = $method->name =~ m/^on_(.*)/ or next;
        my $from = $pkg->meta->find_method_by_name("from_$name");
        $rules->{$name} = {
            do => $method->body,
            rules => $from ? $from->body->($pkg) : [],
        };
    }
    return $rules;
}

method on_pending {
    my $order = $->notes('order');
    my $dir = $->direction;
    # XXX: dir in notes is compat only
    $->notes('dir' => $dir);
    $->notes('qty', $order->{qty});
    $->notes('order_price', $order->{price}) if $order->{price};
    my $submit_i = $self->i;
    my $id = $self->broker->register_order(
        { %$order },
        on_match => sub {
            my ($price, $qty) = @_;
            $->machine->{position_entered} += $qty;
        },
        on_ready => sub {
            $self->log->info("order submitted: ($dir): $order->{price}");
        },
        on_error => sub {
        },
        on_summary => sub {
            my $id = $->notes('order_id');
            if ($_[0]) {
                my $o = $self->broker->get_order($id);
                $->result($_[0]);
                $->format_order($o->{order}, $o->{order}{price}, $_[0], $->notes('order_price'));
                $self->log('TradeSpring.Position')->info("position entered: ($o->{order}{dir}) $o->{order}{price} x $_[0] @ $o->{last_fill_time}");
                $->notes(submit_i => $submit_i);
                $->notes(entry_price =>$o->{order}{price});
                my $new = $->machine->try_switch();
            }
        });
    $->notes(order_id => $id);
    $->notes(order_annotation => $self->frame->order_annotation($self));
    return;
}

method get_initial_stp($entry, @stp) {
    my $stp = $->lu_best($->frame->initial_stp_price($->direction, $entry), @stp);

    my $r = ($->close - $stp) * $->direction;
    return ($stp, $r);
}

method from_pending {
    [
        'entered' => sub { return $_[0]->result }
    ]
}

method on_position_entered {
    $->frame->current_position( $->frame->current_position + $->direction );
}

method on_entered {
    my $dir = $->direction;
    $->on_position_entered;
    $self->fill_position($dir,
                         $->notes('entry_price'),
                         $->notes('qty'),
                         $->notes('submit_i'),
                         %{ $->notes('order_annotation') || {} },
                         %{ $->frame->entry_annotation($dir) });

    my $stp_price = $->notes('stp_price') or return;
    my $qty = $->notes('qty');
    $->_submit_exit_order('stp', {
        dir => $dir * -1,
        type => 'stp',
        qty => $qty,
        price => $stp_price,
    });
}

method _submit_exit_order($type, $order) {
    my $entry_id = $->notes('order_id');
    $order->{oca_group} = $entry_id;
    $->notes('exit_id_map', {}) unless $->notes('exit_id_map');
    my $exit_id_map = $->notes('exit_id_map');
    my $id;
    $self->log('order')->info("submit exit $type: $order->{type}($order->{dir})/$order->{price}");
    $id = $exit_id_map->{$type} = $self->broker->register_order(
        $order,
        on_ready => sub {
            $self->log('order')->info("stp order ready($type): $id ".join(',',@_));
        },
        on_match => sub {
            my ($price, $qty) = @_;
            $->machine->{position_exited} += $qty;
        },
        on_error => sub {
            # XXX: recover procedure:
            # - unexpeted errors
            #   - stop strategy new positions
            #   - check submitted order
            my ($type, $msg) = @_;
            $self->log->error("order failed: $type $msg");
        },
        on_summary => sub {
            my $o = $self->broker->get_order($id);
            if ($_[0]) {
                $self->format_order($o->{order}, $o->{order}{price}, $_[0]);
                $self->log('TradeSpring.Position')->info("position exited: ($o->{order}{dir}) $o->{order}{price} x $_[0] @ $o->{last_fill_time}");
                $self->fill_position($o->{order}{dir}, $o->{order}{price}, $_[0], $self->i, exit_type => $type, $self->exit_map);


                $->machine->curr_state->result($_[0]);
                my $new = $->machine->try_switch();
            }
        });
    return $id;
}

method exit_map() { return () }

method from_entered {
    [
        'closed' => sub { shift->result },
        'entered' => sub { shift->do_manage_position; return },
    ]
}

method manage_position {
    return sub {};
}


method on_closed {
    return unless $->notes('order_price');
    $->frame->current_position( $->frame->current_position - $->direction );
}

__PACKAGE__->meta->make_immutable(
    inline_constructor => 0);
1;
