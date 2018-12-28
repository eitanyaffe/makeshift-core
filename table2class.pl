#!/usr/bin/env perl

use strict;
use POSIX;
use warnings FATAL => qw(all);
use File::Basename;

if ($#ARGV == -1) {
	print STDERR "usage: $0 <table> <class field> <class>\n";
	exit 1;
}

my $ifn = $ARGV[0];
my $field = $ARGV[1];
my $class = $ARGV[2];

open(IN, $ifn) || die $ifn;
my $header = <IN>;
my %h = parse_header($header);
my $index = 1;
while (my $line = <IN>) {
    chomp $line;
    my @f = split("\t", $line);
    my $instance = $f[$h{$field}];
    printf("\$(call _class_instance,taxa,%s%d,%s)\n", $class, $index, $instance);
    $index++;
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
