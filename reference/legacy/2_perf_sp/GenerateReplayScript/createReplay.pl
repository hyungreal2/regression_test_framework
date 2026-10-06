#!/usr/bin/perl

#======================================================
## Script name: createReplay.pl
#======================================================

use Getopt::Long;

#--------------------------------------------------------
# Initialize default values for command line arguments
#--------------------------------------------------------
$_library = "";
$_cell = "";
$template = "";

#--------------------------------------------------------
# Parse command-line arguments
#--------------------------------------------------------
GetOptions("lib=s" => \$_library,
	   "cell=s" => \$_cell,
	   "template=s" => \$template
    );

%spec;

if(-e $template) {
    print "";
}
else {
    print "Template Not Found \n";
    exit;
}

#--------------------------------------------------------
## Read the test specification file (test.spec)
#--------------------------------------------------------
open(testSpec, "test.spec");
while(<testSpec>) {
    if(/^$/) { next;}
    my @tmp = split("=");
    $spec{$tmp[0]} = $tmp[1];
}

#--------------------------------------------------------
# Determine the Library/Cell/View. 
# Generate the lcv.txt from command-line lib/cell pair
#--------------------------------------------------------
if($_library =~ /^$/) {
    $lcvPath = $spec{"LCVPath"};
    chomp($lcvPath);
}
else {
    open(lcv, ">lcv.txt");
    @libs=split(" ",$_library);
    @cells=split(" ",$_cell);

# Validate that each library has a corresponding cells
    if(scalar(@libs)!=scalar(@cells)) {
	print("Lib Cell Pairs mismatch\n");
	exit;
    }
    for($i=0; $i<scalar(@libs); $i=$i+1) {
	print lcv ("\"$libs[$i]\" \"$cells[$i]\" \"schematic\"\n");
    }
    $lcvPath="./lcv.txt";
}
close(lcv);

#--------------------------------------------------------
## Drive the replay file middle name from the template
#--------------------------------------------------------
$replayMid = $template;
$replayMid =~ s/\.au//g;

open(libcellview, "$lcvPath");

# Counter for numbering output replay files
$cnt = 1;
while(<libcellview>) {
    if(/^$/) { next;}

# Open a new numbered replay output file
    open(replayOut, ">replay.$replayMid$cnt.au");
    $lcv = $_;
    chomp($lcv);

# Create derived variable from the LCV triplet
    $tmplcv = $lcv;
    $cell = $lcv;
    $lib = $lcv;
    $tmplcv =~ s/"(\w+)"\s+"(\w+)"\s+"(\w+)"/$1_$2_$3/g;
    $cell =~ s/"(\w+)"\s+"(\w+)"\s+"(\w+)"/$2/g;
    $lib =~ s/"(\w+)"\s+"(\w+)"\s+"(\w+)"/$1/g;

# Read the template and perform subsitutions line by line
    open(template, $template);
    while(<template>) {
        s/(openDesign\()(.*\))/$1$lcv $2/g;
        s/(hiStartLog\()/$1"$tmplcv.log"/g;
        s/Replace_CellName_here/$tmplcv/g;
        s/Replace_Cell_here/$cell/g;
        s/Replace_Lib_here/$lib/g;
        s/(renameRefLib\()"(_\w+)"\s+"(_\w+)"\s+"(_\w+)"/$1"$lib$2" "$lib$3" "$lib$4"/g;
        print replayOut $_;
    }        
    close(replayOut);
    $cnt = $cnt + 1;
}

