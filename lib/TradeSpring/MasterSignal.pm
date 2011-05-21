package TradeSpring::MasterSignal;
use Moose::Role;


has master_idx => (is => "rw", isa => "Int", default => sub {  0 });


has master_record => (
    is => "rw",
    isa => "ArrayRef",
    lazy_build => 1
);

sub _build_master_record {
    my $self = shift;
    my $records = [];
    use Text::CSV_XS;
    my $csv = Text::CSV_XS->new;

    open my $fh, '<', $self->master_file or die $!;

    my @headers = @{$csv->getline($fh)};
    my $calc = $self->calc;

    while (my $row = $csv->getline($fh)) {
        my $entry = {};
        @{$entry}{@headers} = @$row;
        my $p = $calc->prices;
        $entry->{open_i} = $p->date($entry->{open_date}) or next;
        $entry->{close_i} = $p->date($entry->{close_date});
        push @$records, $entry;
    }

    return $records;
}


sub master_entry {
    my $self = shift;
    $self->master_record->[$self->master_idx]->{open_price};
}

sub master {
    my ($self, $i) = @_;
    $i //= $self->i;
    return if $self->master_idx > $#{$self->master_record};
    my $r = $self->master_record->[$self->master_idx];
    if ($i < $r->{open_i}) {
        return 0;
    }
    else {
        if ($i < $r->{close_i}) {
            return $r->{dir};
        }
        ++$self->{master_idx};
    }
    return 0;
}

has master_file => (is => "rw", isa => "Str");


1;
