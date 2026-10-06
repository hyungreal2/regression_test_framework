procedure(sge_copyLibrary(srcLibName destLibName @optional (overwrite nil))
 let((srcLib destLib srcSpecList destSpecList srcSpec destSpec result)
     ;check source library exists
	srcLib=ddGetObj(srcLibName)
	unless(srcLib
	error("sge_copyLibrary: source library '%s' not found" srcLibName)
    )
      ;check destination library ; create if it does not exist
	destLib=ddGetObj(destLibName)
	unless(destLib
	printf("Destination library '%s' not found. Creating now ...\n" destLibName)
	destLib=ddCreateLib(destLibName)
	unless(destLib
	error("sge_copyLibrary:Failed to create destination library '%s'" destLibName)
    )
	printf("Created destination library '%s' at '%s'.\n" destLibName destLib~>readPath)
  )
       ;build source Spec list with library-level spec
	srcSpecList=gdmCreateSpecList()
 	srcSpec=gdmCreateSpec(srcLibName "" "" "" "CDBA")
	gdmAddSpecToSpecList(srcSpec srcSpecList)
       ;Build destination spec list with library-level spec
	destSpecList=gdmCreateSpecList()
	destSpec=gdmCreateSpec(destLibName "" "" "" "CDBA")
	gdmAddSpecToSpecList(destSpec destSpecList)

      ;perform the copy operation
	result=ccpCopy(srcSpecList destSpecList overwrite 'CCP_EXPAND_COMANAGED)
	if(result
		then 
	printf("Sucessfullly copied library '%s to '%s'.\n" srcLibName destLibName)
		else
	warn("sgeCopyLibrary: copied from '%s' to '%s' may have encounter issue.\n" srcLibName destLibName)
       )
	result
   )
 )
;-------------------------------------------------------------------------------------------------
procedure(sge_CopyLibraryMultiple(srcLibName destPrefix numCopies @optional (overwrite nil))
let((destLibName i)
for(i 1 numCopies
destLibName=sprintf(nil "%s%d" destPrefix i)
printf("-----Coping to '%s'(%d of %d) --\n" destLibName i numCopies)
sge_copyLibrary(srcLibName destLibName overwrite)
)
printf("Done. Created %d copies of '%s'.\n" numCopies srcLibName)

t
)
)
