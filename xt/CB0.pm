package CB0;
use warnings;
use 5.10.0;
use Moose;
use Method::Signatures::Simple;
extends 'TradeSpring::Frame', 'TradeSpring::Strategy';
use TradeSpring::Position;

method run {
    return unless $self->dframe->i;

    if ($self->hour >= 1330) {
        $self->on_end_of_day if $self->hour == 1330;
        return;
    }

    if ($self->position) {
        my $ww = $self->ne_ww;
        $ww->test($_) for ($self->i-$self->evxlength+1..$self->i);
        my $stp = $self->broker->get_order($self->position->stp_id);
        $self->broker->update_order($self->position->stp_id, $ww->current_value, undef,
                                    sub { $self->debug('updated stp to '.$ww->current_value.' from ' .$stp->{order}{price}.' evxlength: '.$self->evxlength) })
            if $self->bt($ww->current_value, $stp->{order}{price});

        return;
    }
    if ($self->pending_positions) {
        for (keys %{$self->pending_positions}) {
            (delete $self->pending_positions->{$_})->cancel;
        }
    }

    return unless $self->adx > 25;
    for my $dir (-1,1) {
        next unless $self->dfup * $dir > $self->dfdown * $dir;
        next unless $self->macd * $dir > $self->macd($self->i-1) * $dir;

        next if $dir == -1 && $self->adx >= 65;

        $self->mk_order($dir);
    }
}

method mk_order($dir) {
    local $self->{direction} = $dir;
    my $bb = $self->ne_bb;
    $bb->test($_) for ($self->i-$self->evlength+1..$self->i);
    if ($self->hour <= 900 || $self->hour >= 1320) {
        return;
    }
    if ( $self->day_high->current_value > $self->dframe->close * 1.05 ||
         $self->day_low->current_value  < $self->dframe->close * 0.95 ) {
        return;
    }

    $self->new_position(
        { type => 'stp',
          price => $bb->current_value,
          qty => 1 },
        { price => $bb->current_value * ( 1 - 0.01 * $dir) },
        undef,
        direction => $dir,
        on_entry => sub {
            my $pos = shift;
            $self->fill_position($dir, @_, $self->i);
            $self->direction($dir);
            $self->position($pos);
            $self->debug('entered');
            my $stp = $bb->current_value * ( 1 - 0.01 * $dir);
            $self->debug('stp :'.$stp);

            if ($_[0] != $bb->current_value) {
                $self->broker->update_order($self->position->stp_id, $_[0] * ( 1 - 0.01 * $dir),
                                            undef,
                                            sub { $self->debug('updated stp') });
            }
        },
        on_error => sub {
            warn "ERROR ".join(',',@_);
        },
        on_exit => sub {
            my ($pos, $type, $price, $qty) = @_;
            $self->fill_position($dir*-1, $price, $qty, $self->i);
            $self->clear_position;
            warn "$type matched: $price/$qty";
        }
    );

}

with 'TradeSpring::GTIndicators', 'TradeSpring::DayTrade', 'TradeSpring::Directional';

has_indicator (hlength => '@I:EXX 48 120 15');
has_indicator (llength => '@I:EXX 18 72 15');

has_indicator (hxlength => '@I:EXX 40 120 15');
has_indicator (lxlength => '@I:EXX 27 40 15');

has_indicator (adx => 'I:ADXR 15 15');

has_indicator (dfup =>   'I:ADX/2 15');
has_indicator (dfdown => 'I:ADX/3 15');

has_indicator (macd => 'I:MACD/1 5 34 5');


__PACKAGE__->mk_directional_method('evlength'  => 'hlength', 'llength');
__PACKAGE__->mk_directional_method('evxlength'  => 'hxlength', 'lxlength');

1;
