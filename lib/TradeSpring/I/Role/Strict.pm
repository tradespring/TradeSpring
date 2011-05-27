package TradeSpring::I::Role::Strict;
use Moose::Role;
use Carp::Clan qw(^(TradeSpring::I::Role::|Class::MOP::));

has last_i => (is => "rw", isa => "Int");
has last_vals => (is => "rw", isa => "ArrayRef");

around 'do_calculate' => sub {
    my ($next, $self, @args) = @_;
    if (defined $self->last_i) {
        return @{$self->last_vals} if $self->i == $self->last_i;
        if ($self->i != $self->last_i+1) {
            croak "@{[ $self->as_string ]} not called with incremental i: @{[ $self->i ]}, was: @{[ $self->last_i]}";
        }
    }

    $self->last_i($self->i);
    my @val = $self->$next(@args);
    $self->last_vals( \@val);
    return @{$self->last_vals};
};

1;
