package TradeSpring::PositionReport;
use Moose::Role;
use methods;
use List::Util qw(sum);
use MooseX::ClassAttribute;


has open_positions => (is => "rw", isa => "ArrayRef", default => sub { [] });

class_has _last_ym => (is => "rw", isa => "Str");
class_has _ym_cnt => (is => "rw", isa => "Int", default => sub { 0 });

has report_header => (is => "ro", isa => "Bool");

has report_fh => (is => "rw", default => sub { \*STDOUT });

method fill_position($dir, $price, $qty, $submit_i, %attrs) {
    my $pos = $self->open_positions;
    my $cp = (sum map { $_->{dir} } @$pos) || 0;
    if ($cp * $dir < 0) { # closing
        my $c = shift @$pos;
#        warn "closing $cp $dir ".Dumper($c) ; use Data::Dumper;
        my $date = $self->date;

        my ($y, $m, $d) = split(/[-\s]/, $date);
        my $dt = DateTime->new(year => $y, month => $m, day => $d);

        my ($ym) = $date =~ m/(\d{4}-\d{2})/;
        $ym =~ s/-//;
        if (!$self->_last_ym || $ym ne $self->_last_ym) {
            $self->_ym_cnt( 0 );
            $self->_last_ym($ym);
        }

        my $profit = ($price - $c->{price}) * $c->{dir};

        $c->{$_} = $attrs{$_} for keys %attrs;
        $self->_ym_cnt($self->_ym_cnt+1);
        syswrite $self->report_fh,
            join(",", $ym.'-'.sprintf('%03d',$self->_ym_cnt), $dt->ymd, $c->{dir},
                   $self->date($c->{i}), $date,
                   $c->{price}, $price, $profit,
                   $self->position_attributes($c)
               ).$/;
        $self->position_closed($profit, $qty);
    }
    else {
        push @$pos, { dir => $dir, price => $price, i => $self->i, qty => $qty,
                      submit_i => $submit_i, %attrs
                  };
    }
}

1;
