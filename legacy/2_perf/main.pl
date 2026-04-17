#!/usr/bin/perl use Getopt::Long;
$cwd=pwd;
chomp($cwd);
$library = "";
$cell = "";
$manage = "unmanaged managed";
$ws = "";
$proj = "";
$id = "";
$mode="";
@generatedReplay;
$genOnly = 1;
$totalArgs = scalar(@ARGV);
GetOptions("lib=s" => \$library, "cell=s" => \$cell, "mode=s" => \$mode, "manage=s" => \$manage, "ws=s" => \$ws, "proj=s" => \$proj, "id=s" => \$id, "version=s" => \$version, "genOnly=s" => \$genOnly, );
if($version=~ /^$/) {
    print("Missing Virtuoso Version \n");
exit;
} if($library=~ /^~/) {
    print("Error lib argument Missing");
exit;
} if($cell =~ /^$/) {
    print("Error cell argument Missing");
exit;
} @libs = split(" ",$library);
@cells = split(" ",$cell);
if(scalar(@libs)!=scalar(@cells)){
    print("Lib Cell Pairs Mismatch\n");
exit;
} if($manage !~ /^(unmanaged managed|managed unmanaged|managed|unmanaged)$/){
    if($manage!~ /^$/){
    print "invalid combination\n";
exit;
}
} if($mode=~ /^$/) {
    @templates = ('checkHier','renameRefLib','replace','deleteAllMarker','copyHierToNonEmpty','copyHierToEmpty');
} else {
    @templates=split(/\s+/, $mode);
} chdir "GenerateReplayScript";
system("\\rm replay*.au");
foreach my $key(@templates) {
    print("./createReplay.pl -lib \"$library\" -cell \"$cell\" -template $key\n");
system("./createReplay.pl -lib \"$library\" -cell \"$cell\" -template $key\n");
} @replayFiles =ls replay*.au;
chdir $cwd;
system("\\rm code/replay/replay*.au");
system("cp -r GenerateReplayScript/replay*.au code/replay/");
open(maintmpl, "main.template") ||die "can't open script Template \n";
open(main.sh, ">main.sh") || die "Can;t open script \n";
$start=0;
while(<maintmpl>) {
    s/man_folders=\(\)/man_folders=\($manage\)/g;
s/(virtuoso_version=)/$1$version/g;
if(/replay_files=\(/){
    $start=1;
print mainsh $_;
next;
} if($start==1) {
    foreach my $key(@replayFiles) {
    print mainsh "$key";
} $start=0;
} print mainsh $_;
} close(mainsh);
system("chmod +x main.sh");
if($genOnly == 1) {
    exit;
} else {
    system("./main.sh");
}
