package TradeSpring::Strategy::FSA;
use Moose;
use methods-invoker;
use YAML::Syck qw(LoadFile DumpFile Dump);
use Try::Tiny;

extends 'TradeSpring::Frame', 'TradeSpring::Strategy';

with 'TradeSpring::OrderReport';

has state_class => (
    is => "ro",
    isa => "Str",
);

has fsa => (is => "rw", isa => "ArrayRef", default => sub { [] });

has current_position => (is => "rw", isa => "Int", default => sub { 0 });

has state_file => (is => "rw", isa => "Str");

method load($prev, $first, $last) {
    return if $prev < 0;

    my $f = $->state_file or return;
    try {
        my $state = LoadFile($f);
        if ($prev >= 0) {
            die "state stamp mismatch $state->{date} vs ".$->date($prev)
                unless $state->{date} eq $->date($prev);
        }
        $->i($prev);
        $->load_from_state($state->{fsa});
        $->log->info("state restored from $f");
    }
    catch {
        $->log('TradeSpring.Position')->error("failed to load state: $_");
        $->i($prev);
        $->log->warn("rerun last: ".$->date);
        $->run;
    }
}

method load_from_state($state) {
    for my $entry (@$state) {
        my $notes = $entry->{notes};
        my $dir = delete $entry->{notes}{dir};
        my $fsa = $->new_directional_fsa(
            direction => $dir,
            curr_state => $entry->{curr_state},
            dir => $dir, # XXX: caller should simply use state->direction
            %{ $entry->{notes} } );
        push @{$->fsa}, $fsa;
        $fsa->try_switch();
    }
}

method dump_state($state) {
    for (@$state) {
        delete $_->{notes}{exit_id_map};
        $_->{notes}{order_id} =~ s/^b/s/;
    }
    DumpFile($self->state_file, { date => $self->date,
                                  fsa => $state });
}

method new_directional_fsa(%attr) {
    my $state_class = $->state_class;
    my $dir = delete $attr{direction};
    my $state = delete $attr{curr_state} || $state_class->start_state;
    my $fsa = $state_class->new_machine( frame => $self,
                                         direction => $dir,
                                         broker => $->broker,
                                         report_fh => $->report_fh,
                                         $->order_report
                                             ? (order_report => $->order_report)
                                             : ()
                                  );
    $fsa->notes(fsa_start => $->i);
    $fsa->notes($_ => $attr{$_}) for keys %attr;
    $fsa->curr_state($state);

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

before 'on_end_of_day' => method {
    my $fsa = $->fsa;
    for my $f (@$fsa) {
        my $p = $f->{position_entered} or next;;
        $->debug('close '.$->date($f->notes('confirming')));
        my $state = $f->curr_state;
        $state->fill_position($state->direction*-1, $->close, $p, $self->i, exit_type => 'eod');
        $f->curr_state('closed');
    }
};

after 'end' => sub {
    my $self = shift;
    my $state = [ map {
        { notes => { %{$_->notes} }, curr_state => $_->curr_state->name }
    } grep { !$_->at('closed') } @{ $self->fsa } ];

    $self->dump_state($state) if $self->state_file;
    # shutdown

    for my $f (@{ $self->fsa } ) {
        if ($f->at('pending')) {
            $self->broker->cancel_order( $f->notes('order_id'), sub {
                                             $self->log->info("order @{[ $f->notes('order_id') ]} cancelled: ".join(',', @_) );
                                         });
        }
        elsif ($f->at('entered')) {
            $self->broker->cancel_order( $f->notes('exit_id_map')->{stp}, sub {
                                             $self->log->info("order @{[ $f->notes('exit_id_map')->{stp} ]} cancelled: ".join(',', @_) );
                                         });
        }
    }
    $self->fsa([]);
};


__PACKAGE__->meta->make_immutable;
no Moose;
1;
