; revert ICM library after change reference library
; **INPUT**
; libName: STRING "libA"
;
; **EXAMPLE**
; changeRefLib_revertICM("libA" "managed")
; changeRefLib_revertICM("libA" "unmanaged")
;

procedure(Exec(cmd)
	let((cid)
		cid=ipcBeginProcess(cmd
			            ""
                                    lambda((c d) print("%s" d))
                                    lambda((c d) print("%s" d)))
		ipcWaitForProcess(cid)
		while(ipcIsAliveProcess(cid) ipcSleep(1))
	)
)
				


procedure(copyHierToEmpty_revertICM(libName managed)
prog((libPath)
	unless(member(managed list("managed" "unmanaged")) 
		warn("managed input only allow 'managed' or 'unmanaged'")
		return(nil)
	)

	libPath=ddGetObj(libName)->writePath

	if(managed=="managed" then
		printf("libPath: %Y\n" libPath)
		printf("Deleting library %Y...\n" libName)

		printf("1. xlp4 delete %Y/...\n" libPath)
		;Exec(strcat("xlp4 delete " libPath "/..."))
		Exec(strcat("find " libPath " -mindepth 1 ! -name 'cdsinfo.tag' -exec xlp4 delete {} +"))

		printf("2. xlp4 submit %Y/...\n" libPath) 
		Exec(strcat("xlp4 submit -d 'delete library' " libPath "/..."))

		printf("3. find %Y -mindepth 1 ! -name 'cdsinfo.tag' -exec /usr/bin/rm -rf {} + \n" libPath) 
		Exec(strcat("find " libPath " -mindepth 1 ! -name 'cdsinfo.tag' -exec /usr/bin/rm -rf {} +"))
	else
		printf("1. find %Y -mindepth 1 ! -name 'cdsinfo.tag' -exec /usr/bin/rm -rf {} + \n" libPath) 
		Exec(strcat("find " libPath " -mindepth 1 ! -name 'cdsinfo.tag' -exec /usr/bin/rm -rf {} +"))
	)
	
	
	ddsHiRefresh()
)
)
