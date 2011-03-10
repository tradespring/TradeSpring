package TradeSpring::PS::MarketMoney;
use Moose;
use Method::Signatures::Simple;
use MooseX::Storage;

with Storage(format => 'YAML', io => 'File', traits => ['OnlyWhenBuilt']);

with 'MooseX::Log::Log4perl';
use List::Util qw(max sum);

has base => (is => "rw", isa => "Num");
has equity => (is => "rw", isa => "Num", trigger => \&_set_equity);

has equity_seen => (is => "rw", isa => "ArrayRef", default => sub { [] });
has base_reset_ma => (is => "rw", isa => "Int", default => sub { 5 } );

has base_risk => (is => "rw", isa => "Num", default => sub { 0.04 });
has mm_risk => (is => "rw", isa => "Num", default => sub { 0.01 });

method reset_base($e) {
    $self->base($e);
    $self->equity_seen([]);
    $self->equity($e);
}

method _set_equity($e) {
    my $total = $self->equity_seen;
    push @$total, $e;
    my $ma = $self->base_reset_ma;
    if (scalar @$total > $ma) {
        shift @$total;
        my $base = (sum @$total)/$ma;
        if ($base > $self->base) {
            $self->base($base);
#            $self->log->info("update base to $base, equity = $e");
        }
    }
}

method get_qty($r) {
    my $e = $self->equity;
    my $risk = ($e * $self->base_risk + max(0, ($e - $self->base)) * $self->mm_risk);
    my $qty = int($risk / $r);

#    $self->log->info("risking $risk, qty = $qty");
    return $qty;
}

__PACKAGE__->meta->make_immutable;
no Moose;


