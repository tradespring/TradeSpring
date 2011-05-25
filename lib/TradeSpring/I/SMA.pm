package TradeSpring::I::SMA;
use Moose;
use Statistics::Basic qw(nofill);
use Statistics::Basic::Mean;
extends 'TradeSpring::I';

has n => (is => "ro", isa => "Int", traits => ['IParam']);
has arg => (is => "ro", traits => ['IParam', 'Depended'], default => sub { 'close' } );

has arg_value => (is => "rw");

sub BUILD {
    my $self = shift;
}

has mean => (
    is => "rw",
    lazy_build => 1
);

sub _build_mean {
    my $self = shift;
    Statistics::Basic::Mean->new()->set_size($self->n);
}

sub do_calculate {
    my $self = shift;
    $self->mean->insert( $self->arg_value->() );
    $self->mean->query;
}

1;
