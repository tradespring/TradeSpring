package TradeSpring::I;

use Moose;

has frame => (is => "ro", isa => "TradeSpring::Frame",
              handles => [qw(i calc date open high highest_high low lowest_low close debug)],
);

has params => (
    is => "rw",
    isa => 'ArrayRef',
    lazy_build => 1
);

has as_string => (
    is => "rw",
    isa => "Str",
    lazy_build => 1
);

sub _build_as_string {
    my $self = shift;
    $self->meta->name.'('.
    join(',',
    map {
        ref $self->$_ ? $self->$_->as_string : $self->$_
    } @{$self->params}).')';
}

sub names {}

sub _build_params {
    my $self = shift;
##    warn "==> build params: ".join(',',map { $_->name} grep { $_->does('TradeSpring::Meta::Attribute::Trait::IParam' ) }
#             $self->meta->get_all_attributes);
    return [map { $_->name }
         grep { $_->does('TradeSpring::Meta::Attribute::Trait::IParam' ) }
             $self->meta->get_all_attributes ]
}

sub BUILD {
    # deps
    my $self = shift;
    for my $attr (grep {$_->does('TradeSpring::Meta::Attribute::Trait::Depended') }
                      $self->meta->get_all_attributes) {

        my $name = $attr->name.'_value';
        next unless $self->meta->has_attribute($name);
        my $ichild = $attr->get_value($self);
        warn "===> $ichild -> $name of $self";
        if (UNIVERSAL::isa($ichild, 'TradeSpring::I')) {
            $self->$name(sub {
                                 $ichild->do_calculate
                             })
        }
        else {
            $self->$name(sub {
                                 $self->$ichild
                             })
        }
    }

}

use List::MoreUtils qw(zip);

sub calculate {
    my $self = shift;
    my @names = $self->names;
    my @values = $self->do_calculate;
    return { zip @names, @values };

}


__PACKAGE__->meta->make_immutable;
no Moose;


package Moose::Meta::Attribute::Custom::Trait::Depended;
sub register_implementation {'TradeSpring::Meta::Attribute::Trait::Depended'}

package Moose::Meta::Attribute::Custom::Trait::IParam;
sub register_implementation {'TradeSpring::Meta::Attribute::Trait::IParam'}

package TradeSpring::Meta::Attribute::Trait::IParam;
use Moose::Role;

1;


package TradeSpring::Meta::Attribute::Trait::Depended;
use Moose::Role;

with 'TradeSpring::Meta::Attribute::Trait::IParam';

1;
