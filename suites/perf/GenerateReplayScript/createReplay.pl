#!/usr/bin/perl

use Getopt::Long;

$_library = "";
$_cell = "";
$template = "";
$manage = "";
$result = "";

GetOptions("lib=s" => \$_library,
	   "cell=s" => \$_cell,
	   "template=s" => \$template,
       "manage=s" => \$manage,
       "result=s" => \$result
    );

%spec;

if(-e $template) {
    print "";
}
else {
    print "Template Not Found \n";
    exit;
}
open(testSpec, "test.spec");
while(<testSpec>) {
    if(/^$/) { next;}
    my @tmp = split("=");
    $spec{$tmp[0]} = $tmp[1];
}

if($_library =~ /^$/) {
    $lcvPath = $spec{"LCVPath"};
    chomp($lcvPath);
}
else {
    open(lcv, ">lcv.txt");
    @libs=split(" ",$_library);
    @cells=split(" ",$_cell);
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

$replayMid = $template;
$replayMid =~ s/\.au//g;

open(libcellview, "$lcvPath");

$cnt = 1;
while(<libcellview>) {
    if(/^$/) { next;}
    $lcv = $_;
    chomp($lcv);
    $tmplcv = $lcv;
    $cell = $lcv;
    $lib = $lcv;
    $tmplcv =~ s/"(\w+)"\s+"(\w+)"\s+"(\w+)"/$1_$2_$3/g;
    $cell =~ s/"(\w+)"\s+"(\w+)"\s+"(\w+)"/$2/g;
    $lib =~ s/"(\w+)"\s+"(\w+)"\s+"(\w+)"/$1/g;
    open(replayOut, ">replay.$replayMid\_$lib\_$manage.au");
    open(template, $template);
    while(<template>) {
        s/(openDesign\()\s*"a"\s*(\))/$1$lcv "a" $2/g;
        s/(hiStartLog\()/$1"$tmplcv.log"/g;
        s/Replace_CellName_here/$tmplcv/g;
        s/Replace_Cell_here/$cell/g;
        s/Replace_Lib_here/$lib/g;
        s/(renameRefLib\()"(_\w+)"\s+"(_\w+)"\s+"(_\w+)"/$1"$lib$2" "$lib$3" "$lib$4"/g;
        s/managed=""/managed="$manage"/g;
        s/CDS_PV_REG_RES_NO/"$result"/g;
        
        print replayOut $_;
    }        
    close(replayOut);
    $cnt = $cnt + 1;
}

