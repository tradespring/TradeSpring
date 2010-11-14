package TradeSpring::DayTrade;
use Moose::Role;
use Method::Signatures::Simple;

requires 'highest_high';

has day_high => (is => "rw");
has day_low => (is => "rw");

has di => (is => "rw", isa => "Int");

has dstart => (is => "rw", isa => "Int");

before run => method {
    if ($self->is_dstart) {
        $self->dstart($self->i);
        $self->day_high( $self->highest_high );
        $self->day_low(  $self->lowest_low );
        if ($self->meta->find_attribute_by_name('dcalc') && $self->i > 0) {
            my ($last_day) = $self->date($self->i-1) =~ m/^([\d-]+)/;
            $self->di( $self->dcalc->prices->date($last_day) );
        }
    }

    if (defined $self->day_high) {
        $self->day_high->test($self->i);
        $self->day_low->test($self->i);
    }
    else {
        warn "WTF?";
    }
};

1;
