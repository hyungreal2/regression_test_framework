procedure(date_virtuosoVer(@optional (prefix ""))
let((filePath port ver date_virtuosoVer)
filePath = strcat(prefix "date_virtuosoVer.txt")
if(isFile(filePath)
then
; read existing content port = infile(filePath)
gets(date_virtuosoVer port)
close(port)
date_virtuosoVer = substring(date_virtuosoVer 1 strlen(date_virtuosoVer)-1)
else
; remove "sub-version"
rexCompile("sub-version")
ver = rexReplace(getVersion(t) "" 1)
; remove all spaces
rexCompile(" ")
ver = rexReplace(ver "" 0)
date_virtuosoVer = strcat(sprintf(nil "%d" stringToTime(getCurrentTime())) "_" ver)
; create file and write content port = outfile(filePath)
fprintf(port "%s\n" date_virtuosoVer)
close(port) )
date_virtuosoVer ) )
