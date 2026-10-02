#!/usr/bin/perl
use strict;
use warnings;


my @templates=('checkHier','renameRefLib','replace','deleteAllMarker','copyHierToNonEmpty','copyHierToEmpty');
foreach my $template(@templates) {
printf "--status $template =\n";
my $exit_status=system("perl createReplay.pl $template");

if($exit_status!=0) {
	print "FAIL" ;
	}
	else { 
	print "sucess";
	}
	}
	print "all completed \n";
