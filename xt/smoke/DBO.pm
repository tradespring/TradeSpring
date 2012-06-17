package DBO::State;
use Moose;
use methods-invoker;

extends 'TradeSpring::FSA::State';

method start_state { 'submit' }

method on_submit {
    $->machine->try_switch();
}

method from_submit {
    [ pending => sub { 1 } ];
}

method do_manage_position {
    my $stp_id = $->notes('exit_id_map')->{'stp'} or return;
    my $stp = $->broker->get_order($stp_id);

    my $evx = 15;
    my $ww = $self->ne_ww;
    $ww->test($_) for ($self->i-$evx+1..$self->i);
    my $price = $ww->current_value;
    if ($->bt($price, $stp->{order}{price})) {
        $->broker->update_order($stp_id, $price,
                                    undef,
                                    sub { $->log->info('updated stp to '.$ww->current_value) });
        $->notes('stp_price', $price);
    }
    return 0;
}

package DBO;
use Moose;
use methods;

extends 'TradeSpring::Strategy::FSA';
with 'MooseX::Log::Log4perl';

use constant fsa_cancel_pending => 1;
has '+state_class' => (default => sub { 'DBO::State' });

around attrs => sub {
    my ($next, $self) = @_;
    +{ %{ $self->$next() }, (
        _mk_cpos_attr(qw(exit_type r)),
    )}
};

sub _mk_cpos_attr {
    map { $_ => method($cpos) { $cpos->{$_} } } @_;
}

around order_annotation => sub {
    my ($next, $self, $state) = @_;
    my $ann = {};
    if (my $stp = $state->notes('stp_price')) {
        my $dir = $state->direction;
        my $p = $state->notes('order_price');
        my $r = ($p - $stp) * $dir;
        $ann = { r => $r };
    }
    +{ %{ $self->$next($state) }, %$ann };
};

around run => sub {
    my ($next, $self, @args) = @_;
    $self->$next(@args);

    my $fsa = $self->fsa;

    return if @$fsa;

    for my $dir (-1,1) {
        $self->mk_order($dir);
    }
};

method initial_stp { 0.02 }

method mk_order($dir, $type) {
    local $self->{direction} = $dir;
    $type ||= 'stp';

    my $evl =  22;
    my $bb = $self->ne_bb;
    $bb->test($_) for ($self->i-$evl+1..$self->i);

    my $order = { dir => $dir,
		  price => $bb->current_value,
		  type => $type,
		  qty => 1 };

    push @{$self->fsa}, $self->new_directional_fsa(
        direction => $dir,
        order => $order,
        stp_price => $self->initial_stp_price($dir, $bb->current_value),
    );
}

with 'TradeSpring::Directional';

__PACKAGE__->meta->make_immutable;
