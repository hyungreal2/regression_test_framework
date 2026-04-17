#!/usr/bin/perl
use Getopt::Long;

$_library = "";
$_cell    = "";
$template = "";

GetOptions(
    "lib=s"      => \$_library,
    "cell=s"     => \$_cell,
    "template=s" => \$template,
);

%spec;

if (-e $template) {
    print "";
} else {
    print "Template Not Found: $template\n";
    exit;
}

open(testSpec, "test.spec");
while (<testSpec>) {
    if (/^$/) { next; }
    my @tmp = split("=");
    $spec{$tmp[0]} = $tmp[1];
}
close(testSpec);

if ($_library =~ /^$/) {
    $lcvPath = $spec{"LCVPath"};
    chomp($lcvPath);
} else {
    open(lcv, ">lcv.txt");
    @libs  = split(" ", $_library);
    @cells = split(" ", $_cell);
    if (scalar(@libs) != scalar(@cells)) {
        print("Lib Cell Pairs mismatch\n");
        exit;
    }
    for ($i = 0; $i < scalar(@libs); $i++) {
        print lcv ("\"$libs[$i]\" \"$cells[$i]\" \"schematic\"\n");
    }
    $lcvPath = "./lcv.txt";
    close(lcv);
}

$replayMid = $template;
$replayMid =~ s/\.au//g;

open(libcellview, "$lcvPath");
$cnt = 1;
while (<libcellview>) {
    if (/^$/) { next; }

    open(replayOut, ">replay.$replayMid$cnt.au");

    $lcv = $_;
    chomp($lcv);
    $tmplcv = $lcv;
    $cell   = $lcv;
    $lib    = $lcv;

    $tmplcv =~ s/"(\w+)"\s+"(\w+)"\s+"(\w+)"/$1_$2_$3/g;
    $cell   =~ s/"(\w+)"\s+"(\w+)"\s+"(\w+)"/$2/g;
    $lib    =~ s/"(\w+)"\s+"(\w+)"\s+"(\w+)"/$1/g;

    open(tmpl, $template);
    while (<tmpl>) {
        s/(openDesign\()(.*\))/$1$lcv $2/g;
        s/(hiStartLog\()/$1"$tmplcv.log"/g;
        s/Replace_CellName_here/$tmplcv/g;
        s/Replace_Cell_here/$cell/g;
        s/Replace_Lib_here/$lib/g;
        s/(renameRefLib\()"(_\w+)"\s+"(_\w+)"\s+"(_\w+)"/$1"$lib$2" "$lib$3" "$lib$4"/g;
        print replayOut $_;
    }
    close(tmpl);
    close(replayOut);
    $cnt++;
}
close(libcellview);
