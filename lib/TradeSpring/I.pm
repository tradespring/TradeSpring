package TradeSpring::I;

use Moose;
use UNIVERSAL::require;
with 'MooseX::Traits';

has '+_trait_namespace' => (default => 'TradeSpring::I::Role');

has frame => (is => "ro", isa => "TradeSpring::Frame",
              handles => [qw(i calc date open high highest_high low lowest_low close hour last_hour is_dstart debug)],
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

has loader => (is => "rw");


sub load {
    my ($self, $name, %args) = @_;
    my $module = $name =~ /^\+/ ? $name : "TradeSpring::I::$name";
    $module->require or die $@;

    return $self->loader->load($module, %args)
        if $self->loader;

    $module->new( %args, frame => $self->frame);

}

sub _build_as_string {
    my $self = shift;
    my $name = $self->meta->name;
    $name = ($self->meta->superclasses)[0] if $name =~ /__ANON__/;

    $name.'('.
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
    return [map { $_->name } sort { $a->index <=> $b->index }
         grep { $_->does('TradeSpring::Meta::Attribute::Trait::IParam' ) }
             $self->meta->get_all_attributes ]
}

sub BUILD {
    # deps
    my $self = shift;
    for my $attr (grep {$_->does('TradeSpring::Meta::Attribute::Trait::Depended') }
                      $self->meta->get_all_attributes) {

        my $name = $attr->name.'_value';
        next unless $self->meta->find_attribute_by_name($name);
        my $ichild = $attr->get_value($self);

        if (UNIVERSAL::isa($ichild, 'TradeSpring::I')) {
            $self->$name( $self->build_depended_attribute($name, $ichild) );
        }
        else {
            $self->$name(sub {
                                 $self->$ichild
                             })
        }
    }

}

sub build_depended_attribute {
    my ($self, $name, $ichild) = @_;
    return sub {
        $ichild->do_calculate
    }
}

use List::MoreUtils qw(zip);

sub calculate {
    my $self = shift;
    my @names = $self->names;
    my @values = $self->do_calculate;
    return { zip @names, @values };

}

sub do_calculate { die 'must implement' };


__PACKAGE__->meta->make_immutable;
no Moose;


package Moose::Meta::Attribute::Custom::Trait::Depended;
sub register_implementation {'TradeSpring::Meta::Attribute::Trait::Depended'}

package Moose::Meta::Attribute::Custom::Trait::IParam;
sub register_implementation {'TradeSpring::Meta::Attribute::Trait::IParam'}

package TradeSpring::Meta::Attribute::Trait::IParam;
use Moose::Role;


after 'attach_to_class' => sub {
    my ($self, $class) = @_;
    $self->{index} = (($class->{nparam} ||= 0)++);
};

has index => (
    is      => 'ro' ,
    isa     => 'Int' ,
);

1;


package TradeSpring::Meta::Attribute::Trait::Depended;
use Moose::Role;


1;
