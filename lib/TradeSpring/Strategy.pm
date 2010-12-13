package TradeSpring::Strategy;
use Moose;
use DateTime;
use Method::Signatures::Simple;
use MooseX::ClassAttribute;
use TradeSpring::Position;

use List::Util qw(sum);

with 'MooseX::Log::Log4perl';

class_has attrs => (is => "rw", isa => "HashRef", default => sub { {} });

has open_positions => (is => "rw", isa => "ArrayRef", default => sub { [] });
has broker => (is => "rw");
has position => (is => "rw", isa => "TradeSpring::Position", clearer => 'clear_position');

has _last_ym => (is => "rw", isa => "Str");
has _ym_cnt => (is => "rw", isa => "Int", default => sub { 0 });

has pending_positions => (is => "rw", isa => "HashRef", default => sub { {} });

has report_fh => (is => "rw", default => sub { \*STDOUT });

method new_position($entry, $stp, $tp, %args) {
    my $pos = TradeSpring::Position->new(broker => $self->broker, %args);

    $pos->create($entry, $stp, $tp);

    $self->pending_positions->{$pos->entry_id} = $pos;
}

method frame_attrs { return }

method fill_position($dir, $price, $qty, $submit_i, %attrs) {
    my $pos = $self->open_positions;
    my $cp = (sum map { $_->{dir} } @$pos) || 0;
    if ($cp * $dir < 0) { # closing
        my $c = shift @$pos;
#        warn "closing $cp $dir ".Dumper($c) ; use Data::Dumper;
        my $date = $self->date;

        my ($y, $m, $d) = split(/[-\s]/, $date);
        my $dt = DateTime->new(year => $y, month => $m, day => $d);

        my ($ym) = $date =~ m/(\d{4}-\d{2})/;
        $ym =~ s/-//;
        if (!$self->_last_ym || $ym ne $self->_last_ym) {
            $self->_ym_cnt( 0 );
            $self->_last_ym($ym);
        }

        print {$self->report_fh}
            join(",", $ym.'-'.sprintf('%03d',++$self->{_ym_cnt}), $dt->ymd, $c->{dir},
                   $self->date($c->{i}), $date,
                   $c->{price}, $price,
                   ($price - $c->{price}) * $c->{dir},

                   map { $self->attrs->{$_}->($self, $c) } sort keys %{$self->attrs}
               ).$/;
    }
    else {
        push @$pos, { dir => $dir, price => $price, i => $self->i, qty => $qty,
                      submit_i => $submit_i, %attrs
                  };
    }
}

method init($pkg:) {
}

method end {}

method on_end_of_day {
    my $pos = $self->open_positions;
    if (@{$pos}) {
        $self->fill_position($pos->[0]{dir}*-1, $self->close, 1);
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
