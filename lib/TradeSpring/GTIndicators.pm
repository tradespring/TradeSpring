package TradeSpring::GTIndicators;
use Moose::Role;
use Finance::GeniusTrader::Eval;
use Finance::GeniusTrader::Calculator;

requires 'calc';

sub has_indicator {
    my ($name, $spec) = @_;
    my $pkg = (caller())[0];
    my $meta = $pkg->meta;
    my ($mod, $arg) = split(/ /, $spec, 2);

    my $which = $mod =~ s#/(\d+)## ? $1-1 : 0;
    my $object = create_standard_object($mod, $arg // ());
    my $object_name = $object->get_name($which);
    my $cache_tried = $ENV{GTINDICATOR_CACHE} ? 0 : 1;
    if ($object->isa('Finance::GeniusTrader::Indicators')) {
        $meta->add_method(
            $name =>
                sub {
                    my ($self, $i) = @_;
                    my $calc = $self->calc;

                    unless ($cache_tried++) {
                        use Data::Walk 'walk';
                        walk sub {
                            return unless UNIVERSAL::isa($_, 'Finance::GeniusTrader::Indicators');
                            $_->load_from_cache($calc);
                        }, $object;
                    }

                    $i //= $self->i;
                    my $indicators = $self->calc->indicators;
                    $object->calculate( $calc, $i )
                        unless $indicators->is_available( $object_name, $i );
                    $indicators->get( $object_name, $i );
                }
            )
    }
    elsif ($object->isa('Finance::GeniusTrader::Signals')) {
        $meta->add_method(
            $name =>
                sub {
                    my ($self, $i) = @_;
                    $object->detect( $self->calc, $i // $self->i);
                    $self->calc->signals->get( $object_name, $i // $self->i );
                }
            )
    }
}

__PACKAGE__;
