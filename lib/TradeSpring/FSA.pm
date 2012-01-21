package TradeSpring::FSA;
use 5.10.1;
use Moose::Role;
use Try::Tiny;
use methods;

use YAML::Syck qw(LoadFile DumpFile);
use FSA::Rules;
with 'TradeSpring::OrderReport';

has state_file => (is => "rw", isa => "Str");
has fsa => (is => "rw", default => sub { [] });

method load($prev, $first, $last) {
    if (my $f = $self->state_file) {
        try {
            my $state = LoadFile($f);
            if ($prev >= 0) {
                die "state stamp mismatch $state->{date} vs ".$self->date($prev)
                    unless $state->{date} eq $self->date($prev);
            }
            $self->load_from_state($state->{fsa});
            $self->log->info("state restored from $f");
        }
        catch {
            $self->log->error("failed to load state: $_");
            $self->i($prev);
            $self->log->warn("rerun last: ".$self->date);
            $self->run;
        }
    }
}

around attrs => sub {
    my ($next, $self) = @_;
    +{ %{ $self->$next() }, (
        _mk_cpos_attr(qw(exit_type r)),
    )}
};

sub _mk_cpos_attr {
    map { $_ => method($cpos) { $cpos->{$_} } } @_;
}

method dump_state($state) {
    for (@$state) {
        delete $_->{notes}{exit_id_map};
        $_->{notes}{order} =~ s/^b/s/;
    }
    DumpFile($self->state_file, { date => $self->date,
                                  fsa => $state });
}

method new_fsa($dir, $price, $qty, $stp_price) {
    my $order = { dir => $dir,
                  price => $price,
                  type => 'stp',
                  qty => $qty,
              };

    $self->new_fsa2(
        { submit => {
            do => sub {
                my $state = shift;
                $state->notes('order', $order);
            },
            rules => [ pending => sub { 1 } ],
        }
      },
        $stp_price,
    );
}

method new_fsa2($conditions, $stp_price, $on_enter) {
    my $fsa = FSA::Rules->new(
        %$conditions,
        pending => {
            do => sub {
                my $state = shift;
                my $order = $state->notes('order');#, undef);
                $state->notes('order', undef);
                my $dir = $order->{dir};
                $state->notes('dir', $dir);
                $state->notes('qty', $order->{qty});
                $state->notes('order_price', $order->{price}) if $order->{price};

                my $submit_i = $self->i;
                my $id = $self->broker->register_order(
                    $order,
                    on_match => sub {
                        my ($price, $qty) = @_;
                        $self->debug("matched!");
                        $state->machine->{position_entered} += $qty;
                    },
                    on_ready => sub {
                        $self->debug("order submitted: ($dir): $order->{price}");
                    },
                    on_error => sub {
                    },
                    on_summary => sub {
                        my $id = $state->notes('order');
                        if ($_[0]) {
                            my $o = $self->broker->get_order($id);
                            $state->result($_[0]);
                            $self->format_order($o->{order}, $state->notes('order_price'), $_[0]);
                            $self->log->info("position entered: ($o->{order}{dir}) $o->{order}{price} x $_[0] @ $o->{last_fill_time}");
                            $state->notes(submit_i => $submit_i);
                            $state->notes(entry_price =>$o->{order}{price});
                            my $new = $state->machine->try_switch();
                        }
                    });
                $state->notes(order => $id);
                $state->notes(stp_price => $stp_price) if $stp_price;
                my $default_stp = $state->notes('order_price') * ( 1 - $self->initial_stp * $dir);
                my $stp = $state->notes('stp_price');
                $state->notes(stp_price => $default_stp)
                    if !$stp || $default_stp * $dir > $stp * $dir;

                local $_;
                $state->notes(order_annotation => $self->order_annotation($state));
                return;
            },
            rules => [
                'entered' => sub { shift->result }
            ],
        },
        'entered' => {
            do => sub {
                my $state = shift;
                my $dir = $state->notes('dir');
                $self->direction($dir);

                $self->on_position_entered($state);
                $self->fill_position($state->notes('dir'), $state->notes('entry_price'),
                                     $state->notes('qty'), $state->notes('submit_i'),
                                     %{ $state->notes('order_annotation') || {} },
                                     %{ $self->entry_annotation($state) });

                my $stp_price = $state->notes('stp_price');
                my $qty = $state->notes('qty');
                $self->_submit_exit_order('stp', {
                    dir => $dir * -1,
                    type => 'stp',
                    qty => $qty,
                    price => $stp_price,
                }, $state);
            },
            rules => [
                'closed' => sub { shift->result },
                'entered' => $self->manage_position,
            ]
        },
        closed => {
            do => sub { $self->direction(0); }
        }
    )
}

around order_annotation => sub {
    my ($next, $self, $state) = @_;
    my $ann = {};
    if (my $stp = $state->notes('stp_price')) {
        my $dir = $state->notes('dir');
        my $p = $state->notes('order_price');
        my $r = ($p - $stp) * $dir;
        $ann = { r => $r };
    }
    +{ %{ $self->$next($state) }, %$ann };
};

method initial_stp { 0.005 };

method _submit_exit_order($type, $order, $state) {
    my $entry_id = $state->notes('order');
    $order->{oca_group} = $entry_id;
    $state->notes('exit_id_map', {}) unless $state->notes('exit_id_map');
    my $exit_id_map = $state->notes('exit_id_map');
    my $id;
    $self->log('order')->info("submit exit $type: $order->{type}($order->{dir})/$order->{price}");
    $id = $exit_id_map->{$type} = $self->broker->register_order(
        $order,
        on_ready => sub {
            $self->log('order')->info("stp order ready($type): $id ".join(',',@_));
        },
        on_match => sub {
            my ($price, $qty) = @_;
            $state->machine->{position_exited} += $qty;
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
                $self->format_order($o->{order}, $order->{price} || $self->broker->{last_price}, $_[0]);
                $self->log->info("position exited: ($o->{order}{dir}) $o->{order}{price} x $_[0] @ $o->{last_fill_time}");
                $self->fill_position($o->{order}{dir}, $o->{order}{price}, $_[0], $self->i, exit_type => $type, $self->exit_map($state));
                $state->machine->curr_state->result($_[0]);
                my $new = $state->machine->try_switch();
            }
        });

    return $id;
}

method on_position_entered($state) { return () }

method exit_map($state) { return () }

method load_from_state($state) {
    for my $entry (@$state) {
        my $notes = $entry->{notes};
        my $fsa = $self->new_fsa($notes->{dir}, $notes->{price},
                                 $notes->{qty}, $notes->{stp_price});
        %{ $fsa->notes } = %{ $entry->{notes} };
        $fsa->curr_state($entry->{curr_state});
        push @{$self->fsa}, $fsa;
    }
}

after 'end' => sub {
    my $self = shift;
    my $state = [ map {
        { notes => { %{$_->notes} }, curr_state => $_->curr_state->name }
    } grep { !$_->at('closed') } @{ $self->fsa } ];

    $self->dump_state($state) if $self->state_file;
    # shutdown

    for my $f (@{ $self->fsa } ) {
        if ($f->at('pending')) {
            $self->broker->cancel_order( $f->notes('order'), sub {
                                             $self->debug("order @{[ $f->notes('order') ]} cancelled: ".join(',', @_) );
                                         });
        }
        elsif ($f->at('entered')) {
            $self->broker->cancel_order( $f->notes('exit_id_map')->{stp}, sub {
                                             $self->debug("order @{[ $f->notes('exit_id_map')->{stp} ]} cancelled: ".join(',', @_) );
                                         });
        }
    }
    $self->fsa([]);
};

1;
