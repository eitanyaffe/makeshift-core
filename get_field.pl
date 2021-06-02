use strict;
use POSIX;
use warnings FATAL => qw(all);

if ($#ARGV == -1) {
        print STDERR "usage: $0 <ifn> <field>\n";
        exit 1;
}

my $ifn = $ARGV[0];
my $field = $ARGV[1];

if (!-e $ifn || -s $ifn == 0) {
    print "V1 V2 V3";
    exit(0);
}

# read table
open(IN, $ifn) || die $ifn;
my $header = <IN>;
my %h = parse_header($header);
my $first = 1;
while (my $line = <IN>) {
    chomp($line);
    my @f = split("\t", $line);
    if ($first) {
	$first = 0;
    } else {
	print " ";
    }
    print $f[$h{$field}];
}
close(IN);

sub parse_header
{
	my ($header) = @_;
	chomp($header);
	my @f = split("\t", $header);
	my %result;
	for (my $i = 0; $i <= $#f; $i++) {
		$result{$f[$i]} = $i;
	}
	return %result;
}
