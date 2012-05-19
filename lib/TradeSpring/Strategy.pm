package TradeSpring::Strategy;
use Moose;
use DateTime;
use methods;
use MooseX::ClassAttribute;
use TradeSpring::Position;
use POSIX qw(ceil floor);

with 'MooseX::Log::Log4perl';
with 'TradeSpring::PositionReport';

class_has attrs => (is => "rw", isa => "HashRef", default => sub { {} });

has broker => (is => "rw");
has position => (is => "rw", isa => "TradeSpring::Position", clearer => 'clear_position');

has pending_positions => (is => "rw", isa => "HashRef", default => sub { {} });

has position_qty => (is => "ro", isa => "Int", default => sub { 1 });

has ps_class => (is => "ro", isa => "Str");

has ps_store => (is => "rw", isa => "Str");

has ps => (is => "rw");

has cost => (is => "rw", isa => 'Num', default => sub { 0 });

has initial_stp => (is => "rw", isa => "Num", default => sub { 0.01 });

method BUILD {
    if (my $class = $self->ps_class) {
        $class =~ s/^\+// or $class = "TradeSpring::PS::".$class;

        local @ARGV = @{$self->extra_argv};
        $self->ps(TradeSpring::load_ps($class, $self->ps_store,
                                       sub {
                                           $self->extra_argv($_[0])
                                       }));

        $self->log->info("loaded position sizing module: ".$self->ps->info);
        unless ($self->ps->equity) {
            $self->log->logdie("must specify initial equity");
        }
    }
}

method load($prev, $first, $last) {
}

method dir_round($dir, $price) {
    $dir > 0 ? ceil($price) : floor($price);
}

method initial_stp_price($dir, $price) {
    $self->dir_round(-$dir, $price * ( 1 - $self->initial_stp * $dir));
}

method position_closed($profit, $qty) {
    if ($self->ps) {
        my $n = $self->ps->equity + ($profit - $self->cost) * $qty;
        $self->log->info("Updating equity: $n");
        $self->ps->equity( $n );
        $self->ps->store($self->ps_store) if $self->ps_store;
    }
}


method position_attributes($c) {
    map { $self->attrs->{$_}->($self, $c) } sort keys %{$self->attrs}
}

method get_position_qty($r) {
    return $self->position_qty unless $self->ps;

    return $self->ps->get_qty($r);
}

method new_position($entry, $stp, $tp, %args) {
    my $pos = TradeSpring::Position->new(broker => $self->broker, %args);

    $pos->create($entry, $stp, $tp);

    $self->pending_positions->{$pos->entry_id} = $pos;
}

method frame_attrs { return }

method order_annotation { {} }
method entry_annotation { {} }

method init($pkg:) {
}

method end {}

method on_end_of_day {
    my $pos = $self->open_positions;
    if (@{$pos}) {
        $self->fill_position($pos->[0]{dir}*-1, $self->close, $pos->[0]{qty}, $self->i, exit_type => 'eod');
        warn "===ERROR: unclosed position after closing"
            if @$pos;
    }
    $self->open_positions([]);

    for ( keys %{$self->broker->orders})  {
        $self->broker->cancel_order( $_, sub { 'cancelled'} )
            if exists $self->broker->orders->{$_};
    }

    $self->broker->filled_orders({});

    $self->cleanup;
}

method cleanup {
    $self->direction(0);
    $self->clear_position;
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;
