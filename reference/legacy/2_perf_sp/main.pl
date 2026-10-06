#!/usr/bin/perl

#============================================================
# Script: main.pl
#============================================================

use Getopt::Long;

# Store the current working directory to  retrun to later
$cwd=`pwd`;
chomp($cwd);

#----------------------------------------------------------
# Initialize default values for command line arguments.
#----------------------------------------------------------

$library = ""; # Space-seperated list of library names
$cell = ""; # Space-seperated list of cell names
$manage = "unmanaged managed"; # Default manage mode are both
$ws = "";
$proj = "";
$id = "";
$mode="";
@generatedReplay;
$genOnly = 1;
$totalArgs = scalar(@ARGV);

#----------------------------------------------------------
# Parse Command-line arguments
#----------------------------------------------------------

GetOptions("lib=s" => \$library,
	   "cell=s" => \$cell,
	   "mode=s" => \$mode,
	   "manage=s" => \$manage,
	   "ws=s" => \$ws,
	   "proj=s" => \$proj,
	   "id=s" => \$id,	   
	   "version=s" => \$version,
	   "genOnly=s" => \$genOnly,
    );

#----------------------------------------------------------
# Input Validation
#----------------------------------------------------------
    
# Ensure Virtuoso version is provided   
if($version=~ /^$/) {
    print("Missing Virtuoso Version \n");
    exit;
}

# Ensure library argumnet is provided.
if($library=~ /^~/) {
    print("Error lib argument Missing");
    exit;
}

# Ensure Cell argumnet is provided.
if($cell =~ /^$/) {
    print("Error cell argument Missing");
    exit;
}

# Ensure library and Cell into arrays
@libs = split(" ",$library);
@cells = split(" ",$cell);

# Validate that each library has a corresponding cell
if(scalar(@libs)!=scalar(@cells)){
    print("Lib Cell Pairs Mismatch\n");
    exit;
}

# Validate the manage option against allowed combinations
if($manage !~ /^(unmanaged managed|managed unmanaged|managed|unmanaged)$/){
    if($manage!~ /^$/){
	print "invalid combination\n";
	exit;
    }
}

#----------------------------------------------------------
# Determine which templates to use.
# if no mode is specified,use all available templates
#----------------------------------------------------------

if($mode=~ /^$/) {
    @templates = ('checkHier','renameRefLib','changeRefLib','replace','deleteAllMarker','copyHierToNonEmpty','copyHierToEmpty');
}
else {
    @templates=split(/\s+/, $mode);
}

#----------------------------------------------------------
# Generate replay(.au) files from templates.
#----------------------------------------------------------
# Navigate the replay generation directory and clean up previously generated replay files
chdir "GenerateReplayScript";
system("\\rm replay*.au");

# Invoke createReplay.pl for each selected template.
foreach my $key(@templates) {
    print("./createReplay.pl -lib \"$library\" -cell \"$cell\" -template $key\n");
    system("./createReplay.pl -lib \"$library\" -cell \"$cell\" -template $key\n");
}
@replayFiles =`ls replay*.au`;

chdir $cwd;

#----------------------------------------------------------
# Assemble the main.sh script from template
#----------------------------------------------------------
system("\\rm code/replay/replay*.au"); # Clean up the replay files in the code/replay directory
system("cp -r GenerateReplayScript/replay*.au code/replay/"); # Copy newly generated replay files to code/replay directory
open(maintmpl, "main.template") ||die "can't open script Template \n"; # open main.template file
open(main.sh, ">main.sh") || die "Can;t open script \n"; # open main.sh file for writing

# Process the template line by line and perform substitutions.
$start=0;
while(<maintmpl>) {
    s/man_folders=\(\)/man_folders=\($manage\)/g;
    s/(virtuoso_version=)/$1$version/g;

    if(/replay_files=\(/){
	$start=1;
	print mainsh $_;
	next;
    }
    if($start==1) {
	foreach my $key(@replayFiles) {
	    print mainsh "$key";
	}
	$start=0;
    }
    print mainsh $_;
}

close(mainsh); # close file handles
system("chmod +x main.sh"); # Make the script executable

if($genOnly == 1) {
    exit;
}
else {
    system("./main.sh");
    
}
