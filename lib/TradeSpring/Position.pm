package TradeSpring::Position;
use Moose;
use Method::Signatures::Simple;
with 'MooseX::Log::Log4perl';

has broker => (is => "ro", isa => "TradeSpring::Broker");

has status => (is => "rw", isa => "Str");

has order => (is => "rw", isa => "HashRef");

has on_entry => (is => "rw", isa => "CodeRef");
has on_error => (is => "rw", isa => "CodeRef");
has on_exit => (is => "rw", isa => "CodeRef");

has direction => (is => "ro", isa => "Int");

has entry_id => (is => "rw", isa => "Maybe[Str]");
has exit_id_map => (is => "rw", isa => "HashRef", default => sub { {} });

has position_entered => (is => "rw", isa => "Int", default => sub { 0 });
has position_exited  => (is => "rw", isa => "Int", default => sub { 0 });
has qty => (is => "rw", isa => "Int");

# compat
method stp_id { $self->exit_id_map->{stp} }
method tp_id { $self->exit_id_map->{tp} }

method _submit_exit_order($type, $order) {
    $order->{attached_to} = $self->entry_id
        if !$self->position_entered;
    $order->{oca_group} = $self->entry_id;
    my $id;
    $id = $self->exit_id_map->{$type} = $self->broker->register_order(
        $order,
        on_ready => sub {
            $self->log('order')->info("order ready($type): ".join(',',@_));
        },
        on_match => sub {
            my ($price, $qty) = @_;
            $self->{position_exited} += $qty;
        },
        on_error => sub {
            # XXX: recover procedure:
            # - unexpeted errors
            #   - stop strategy new positions
            #   - check submitted order
            my ($type, $msg) = @_;
            $self->log->fatal("order failed: $type $msg");
        },
        on_summary => sub {
            # XXX: consolidate tp/stp orders's summary for actual on_exit price
            my $o = $self->broker->get_order($id);
            $self->status('exited');
            if ($_[0]) {
                $self->on_exit->($self, $type, $o->{order}{price}, $_[0], $o);
                $self->log->info("position exited: ($o->{order}{dir}) $o->{order}{price} x $_[0] @ $o->{last_fill_time}");
            }
        });

    return $id;
}

method create ($entry, $stp, $tp) {

    my $entry_order = { %$entry, dir => $self->direction };
    $self->qty( $entry_order->{qty} );
    $self->entry_id(
        $self->broker->register_order
            ($entry_order,
             on_match => sub {
                 my ($price, $qty) = @_;
                 my ($stp_order, $exit_order);
                 $self->{position_entered} += $qty;
             },
             on_ready => sub {
                 my $parent = shift;
                 $self->status('submitted');
                 if ($stp && !$self->stp_id) {
                     $stp->{dir} ||= $self->direction * -1; ### ensure?
                     my $stp_order = { %$stp };
                     $stp_order->{type} ||= 'stp';
                     $stp_order->{qty} ||= $entry_order->{qty};

                     $self->_submit_exit_order('stp', $stp_order);
                 }
                 if ($tp && !$self->tp_id) {
                     $tp->{dir} ||= $self->direction * -1; ### ensure?
                     my $tp_order = { %$tp };
                     $tp_order->{type} ||= 'lmt';
                     $tp_order->{qty} ||= $entry_order->{qty};

                     $self->_submit_exit_order('tp', $tp_order);
                 }
             },
             on_error => sub {
                 # XXX: recover procedure:
                 # - unexpeted errors
                 #   - stop strategy new positions
                 #   - check submitted order
                 my ($type, $msg) = @_;
                 $self->log->fatal("order failed: $type $msg");
             },
             on_summary => sub {
                 if ($_[0]) {
                     my $o = $self->broker->get_order($self->entry_id);
                     $self->status('entered');
                     $self->on_entry->($self, $o->{order}{price}, $_[0], $o);
                     $self->log->info("position entered: ($o->{order}{dir}) $o->{order}{price} x $_[0] @ $o->{last_fill_time}");
                 }
             }));
}

method cancel {
    $self->broker->cancel_order( $self->entry_id, sub {
                                     $self->log('order')->info("order @{[ $self->entry_id]} cancelled: ".join(',', @_) );
                                 });
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;
