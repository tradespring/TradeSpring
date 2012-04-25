package DBO;
use warnings;
use 5.10.0;
use Moose;
use Try::Tiny;
use methods;

extends 'TradeSpring::Frame', 'TradeSpring::Strategy';
with 'MooseX::Log::Log4perl';

method manage_position {
    sub {
        my $state = shift;
        my $stp_id = $state->notes('exit_id_map')->{'stp'};
        my $stp = $self->broker->get_order($stp_id);

        return unless $stp_id;
        my $evx = 15;
        my $ww = $self->ne_ww;
        $ww->test($_) for ($self->i-$evx+1..$self->i);
        my $price = $ww->current_value;
        if ($self->bt($price, $stp->{order}{price})) {
            $self->broker->update_order($stp_id, $price,
                                        undef,
                                        sub { $self->log->info('updated stp to '.$ww->current_value) });
            $state->notes('stp_price', $price);
        }
        return 0;
    }
}

method run {
    my $fsa = $self->fsa;
    if (@$fsa) {
        my @remaining;
        for my $f (@$fsa) {
            if ($f->at('pending')) {
                $self->broker->cancel_order( $f->notes('order_id'), sub {
                                                 $self->log->info("order @{[ $f->notes('order_id') ]} cancelled: ".join(',', @_) );
                                 });

            }
            elsif ($f->at('closed')) {
            } else {
                $f->try_switch;
                push @remaining, $f;
            }
        }
        $fsa = \@remaining;
        $self->fsa($fsa);

    }
    if (@$fsa) {
        return;
    }

    for my $dir (-1,1) {
        $self->mk_order($dir);
    }
}

method initial_stp { 0.02 }

method mk_order($dir, $type) {
    local $self->{direction} = $dir;
    $type ||= 'stp';

    my $evl =  22;
    my $bb = $self->ne_bb;
    $bb->test($_) for ($self->i-$evl+1..$self->i);

    my $stp_price = $bb->current_value * ( 1 - $self->initial_stp * $dir);
    my $qty = 1;

    my $order = { dir => $dir,
		  price => $bb->current_value,
		  type => $type,
		  qty => $qty };
    my $fsa = $self->new_raw_fsa($order, $stp_price);
    $fsa->start;
    push @{$self->fsa}, $fsa;
}

with 'TradeSpring::Directional', 'TradeSpring::FSA';

__PACKAGE__->meta->make_immutable;

1;
