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
has stp_id => (is => "rw", isa => "Str");
has tp_id => (is => "rw", isa => "Str");

has position_entered => (is => "rw", isa => "Int", default => sub { 0 });
has qty => (is => "rw", isa => "Int");

method _submit_order($type, $order) {
    $self->broker->register_order(
        $order,
        on_ready => sub {
            $self->log('order')->info("order ready: ".join(',',@_));
        },
        on_match => sub {
            $self->on_exit->($self, $type, @_);
        },
        on_summary => sub {
        });
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
                     my $stp_order = { %$stp,
                                       dir => $self->direction * -1,
                                       attached_to => $parent,
                                       oca_group => $parent };
                     $stp_order->{type} ||= 'stp';
                     $stp_order->{qty} ||= $entry_order->{qty};

                     $self->stp_id($self->_submit_order('stp', $stp_order));
                 }
                 if ($tp && !$self->tp_id) {
                     my $tp_order = { %$tp,
                                      dir => $self->direction * -1,
                                      attached_to => $parent,
                                      oca_group => $parent };
                     $tp_order->{type} ||= 'lmt';
                     $tp_order->{qty} ||= $entry_order->{qty};

                     $self->tp_id($self->_submit_order('tp', $tp_order));
                 }
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
                 if ($_[0]) {
                     my $o = $self->broker->get_order($self->entry_id);
                     $self->status('entered');
                     $self->on_entry->($self, $o->{order}{price}, $_[0]);
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
