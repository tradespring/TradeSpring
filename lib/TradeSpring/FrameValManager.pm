package TradeSpring::FrameValManager;
use Moose::Role;
use methods;
with 'MooseX::Log::Log4perl';

has framevals => (is => "ro", isa => "ArrayRef", default => sub { [] });

requires 'calc', 'i';

after '_set_i' => method {
    $_->get for (@{$self->framevals});
};

sub BUILD {}
after BUILD => method {
    my @attrs = grep {$_->does('TradeSpring::Meta::Attribute::Trait::FrameVal') }
                      $self->meta->get_all_attributes;
    for my $attr (@attrs) {
        push @{$self->framevals}, $attr->get_value($self);
    }
};

method load_frameval($name, %args) {
    Class::Load::load_class($name);
    $name->new( frame => $self,
                %args );
}

package Moose::Meta::Attribute::Custom::Trait::FrameVal;
sub register_implementation {'TradeSpring::Meta::Attribute::Trait::FrameVal'}

package TradeSpring::Meta::Attribute::Trait::FrameVal;
use Moose::Role;

1;
