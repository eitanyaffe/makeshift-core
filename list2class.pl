#!/usr/bin/env perl

use strict;
use POSIX;
use warnings FATAL => qw(all);
use File::Basename;

if ($#ARGV == -1) {
	print STDERR "usage: $0 <list file> <class>\n";
	exit 1;
}

my $ifn = $ARGV[0];
my $class = $ARGV[1];

open(IN, $ifn) || die $ifn;
my $index = 1;
while (my $inst = <IN>) {
    chomp $inst;
    printf("\$(call _class_instance,taxa,%s%d,%s)\n", $class, $index, $inst);
    $index++;
}
close(IN);
