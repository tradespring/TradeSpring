package TradeSpring::Directional;
use Moose::Role;
use Finance::GeniusTrader::Prices qw($HIGH $LOW);

use Carp;

with 'TradeSpring::Frame';

has direction => (is => "rw", isa => "Int");

sub mk_directional_method {
    my ($pkg, $name, $long_name, $short_name, $function) = @_;
    my ($long, $short) = map { $pkg->can($_)
                                   || die "method $_ not defined for diretional method $name" }
        ($long_name, $short_name);
    $pkg->meta->add_method
        ($name =>
             Moose::Meta::Method->wrap(
                 sub {
                     my ($self) = @_;
                     shift if $function;
                     if ($self->direction > 0) {
                         goto $long;
                     }
                     if ($self->direction < 0) {
                         goto $short;
                     }
                     croak "better requires direction being set";
                 },
                 name => $name,
                 package_name => __PACKAGE__));
}

__PACKAGE__->mk_directional_method('better' => 'high', 'low');
__PACKAGE__->mk_directional_method('worse'  => 'low',  'high');

sub highest_high {
    my $self = shift;
    my $p = $self->calc->prices->{prices};
    Number::Extreme->max(sub { $p->[$_][$HIGH] });
}

sub lowest_low {
    my $self = shift;
    my $p = $self->calc->prices->{prices};
    Number::Extreme->min(sub { $p->[$_][$LOW] });
}

__PACKAGE__->mk_directional_method('ne_bb'  => 'highest_high', 'lowest_low');
__PACKAGE__->mk_directional_method('ne_ww'  => 'lowest_low',  'highest_high');

use List::Util qw(max min);

__PACKAGE__->mk_directional_method('lu_best'   => 'max',  'min', 'function');
__PACKAGE__->mk_directional_method('lu_worse'  => 'min',  'max', 'function');


1;
