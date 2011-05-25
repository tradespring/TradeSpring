package TradeSpring::IManager;
use Moose;

has frame => (is => "rw");

has indicator_traits => (is => "rw", isa => "ArrayRef");


sub load {
    my ($self, $module, %args) = @_;

    if (my $traits = $self->indicator_traits) {
        return $module->new_with_traits( %args, frame => $self->frame, traits => $traits, loader => $self)
    }

    return $module->new( %args, frame => $self->frame, loader => $self);
}


__PACKAGE__->meta->make_immutable;
no Moose;
1;
