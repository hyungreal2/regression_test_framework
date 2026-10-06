procedure(Validate(ddid expectedState expectedVersion)
	prog((speclist result tokens)
	result=t
	speclist=gdmCreateSpecList()
	gdmAddSpecToSpecList(gdmCreateSpecFromDDID(ddid) speclist)
	rexCompile("(\\.cdslck.*)|(\\.oacache.*)|(\\.tmp\\.[a-z])")
	foreach(spec gdmstatus(speclist 6)
		tokens=parseString(car(spec))
		unless(or(rexMatchp("\\.cdslck.*" car(tokens)) rexMatchp("\\.oacache.*" car(tokens)) rexMatchp("\\.tmp\\.[a-z]" car(tokens)) rexMatchp("data.dm\\.*" car(tokens)) rexMatchp("thumbnail_128x128.png\\.*" car(tokens)))
			if(strcmp(cadr(tokens) expectedState) != 0 then
				printf("ERROR: %s expected %s but got %s\n" car(tokens)
			       		expectedState cadr(tokens))
				result=nil
			)
		)
	)
	gdmResetSpecList(speclist)
	foreach(spec gdmstatus(speclist 10)
		tokens=parseString(car(spec))
		unless(or(rexMatchp("\\.cdslck.*" car(tokens)) rexMatchp("\\.oacache.*" car(tokens)) rexMatchp("\\.tmp\\.[a-z]" car(tokens)) rexMatchp("data.dm\\.*" car(tokens)) rexMatchp("thumbnail_128x128.png\\.*" car(tokens)))
			if(strcmp(cadr(tokens) expectedVersion) != 0 then
				printf("ERROR: %s expected version %s but got %s\n" car(tokens)
			       	       expectedVersion cadr(tokens))
				result=nil
			)
		)
	)
	return(result)
	)
)

procedure(Validate_hier(ddid expectedState) ; expectedState={"CI" "CO"}
	prog(( result libName cellName hierCnt )
		result=t
		libName=ddid->lib->name
		cellName=ddid->cell->name

		mgHierParse( libName cellName "schematic" "./text.txt")

		case(expectedState
			("CI"
				ICM_runP4("-x text.txt files 2>/dev/null | sed 's/#.*//'> ./hier.txt")
				ICM_runP4("-x hier.txt opened 2>/dev/null | wc -l")
				if(ICM_IPCBuffer != "0\n" then
					printf("ERROR: %Y/%Y/%Y expected hier opened 0 but got %Y\n" 
									ddid->lib->name ddid->cell->name ddid->name ICM_IPCBuffer)
					result=nil
				)
			)
			("CO"
				ICM_runP4("-x text.txt files 2>/dev/null | sed 's/#.*//'> ./hier.txt")
				ICM_runCmd("cat hier.txt | wc -l")
				hierCnt = ICM_IPCBuffer
				ICM_runP4("-x hier.txt opened 2>/dev/null | wc -l")
				if(ICM_IPCBuffer != hierCnt then
					printf("ERROR: %Y/%Y/%Y expected hier opened %Y but got %Y\n" 
									ddid->lib->name ddid->cell->name ddid->name substring(hierCnt 1 strlen(hierCnt)-1) ICM_IPCBuffer)
					result=nil
				)
			)
		)
		return(result)
	)
)

procedure(Validate_hierAll(ddid openedPreCnt)
	prog(( result libName cellName libPath hierCnt openedCnt)
		result=t
		libName=ddid->lib->name
		cellName=ddid->cell->name
		libPath = ddGetObj(libName)~>writePath

		mgHierParse( libName cellName "schematic" "./text.txt")
		
		ICM_runP4("-x text.txt files 2>/dev/null | grep -v ' - delete' | sed 's/#.*//' | wc -l ")
		hierCnt=atoi(car(last(parseString(ICM_IPCBuffer "\n"))))

		;ICM_runP4("opened ... | wc -l")
		;openedPostCnt=atoi(car(last(parseString(ICM_IPCBuffer "\n"))))

		ICM_runP4(strcat("opened " libPath "... 2>/dev/null| wc -l"))
		openedCnt=atoi(car(parseString(ICM_IPCBuffer "\n")))

		if(openedPreCnt - hierCnt != openedPostCnt then
			printf("ERROR: %Y/%Y/%Y expected opened %Y in lib but got %Y\n" 
									ddid->lib->name ddid->cell->name ddid->name openedPreCnt-hierCnt openedPostCnt)
			result=nil
		)
		return(result)
	)
)

procedure(Validate_refCount(ddid expectedCount)
	prog((result refCount)
		result=t
		refCount=_ddBatchRefCount(ddid)
		if(expectedCount != refCount then
			printf("ERROR: %Y/%Y/%Y expected refCount %Y but got %Y\n" 
			       	ddid->lib->name ddid->cell->name ddid->name expectedCount refCount)
			result=nil
		)
		return(list(result refCount))
	)
)

