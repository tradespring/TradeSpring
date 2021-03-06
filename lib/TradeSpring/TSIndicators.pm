package TradeSpring::TSIndicators;
use Moose::Role;
use methods;
with 'MooseX::Log::Log4perl';

requires 'calc', 'i';

has imanager => (
    is => "ro",
    lazy_build => 1
);

has range => (is => "ro", isa => "ArrayRef");

has use_cache => (is => "rw", isa => "Bool");

sub _build_imanager {
    my $self = shift;
    require TradeSpring::IManager::Cache;

    my $frame = TradeSpring::Frame->new( calc => $self->calc );
    return TradeSpring::IManager::Cache->new( frame => $frame );
}

sub BUILD {}
after BUILD => method {
    my @attrs = grep {$_->does('TradeSpring::Meta::Attribute::Trait::TSIndicator') }
                      $self->meta->get_all_attributes;
    for my $attr (@attrs) {
        $attr->set_value( $self =>
                              $self->imanager->load($attr->indicator,
                                                    %{ $attr->args }
                                                ) );
    }

    return unless $self->imanager->can('prepare');

    $self->imanager->prepare(0, $self->calc->prices->count-1, $self->use_cache);
    my $range = $self->range || [0, $self->calc->prices->count - 1];
    for my $attr (@attrs) {
        my $indicator = $attr->get_value( $self );
        $self->log->info("populating indicator: ".$indicator->as_string." for ".$attr->name." ".join(',', @$range));
        $self->imanager->get_values($indicator, @$range, $self->use_cache);
    }
    $self->imanager->frame($self);
};


package Moose::Meta::Attribute::Custom::Trait::TSIndicator;
sub register_implementation {'TradeSpring::Meta::Attribute::Trait::TSIndicator'}

package TradeSpring::Meta::Attribute::Trait::TSIndicator;
use Moose::Role;
use methods;

after 'attach_to_class' => sub {
};

has indicator => (is => "rw", isa => "Str");

has args => (
    is      => 'rw' ,
    isa     => 'HashRef' ,
    default => sub { {} },
);

1;
