package TradeSpring::Directional;
use Moose::Role;
use Finance::GeniusTrader::Prices qw($HIGH $LOW);
use Method::Signatures::Simple;
use Number::Extreme;
use Carp;


requires 'high';
requires 'low';

has direction => (is => "rw", isa => "Int");

method mk_directional_method($pkg: $name, $long_name, $short_name, $is_function) {
    my ($long, $short) = map { ref($_) eq 'CODE' ? $_ : $pkg->can($_) }
#                                   || die "method $_ not defined for diretional method $name of $pkg" }
        ($long_name, $short_name);
    $pkg->meta->add_method
        ($name =>
             Moose::Meta::Method->wrap(
                 sub {
                     my ($self) = @_;
                     shift if $is_function;
                     if ($self->direction > 0) {
                         $long ||= $self->can($long_name);
                         goto $long;
                     }
                     if ($self->direction < 0) {
                         $short ||= $self->can($short_name);
                         goto $short;
                     }
                     croak "better requires direction being set";
                 },
                 name => $name,
                 package_name => __PACKAGE__));
}

__PACKAGE__->mk_directional_method('better' => 'high', 'low');
__PACKAGE__->mk_directional_method('worse'  => 'low',  'high');

__PACKAGE__->mk_directional_method('ne_bb'  => 'highest_high', 'lowest_low');
__PACKAGE__->mk_directional_method('ne_ww'  => 'lowest_low',  'highest_high');
__PACKAGE__->mk_directional_method('ne_best' => sub { Number::Extreme->max(@_) },
                                                sub { Number::Extreme->min(@_) }, 'function');


use List::Util qw(max min);

__PACKAGE__->mk_directional_method('lu_best'   => 'max',  'min', 'function');
__PACKAGE__->mk_directional_method('lu_worst'  => 'min',  'max', 'function');

__PACKAGE__->mk_directional_method('bt',
                                   sub { $_[0] > $_[1] },
                                   sub { $_[0] < $_[1] }, 'function');
__PACKAGE__->mk_directional_method('wt',
                                   sub { $_[0] < $_[1] },
                                   sub { $_[0] > $_[1] }, 'function');

method we { !$self->bt(@_) }
method be { !$self->wt(@_) }

1;
