package CB0;
use warnings;
use 5.10.0;
use Moose;
use Method::Signatures::Simple;
extends 'TradeSpring::Frame', 'TradeSpring::Strategy';
use TradeSpring::Position;
use List::Util qw(max min);

method run {
    return unless $self->dframe->i;

    if ($self->hour >= 1330) {
        $self->on_end_of_day if $self->hour == 1330;
        return;
    }

    if ($self->pending_order) {
        $self->cancel_pending_order;
    }
    if ($self->position_entered) {
        my $ww = $self->ne_ww;
        $ww->test($_) for ($self->i-$self->evxlength+1..$self->i);
        $self->update_stp_price($ww->current_value,
                                sub { $self->debug('updated stp to '.$ww->current_value.' evxlength: '.$self->evxlength) });

        return;
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
    if ( max($self->day_high->current_value, $self->high) > $self->dframe->close * 1.05 ||
         min($self->day_low->current_value , $self->low ) < $self->dframe->close * 0.95 ) {
        return;
    }

    $self->new_bracket_order(
        { dir => $dir,
          type => 'stp',
          price => $bb->current_value,
          qty => $self->position_qty },
        { price => $bb->current_value * ( 1 - 0.01 * $dir) },
        undef,
        on_entry => sub {
            my $pos = shift;
            $self->direction($dir);

            my $stp = $bb->current_value * ( 1 - 0.01 * $dir);
            $self->debug('stp :'.$stp);
            if ($_[0] != $bb->current_value) {
                $self->update_stp_price($_[0] * ( 1 - 0.01 * $dir),
                                        sub { $self->debug('updated stp') });
            }
        },
        on_error => sub {
            warn "ERROR ".join(',',@_);
        }
    );

}

with 'TradeSpring::GTIndicators', 'TradeSpring::DayTrade', 'TradeSpring::Directional',
    'TradeSpring::BracketOrder';

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