procedure(Validate_fastCO(libName)
	prog(( result libWritePath allfilesCnt openedCnt )
		
		result=t
		libWritePath = ddGetObj(libName)->writePath
		
		ICM_runP4(strcat("files " libWritePath  "/... | grep -v ' - delete' | wc -l "))
		allfilesCnt=atoi(car(last(parseString(ICM_IPCBuffer "\n"))))

		ICM_runP4(strcat("opened " libWritePath  "/... | wc -l"))
		openedCnt=atoi(car(last(parseString(ICM_IPCBuffer "\n"))))
		if(allfilesCnt != openedCnt then
			printf("ERROR: %Y expected opened %Y in lib but got %Y\n" 
									libName allfilesCnt openedCnt)
			result=nil
		)
		return(result)
	)
)

procedure(Validate_hierCO(ddid)
	prog(( result libName cellName hierCnt openedCnt)
		
		result=t

		libName=ddid->lib->name
		cellName=ddid->cell->name
		libWritePath = ddGetObj(libName)->writePath

		mgHierParse( libName cellName "schematic" "./text.txt")
		
		ICM_runP4("-x text.txt files 2>/dev/null | sed 's/#.*//' | grep -v ' - delete' | wc -l ")
		hierCnt=atoi(car(last(parseString(ICM_IPCBuffer "\n"))))

		ICM_runP4(strcat("opened " libWritePath  "/... | wc -l"))
		openedCnt=atoi(car(last(parseString(ICM_IPCBuffer "\n"))))
		if(hierCnt != openedCnt then
			printf("ERROR: %Y/%Y/%Y expected opened %Y in lib but got %Y\n" 
									ddid->lib->name ddid->cell->name ddid->name hierCnt openedCnt)
			result=nil
		)
		return(result)
	)
)


procedure(Validate_allLibCI(libName)
	prog(( result libPath openedCnt)
		result=t
		libPath = ddGetObj(libName)~>writePath

		ICM_runP4(strcat("opened " libPath "... 2>/dev/null| wc -l"))
		openedCnt=atoi(car(parseString(ICM_IPCBuffer "\n")))
		if(openedCnt != 0 then
			printf("ERROR: %Y expected opened %Y in lib but got %Y\n" 
									libName 0 openedCnt)
			result=nil
		)
		return(result)
	)
)

procedure(Validate_otherRemainCO(ddid openedPreCnt resultCI)
	prog(( result libName cellName filesCnt openedPostCnt )
		
		result=t

		libName=ddid->lib->name
		cellName=ddid->cell->name
		filesCnt = 0
		
		when(resultCI
			ICM_runP4(strcat("files " ddid->writePath  "/... | grep -v ' - delete' | wc -l "))
			filesCnt=atoi(car(last(parseString(ICM_IPCBuffer "\n"))))
		)
		
		ICM_runP4(strcat("opened " ddid->lib->writePath "/... | wc -l"))
		openedPostCnt=atoi(car(last(parseString(ICM_IPCBuffer "\n"))))

		if(openedPreCnt - filesCnt != openedPostCnt then
			printf("ERROR: %Y/%Y/%Y expected opened %Y in lib but got %Y\n" 
					ddid->lib->name ddid->cell->name ddid->name openedPreCnt-filesCnt openedPostCnt)
			result=nil
		)
		return(result)
	)
)


procedure(Validate_otherNotInHierRemainCO(ddid openedPreCnt)
	prog(( result libName cellName hierCnt openedPostCnt)
		
		result=t
		libName=ddid->lib->name
		cellName=ddid->cell->name

		mgHierParse( libName cellName "schematic" "./text.txt")
		
		ICM_runP4("-x text.txt files 2>/dev/null | grep -v ' - delete' | sed 's/#.*//' | wc -l ")
		hierCnt=atoi(car(last(parseString(ICM_IPCBuffer "\n"))))

		ICM_runP4(strcat("opened " ddid->lib->writePath "/... | wc -l"))
		openedPostCnt=atoi(car(last(parseString(ICM_IPCBuffer "\n"))))
		if(openedPreCnt - hierCnt != openedPostCnt then
			printf("ERROR: %Y/%Y/%Y expected opened %Y in lib but got %Y\n" 
									ddid->lib->name ddid->cell->name ddid->name openedPreCnt-hierCnt openedPostCnt)
			result=nil
		)
		return(result)
	)
)


procedure(Validate_lock(libName cellName viewName)
	prog(()
		unless(geGetLockInfo(libName cellName viewName) == "(no data on lock available)"
			return(nil)
		)
		return(t)
	)
)
