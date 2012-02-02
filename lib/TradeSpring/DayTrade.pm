package TradeSpring::DayTrade;
use 5.10.1;
use Moose::Role;
use Method::Signatures::Simple;
use TradeSpring;

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

has dframe_class => (is => "ro", isa => "Str", default => sub { 'TradeSpring::Frame' });

has current_date => (is => "rw", isa => "DateTime");
has is_dstart => (is => "rw", default => sub { 1 });
has is_next => (is => "rw", default => sub { 1 });

has contract_code => (is => "rw", isa => "Str");
has contract => (
    is => "rw",
    isa => "Maybe[Finance::Instrument]",
    lazy_build => 1
);

has is_last_day => (is => "rw", isa => "Bool");

has sessions => (is => "rw", isa => "Maybe[ArrayRef]");
has current_session_idx => (is => "rw", isa => "Int", default => sub { 0 });


method _build_contract {
    return unless $self->contract_code;
    TradeSpring->config->get_instrument($self->contract_code);
}

method _build_sessions {
    return unless $self->contract;
    $self->contract->session;
}

method current_session {
    Carp::cluck unless $self->sessions;
    $self->sessions->[$self->current_session_idx];
}

method _build_dframe {
    $self->dframe_class->new( calc => $self->dcalc,
                              $self->contract ? (contract => $self->contract,
                                                 contract_code => $self->contract_code) : () );
}

around '_set_i' => sub {
    my ($next, $self, $i, $old_i) = @_;

    if (!$self->contract) {
        $self->$next($i, $old_i);
        # fall back to default dstart check
        if (!$self->last_hour || $self->hour < $self->last_hour ) {
            $self->is_dstart(1)
        }
        else {
            $self->is_dstart(0);
        }
        my ($y, $m, $d) = split(/[-\s]/, $self->date);
        $self->current_date(DateTime->new(year => $y, month => $m, day => $d));
        return;
    }

    if ((defined $old_i && $i != $old_i + 1)) {
        # reset;
        return $self->$next($i, $old_i);
    }

    if (!defined $old_i) {
        $self->is_dstart(1);
    }
    else {
        $self->check_dstart;
    }

    $self->$next($i, $old_i);
    $self->check_session;
};

method check_dstart {
    # determine if next is dstart
    if ($self->current_min == $self->current_session->[1] &&
        $self->current_session_idx == $#{$self->sessions}) {
        $self->is_dstart(1);
    }
    else {
        $self->is_dstart(0);
    }

    my $is_next = $self->is_dstart ? 1 : (($self->current_min >= $self->current_session->[1]) ||
                                           $self->current_min < $self->current_session->[0]);
    $self->is_next($is_next);
};

method run {}
before run => method {
    if ($self->is_dstart) {
        $self->dstart($self->i);
        $self->day_high( $self->highest_high );
        $self->day_low(  $self->lowest_low );
        if ($self->meta->find_attribute_by_name('dcalc') && $self->i > 0) {
            my ($last_day) = $self->date($self->i-1) =~ m/^([\d-]+)/;

            $self->dframe->i( $self->dcalc->prices->date($last_day) //
                              $self->dcalc->prices->date($last_day.' 00:00:00') );
        }
        $self->on_day_start if $self->can('on_day_start');
    }
};

method check_session {
    if ($self->is_dstart) {
        my $Strp_time = DateTime::Format::Strptime->new(
            pattern     => '%F %T',
            time_zone   => $self->contract->time_zone,
        );

        my ($s, $dt, $idx) = $self->contract->derive_session($Strp_time->parse_datetime($self->date));
        $self->current_date($dt);
        $self->sessions($s);
        $self->current_session_idx($idx);
        my $current = $self->contract->near_term_contract($dt);
        $self->is_last_day( $current && $current->last_trading_day->ymd eq $dt->ymd );
    }
    elsif ($self->is_next) {
        Carp::cluck if $self->current_session_idx  == 1;
        $self->current_session_idx( $self->current_session_idx + 1);
    }

    if ($self->current_session->[0] < 0) {
        $self->current_min($self->current_min - 1440)
            if $self->current_min > $self->current_session->[1];
    }
}

method order_timed($h, $m, $s) {
    return $self->current_date->epoch + $h * 3600 + $m * 60 + $s;
}

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
