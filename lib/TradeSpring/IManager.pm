package TradeSpring::IManager;
use Moose;
use UNIVERSAL::require;
use Method::Signatures::Simple;
use Graph;
use Graph::Traversal::DFS;

has frame => (is => "rw");

has indicator_traits => (is => "rw", isa => "ArrayRef");

has indicators => (is => "rw", isa => "HashRef", default => sub { { } });

has _cached_order => (is => "rw", isa => "ArrayRef", clearer => 'clear_order');

method order {
    unless ($self->_cached_order) {
        my $g = Graph->new;
        for (values %{ $self->indicators }) {
            $self->expand_tree($g, $_);
        }

        my @order = Graph::Traversal::DFS->new($g)->dfs;
        $self->_cached_order(\@order);
    }

    return $self->_cached_order;
}

method load($module, %args) {
    $self->clear_order;
    my $indicator = $self->load_module($module, %args);
    $self->indicators->{ $indicator->as_string } ||= $indicator;
}

method load_module($module, %args) {
    $module->require or die $@;
    if (my $traits = $self->indicator_traits) {
        return $module->new_with_traits( %args, frame => $self->frame, traits => $traits, loader => $self)
    }

    return $module->new( %args, frame => $self->frame, loader => $self);
}

method expand_tree($g, $i) {
    $g->add_vertex($i);
    for my $attr (grep {$_->has_value($i) &&
                            UNIVERSAL::isa($_->get_value($i), 'TradeSpring::I') }
                      $i->meta->get_all_attributes) {

        my $i_child = $attr->get_value($i);
        $g->add_vertex($i_child);
        $g->add_edge($i, $i_child);
        $self->expand_tree($g, $i_child);
    }
}


__PACKAGE__->meta->make_immutable;
no Moose;
1;
