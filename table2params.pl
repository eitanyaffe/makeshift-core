use strict;
use POSIX;
use warnings FATAL => qw(all);

if ($#ARGV == -1) {
        print STDERR "usage: $0 <ifn>< <item field>\n";
        exit 1;
}

my $ifn = $ARGV[0];
my $field = $ARGV[1];

if (!-e $ifn) {
    print "$field=V1 $field=V2 $field=V3";
    exit(0);
}

# read table
open(IN, $ifn) || die $ifn;
my $hline = <IN>;
chomp($hline);
my @h = split("\t", $hline);
my $first = 1;

my $max = 100;
my $count = 0;

while (my $line = <IN>) {
    if ($first) {
	$first = 0;
    } else {
	print " ";
    }
    chomp($line);
    my @f = split("\t", $line);
    my $item_field_found = 0;
    for (my $i=0; $i<scalar(@f); $i++) {
	print ":" if ($i > 0);
	print $h[$i], "=", $f[$i];
	$item_field_found = $item_field_found | $h[$i] eq $field;
    }
    $item_field_found or die "item field $field not found";
   #last if ($count++ == $max);
}
close(IN);
