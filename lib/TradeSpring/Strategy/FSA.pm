package TradeSpring::Strategy::FSA;
use Moose;
use methods-invoker;

extends 'TradeSpring::Frame', 'TradeSpring::Strategy';

has state_class => (
    is => "ro",
    isa => "Str",
);

has fsa => (is => "rw", isa => "ArrayRef", default => sub { [] });

has current_position => (is => "rw", isa => "Int", default => sub { 0 });

method new_directional_fsa(%attr) {
    my $dir = delete $attr{direction};
    my $state_class = $->state_class;
    my $fsa = $state_class->new_machine( frame => $self,
                                         direction => $dir,
                                         broker => $self->broker,
                                         report_fh => $self->report_fh,
                                  );
    $fsa->notes(fsa_start => $->i);
    $fsa->notes($_ => $attr{$_}) for keys %attr;
    $fsa->curr_state($state_class->start_state);

    return $fsa;
}

method on_day_start {
}

method allowed {
}

use constant fsa_cancel_pending => 0;

method run {
    my $fsa = $->fsa;
    my @remaining;
    for my $f (@$fsa) {
        # $self->debug('fsa at '.$f->curr_state->name);
        if ($f->at('pending')) {
            if ($->fsa_cancel_pending) {
                $self->broker->cancel_order(
                    $f->notes('order_id'),
                    sub {
                        $self->log->info("order @{[ $f->notes('order_id') ]} cancelled: ".join(',', @_) );
                    });
            }
            else {
                push @remaining, $f;
            }
        }
        elsif ($f->at('closed')) {
            # $->debug("closed ".$f->notes('fsa_start'));
        }
        else {
            $f->try_switch;
            push @remaining, $f;
        }
    }
    $self->fsa(\@remaining);
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;
