package TradeSpring::I::Role::Cached;
use Moose::Role;
use Carp::Clan qw(^(TradeSpring::I::Role::|Class::MOP::));

has cache => (is => "rw", isa => "HashRef", default => sub { {} });

around 'do_calculate' => sub {
    my ($next, $self, @args) = @_;
    confess unless defined $self->i;
    $self->cache->{$self->i} //= [ $self->$next(@args) ];
    return @{$self->cache->{$self->i}};
};

1;
