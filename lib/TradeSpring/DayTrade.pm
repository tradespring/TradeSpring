package TradeSpring::DayTrade;
use Moose::Role;
use Method::Signatures::Simple;

requires 'highest_high';

has day_high => (is => "rw");
has day_low => (is => "rw");
has dcalc => (is => "ro");

has dstart => (is => "rw", isa => "Int");

has dframe => (
    is => "rw",
    isa => "TradeSpring::Frame",
    lazy_build => 1
);

has current_date => (is => "rw", isa => "DateTime");

has dframe_class => (is => "ro", isa => "Str", default => sub { 'TradeSpring::Frame' });

method _build_dframe {
    $self->dframe_class->new( calc => $self->dcalc );
}

before run => method {
    if ($self->is_dstart) {
        $self->dstart($self->i);
        $self->day_high( $self->highest_high );
        $self->day_low(  $self->lowest_low );
        if ($self->meta->find_attribute_by_name('dcalc') && $self->i > 0) {
            my ($last_day) = $self->date($self->i-1) =~ m/^([\d-]+)/;

            $self->dframe->i( $self->dcalc->prices->date($last_day) );
            my $date = $self->date;
            my ($y, $m, $d) = split(/[-\s]/, $date);
            $self->current_date(DateTime->new(year => $y, month => $m, day => $d));
        }
        $self->on_day_start if $self->can('on_day_start');
    }
};

after run => method {
    if (defined $self->day_high) {
        $self->day_high->test($self->i);
        $self->day_low->test($self->i);
    }
    else {
        warn "WTF?";
    }
};

1;
