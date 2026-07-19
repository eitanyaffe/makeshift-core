use strict;
use warnings FATAL => qw(all);

# Batched version of table2params.pl.
#
# Usage:
#   table_batch.pl count <ifn> <batch_size>
#       -> prints number of batches (ceil(nrows / batch_size))
#
#   table_batch.pl batch <ifn> <field> <batch_size> <batch_index>
#       -> prints rows for the given 1-indexed batch in the same
#          "field=value:field=value field=value:..." format as table2params.pl
#
# Missing-file behavior mirrors table2params.pl: pretend the table has three
# rows carrying <field>=V1, V2, V3, so 'make -n' / 'make plan' can dry-run
# before the config table has been generated.

if ($#ARGV == -1) {
    print STDERR "usage: $0 count <ifn> <batch_size>\n";
    print STDERR "       $0 batch <ifn> <field> <batch_size> <batch_index>\n";
    exit 1;
}

my $mode = shift @ARGV;

if ($mode eq "count") {
    my ($ifn, $bs) = @ARGV;
    defined $bs or die "batch_size required";
    $bs > 0    or die "batch_size must be positive";
    my $n;
    if (!-e $ifn) {
        $n = 3;
    } else {
        open(my $fh, $ifn) or die $ifn;
        <$fh>;
        $n = 0;
        $n++ while <$fh>;
        close($fh);
    }
    print int(($n + $bs - 1) / $bs), "\n";
    exit 0;
}

if ($mode eq "batch") {
    my ($ifn, $field, $bs, $bi) = @ARGV;
    defined $bi or die "batch_index required";
    $bs > 0    or die "batch_size must be positive";
    $bi >= 1   or die "batch_index must be >= 1";

    my $start = ($bi - 1) * $bs;
    my $end   = $start + $bs;
    my $first = 1;

    if (!-e $ifn) {
        my @dummy = ("V1", "V2", "V3");
        for (my $i = $start; $i < $end && $i < scalar(@dummy); $i++) {
            print " " unless $first;
            $first = 0;
            print $field, "=", $dummy[$i];
        }
        exit 0;
    }

    open(my $fh, $ifn) or die $ifn;
    chomp(my $hdr = <$fh>);
    my @h = split(/\t/, $hdr);
    my $field_found = 0;
    for my $c (@h) { $field_found = 1 if $c eq $field; }
    $field_found or die "item field $field not found";

    my $row = 0;
    while (my $line = <$fh>) {
        last if $row >= $end;
        if ($row >= $start) {
            print " " unless $first;
            $first = 0;
            chomp $line;
            my @f = split(/\t/, $line);
            for (my $i = 0; $i < scalar(@f); $i++) {
                print ":" if $i > 0;
                print $h[$i], "=", $f[$i];
            }
        }
        $row++;
    }
    close($fh);
    exit 0;
}

die "unknown mode: $mode";
