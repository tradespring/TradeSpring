package TradeSpring::I::GT;
our $VERSION = 1;
use Moose;
extends 'TradeSpring::I';
use Number::Extreme;
use Finance::GeniusTrader::Eval;

has expression => (is => "ro", isa => "Str", traits => ['IParam']);

has gtobject => (is => "rw");
has gtobject_names => (is => "rw");

sub BUILD {
    my $self = shift;

    my ($mod, $arg) = split(/ /, $self->expression, 2);
    my $object = create_standard_object($mod, $arg) or die "FAIL: $@";
    my $which = $mod =~ m#/(\d+)# ? $1 : undef;
    $self->gtobject($object);
    $self->gtobject_names( defined $which ?
                               [ $object->get_name($which) ]
                             : [ map { $object->get_name($_) } 0..$object->get_nb_values-1] );
}

sub names {
    my $self = shift;
    @{$self->gtobject_names};
}


sub do_calculate {
    my $self = shift;
    my $i = $self->i;
    $self->gtobject->calculate($self->frame->calc, $i);
    map { $self->frame->calc->indicators->get( $_, $i ) } $self->names;
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;
