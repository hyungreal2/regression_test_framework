;----------------------------------------------------------
;; deleteAllMarkers related starts
;----------------------------------------------------------

procedure(dmDeleteAllMarkers(cvId fd saveOnOff @optional (RowNo "RowNo") (libname "libname") (cellname "cellname"))
prog((checkCellList initMarkerNum postMarkerNum result)

    checkCellList = dmGetHierInst(cvId)
    initMarkerNum = 0

    foreach(tmpCell checkCellList
        initMarkerNum = initMarkerNum + length(tmpCell~>markers)
    )

    hiiSetCurrentForm('geDeleteAllMarkerForm)
    geDeleteAllMarkerForm->type->all->value =  t
    geDeleteAllMarkerForm->scope->value="hierarchy starting from top cellview"
    geDeleteAllMarkerForm->geDelMarkerAccessMode->value="edit"
    if(saveOnOff then
        geDeleteAllMarkerForm->geDelMarkerAutoSave->value = t
    else
        geDeleteAllMarkerForm->geDelMarkerAutoSave->value = nil
    )

    hiFormDone(geDeleteAllMarkerForm)

    postMarkerNum = 0

    foreach(tmpCell checkCellList
        postMarkerNum = postMarkerNum + length(tmpCell~>markers)
    )


    cond(
        (postMarkerNum == 0 && initMarkerNum > 0
        fprintf(fd "\t%s_%s_%s: All Marker Deleted : Validate PASS\n" RowNo libname cellname)
        result = t)
        (initMarkerNum == 0
        fprintf(fd "\t%s_%s_%s: No Marker To Delete : Validate FAIL\n" RowNo libname cellname)
        result = nil)
        (t
        fprintf(fd "\t%s_%s_%s: %d Marker Remained : Validate FAIL\n" RowNo libname cellname postMarkerNum)
        result = nil)
        )
    return(result)
))

;----------------------------------------------------------
;; deleteAllMarkers related ends
;----------------------------------------------------------

;----------------------------------------------------------
;; renameRefLib related starts
;----------------------------------------------------------

procedure(dmRenameRefLib(fromLib toLib libname )
prog((libId fromLibNum toLibNum reCheckFromLibNum )

    libId = ddGetObj(libname)
    when(!libId  
	printf("Error: CAT > Can't find <%s> lib\n" libname)
	return(nil)
    )

    fromLibNum = checkInstNumByLibName(libId fromLib) 

    when(fromLibNum == 0 
	printf("Error: CAT > The instance(s) to be renamed does not exist in the library\n")
	return(nil)
    )

    if(renameRefLib(fromLib toLib libname) == nil then
	return(nil)
    )
    
    toLibNum = checkInstNumByLibName(libId toLib) 

    reCheckFromLibNum  = checkInstNumByLibName(libId fromLib) 

    if(toLibNum == fromLibNum && reCheckFromLibNum == 0  then
	return(t)
    else
	printf("CAT > Instances are still fromLib(%s), Even though toLib(%s)\n" fromLib toLib) 
	return(nil)
    )
))


procedure(checkInstNumByLibName(libId libname)
prog(( targetCellViews checkCell targetCellViews fromInstNum tmpCellViewId fromInstNum )

    targetCellViews = nil 
    checkCell = libId~>cells 
    foreach(tmpCell checkCell
	targetCellViews = append(targetCellViews setof(obj tmpCell~>views obj~>name == "schematic" || obj~>name == "layout"  ))
    )


    fromInstNum = 0

    foreach(targetCellView targetCellViews
	tmpCellViewId = dbOpenCellViewByType(targetCellView~>lib~>name targetCellView~>cell~>name targetCellView~>name nil "r")
	dbRefreshCellView(tmpCellViewId)
	fromInstNum = fromInstNum + length(setof(obj tmpCellViewId~>instances obj~>libName == libname))
	dbClose(tmpCellViewId)
    )
    return(fromInstNum)
))

;----------------------------------------------------------
;; renameRefLib related ends
;----------------------------------------------------------

procedure(dmRunICMCheckInValidate(viewId expectValue preVerInfo)
let((val1)
    val1=Validate(viewId "gdmStateCI" preVerInfo  expectValue) 
))

procedure(dmGetHierInst(cvId @optional (instList nil) (visited nil))
prog((targetInst tmpCVId )
    when( !boundp('cvId) || cvId == nil
        printf("error: CAT > cvId is nil, supposing because of cvId was purged/freed(during Close Data Discard).\n")
	return(nil)
    )
    when( !tablep(visited)
        visited = makeTable("visited" nil)
    )
    when( visited[lsprintf("%s:%s:%s" cvId~>libName cvId~>cellName cvId~>viewName)]
        return(instList)
    )
    visited[lsprintf("%s:%s:%s" cvId~>libName cvId~>cellName cvId~>viewName)] = t
    
    targetInst = setof(obj cvId~>instances obj~>purpose == "cell")
    foreach(tmpInst targetInst
        if(ddGetObj(tmpInst~>libName tmpInst~>cellName "schematic" ) then
    	tmpCVId = dbOpenCellViewByType(tmpInst~>libName tmpInst~>cellName "schematic" nil "r") 
    	when( length(tmpCVId~>instances) > 0
    	    instList = cons(tmpCVId instList)
    	    instList = append(instList dmGetHierInst(tmpCVId instList visited))
    	)
        )
    )

    instList = cons(cvId instList)
    return(removeListDuplicates(instList))
))


procedure(getDDviewByCV(cellViewList)
prog(( ddViewList )
 
    foreach(tmpCellView cellViewList
        ddViewList = cons(ddGetObj(tmpCellView~>libName tmpCellView~>cellName tmpCellView~>viewName) ddViewList)
    )
    return(ddViewList)
))

procedure(getAllDDViewByLib(libName)
prog(( ddViewList ddCellList  )

     ddViewList = nil
     ddCellList = ddGetObj(libName)~>cells
     when(!ddCellList 
	printf("Error: CAT > Could not find cells in %s library\n" libName)
	return(nil)
     )

     foreach(tmpCell ddCellList
	foreach(tmpView tmpCell~>views
	    if(tmpView~>name == "schematic" || tmpView~>name =="layout" then
		ddViewList = cons(tmpView ddViewList)
	    )
	)
     )
     return(ddViewList)
))


procedure(closeAllCV()
let(()

    foreach(tmpCV dbGetOpenCellViews()
	dbClose(tmpCV)
    )
    printf("CAT > All Open cellveiw was closed\n")
))

procedure(dmDbCloseHier(cvId)
let(( cnt checkCellList )
    checkCellList = dmGetHierInst(cvId)
    foreach(tmpCell checkCellList
	cnt = 0
	while( and(dbValidP(tmpCell) cnt<30)
	    dbClose(tmpCell)
	    sleep(1)
	    cnt++
	)
    )
    printf("CAT > DB Close completed for cell hierarchical istances.\n")
  
))

;----------------------------------------------------------
;; replace related starts
;----------------------------------------------------------

procedure(AddInstProperty(propName propValue)
let(( cvId (cnt 0) propType visited )
    cvId = geGetWindowCellView()
    visited = makeTable("visited" nil)

    propType = case(type(propValue)
        (fixnum  "int")
        (flonum  "float")
        (string  "string")
        (boolean "boolean")
        (t       "string")
    )

    cnt = iAddInstProperty(cvId propName propType propValue visited 0)
))


procedure(iAddInstProperty(cvId propName propType propValue visited cnt)
prog(( tmpSCId  )

	visited[lsprintf("%s:%s" cvId~>libName cvId~>cellName)] = t
	if(cvId~>instances == nil then
	    printf("Property addition was skipped because no instances were gound within the %s cell.\n" cvId~>cellName)
	    dbSave(cvId)
	    dbClose(cvId)
	    return(cnt)
	)
	
	foreach( inst cvId~>instances
		if( dbReplaceProp(inst propName propType propValue) then
			cnt++
		)
		if( !visited[lsprintf("%s:%s" inst~>libName inst~>cellName)] then
			visited[lsprintf("%s:%s" inst~>libName inst~>cellName)] = t
			tmpSCId = dbOpenCellViewByType(inst~>libName inst~>cellName "schematic" nil "a")
			if( tmpSCId then
				cnt = iAddInstProperty( tmpSCId propName propType propValue visited cnt )
			)
		)
	)	
	dbSave(cvId)
	dbClose(cvId)
	return(cnt)
))

procedure(VerifyInstPropValue(total propName propValue)
let(( cvId (cnt 0) visited )
    cvId = geGetWindowCellView()
    visited = makeTable("visited" nil)

    cnt = iVerifyInstPropValue(cvId propName propValue visited cnt)
    if(cnt == total && total > 0 then
        printf("Success: All %d instances have %s = %L\n" cnt propName propValue)
        t
    else
        printf("Failure: Only %d/%d instances match %s = %L\n" cnt total propName propValue)
        nil
    )
))

procedure(iVerifyInstPropValue(cvId propName propValue visited cnt)
let(( tmpSCId )
    visited[lsprintf("%s:%s" cvId~>libName cvId~>cellName)] = t
    foreach( inst cvId~>instances
	if( dbFindProp(inst propName) && dbFindProp(inst propName)~>value == propValue then
	    cnt++
	    printf("%L %L \n" visited~>?? dbFindProp(inst propName))
	else
	    printf("dbFindProp(inst propName) == nil or dbFindProp(inst propName)~>value != propValue\n")
	)
	if( !visited[lsprintf("%s:%s" inst~>libName inst~>cellName)] then
	    visited[lsprintf("%s:%s" inst~>libName inst~>cellName)] = t
	    tmpSCId = dbOpenCellViewByType(inst~>libName inst~>cellName "schematic" nil "r")
	    if( tmpSCId then
		cnt = iVerifyInstPropValue(tmpSCId propName propValue visited cnt)
	    )
	)
    )
    cnt
))

;----------------------------------------------------------
;; replace related ends
;----------------------------------------------------------

procedure(dmCreateOpenWire(cvId)
prog(( checkCellList tmpLibName tmpCellName tmpCell )

    checkCellList =  dmGetHierInst(cvId)
    
    foreach(tmpCell checkCellList
	tmpLibName = tmpCell~>libName
	tmpCellName = tmpCell~>cellName 

        if(tmpCell~>mode == "r" then
            dbClose(tmpCell)
            tmpCell = dbOpenCellViewByType(tmpLibName tmpCellName  "schematic" nil "a")
            if(!tmpCell then
                tmpCell= dbOpenCellViewByType(tmpLibName tmpCellName  "schematic" nil "r")

            )

        )
	deleteObject(tmpCell~>markers)
        dbCreateLine(tmpCell list("wire" "drawing") list(0:0 0:1))
        dbSave(tmpCell)
    )
    return(t)
))

procedure(deleteObject(objList)
let(()
    foreach(tmpObj objList
	dbDeleteObject(tmpObj)
    )
))


procedure(dmCreateMarker(cvId)
let(( checkCellList tmpLibName tmpCellName tmpCell  )

    checkCellList =  dmGetHierInst(cvId)
    foreach(tmpCell checkCellList
        tmpLibName = tmpCell~>libName
        tmpCellName = tmpCell~>cellName

        if(tmpCell~>mode == "r" then
            dbClose(tmpCell)
            tmpCell= dbOpenCellViewByType(tmpLibName tmpCellName  "schematic" nil "a")
            if(!tmpCell then
                tmpCell= dbOpenCellViewByType(tmpLibName tmpCellName  "schematic" nil "r")

            )
        )
        dbCreateMarker(tmpCell "" "" list(0:0 0:1))
        dbSave(tmpCell)
    )
    printf("CAT > Markers was created\n") 
))


procedure(dmWriteModeValidation(cvId)
prog(( checkCellList tmpLibName tmpCellName tmpCell  )
    
    checkCellList =  dmGetHierInst(cvId)
    foreach(tmpCell checkCellList
        tmpLibName = tmpCell~>libName
        tmpCellName = tmpCell~>cellName
            tmpCell= dbOpenCellViewByType(tmpLibName tmpCellName  "schematic" nil "a")
            if(!tmpCell then
		return(nil)	
            )
	    dbClose(tmpCell)
        )

    return(t)
))

procedure(getHierVersion(hierCVList)
prog((hierVerInfoList tmpLibName tmpCellName tmpViewName tmpSymbol )

    hierVerInfoList = list(nil)

    foreach(tmpCvId hierCVList
	tmpLibName = tmpCvId~>libName
	tmpCellName = tmpCvId~>cellName
	tmpViewName = tmpCvId~>viewName

	tmpSymbol = stringToSymbol(sprintf(nil "%s/%s/%s" tmpLibName tmpCellName tmpViewName))
	
	hierVerInfoList = append(hierVerInfoList list(tmpSymbol getCurrentVersion(tmpLibName tmpCellName tmpViewName)))
    )

    return(hierVerInfoList)
    
))

procedure(getCurrentVersion(libName cellName viewName)
prog((ddid specList versionInfoList currentVerInfoList  tokens currentVerInfoList  )

    ddid = ddGetObj(libName cellName viewName)
    when(!ddid 
	return(nil)
    )
    specList = gdmCreateSpecList()
    gdmAddSpecToSpecList(gdmCreateSpecFromDDID(ddid) specList)
    versionInfoList = gdmstatus(specList 10)
    gdmResetSpecList(specList)

    currentVerInfoList = nil

    foreach(spec versionInfoList
	tokens=parseString(car(spec))
	unless(or(rexMatchp("\\.cdslck.*" car(tokens)) rexMatchp("\\.oacache.*" car(tokens)) rexMatchp("\\.tmp\\.[a-z]" car(tokens)) rexMatchp("data.dm" car(tokens)) rexMatchp("thumbnail" car(tokens)) rexMatchp("maestro" car(tokens)))

	    printf("B%s\n" car(tokens))
	    currentVerInfoList = append1(currentVerInfoList list(nth(0 tokens) nth(1 tokens)))
	)
    )

    return(currentVerInfoList)
    
))


procedure(getDDViewList(libName)
prog(( targetCellViews nonEmptyTargetCellViews checkCell targetCellViews tmpViewRead    )

;    targetCellViews = nil
    checkCell = ddGetObj(libName)~>cells
    foreach(tmpCell checkCell
        targetCellViews = append(targetCellViews setof(obj tmpCell~>views obj~>name == "schematic" || obj~>name == "layout"  ))
    )
;    nonEmptyTargetCellViews = nil
    foreach(tmpView targetCellViews
	tmpViewRead = dbOpenCellViewByType(libName tmpView~>cell~>name tmpView~>name nil "r")	
        if(tmpViewRead~>instances then
            nonEmptyTargetCellViews = cons(tmpView nonEmptyTargetCellViews)
        )
    )
    return(nonEmptyTargetCellViews)

))


procedure(getDBViewList(libName @optional (toLibName nil ))
prog(( targetCellViews nonEmptyTargetCellViews tmpDBView  )

    targetCellViews = nil
    checkCell = ddGetObj(libName)~>cells
    foreach(tmpCell checkCell
        targetCellViews = append(targetCellViews setof(obj tmpCell~>views obj~>name == "schematic" || obj~>name == "layout"  ))
    )
    nonEmptyTargetCellViews = nil
    foreach(tmpView targetCellViews
	tmpDBView = dbOpenCellViewByType(libName tmpView~>cell~>name tmpView~>name nil "r")
        if(tmpDBView~>instances then
	    if(toLibName == nil then
                nonEmptyTargetCellViews = cons(tmpDBView nonEmptyTargetCellViews)
	    else
		if(length(setof(obj tmpDBView~>instances obj~>libName == toLibName)) != length(tmpDBView~>instances) then
                    nonEmptyTargetCellViews = cons(tmpDBView nonEmptyTargetCellViews)
		)
	    )
        )
    )
    return(nonEmptyTargetCellViews)

))


procedure(dmRunChangeLibRef(chageLibList)
prog(( t1 t2 final inport managed  )

    t1=getCurrentTime()
    changeLibRef(chageLibList)
    t2=getCurrentTime()
    final=compareTime(t2 t1)
    ;system(strcat("mkdir -p " result_path date_virtuosoVer(code_path) ))
    inport = infile(strcat(code_path "managed.txt"))
    gets(managed inport)
    managed = substring(managed 1 strlen(managed)-1)
    close(inport)

    when(!boundp('managed) || managed == nil
        printf("Error : CAT > 'managed' variable is unbound/nil")
        return(nil)
    )

    return(managed)

))



procedure(getCurrentInstRefLib(targetLibName changeLibRefList)
prog(( ddViewList oriInstInfoList count tmpLib tmpCell tmpView symbolName oriInstInfoList tmpCvId changeLibRefInfo tmpValue  )


    ddViewList = getDDViewList(targetLibName)
    oriInstInfoList = list(nil)
    count = 1
    foreach(tmpDDView ddViewList

        tmpLib = tmpDDView~>lib~>name
        tmpCell = tmpDDView~>cell~>name
        tmpView = tmpDDView~>name

        symbolName = stringToSymbol(sprintf(nil "%s/%s/%s" tmpLib tmpCell tmpView))
        oriInstInfoList = append(oriInstInfoList list(symbolName nil))
        tmpCvId = dbOpenCellViewByType(tmpLib tmpCell tmpView nil "r")

        foreach(tmpInst tmpCvId~>instances

            if(changeLibRefInfo = car(setof(obj changeLibRefList nth(1 obj) == targetLibName || nth(1 obj) == 'ALL)) then
                tmpValue = get(oriInstInfoList symbolName)
                setf(get(oriInstInfoList symbolName) append1(tmpValue list(tmpInst->name tmpInst->libName nth(2 changeLibRefInfo) )))
            )
        )
    )
    return(oriInstInfoList)
))


procedure(validationChangeLibRef(targetLibName preCVInstInfoList)
prog(( ddViewList tmpLib tmpCell tmpView symbolName tmpCvId tmpPreCVInstInfo  tmpInst  )

    ddViewList = getDDViewList(targetLibName)

    foreach(tmpDDView ddViewList
        tmpLib = tmpDDView~>lib~>name
        tmpCell = tmpDDView~>cell~>name
        tmpView = tmpDDView~>name
        symbolName = stringToSymbol(sprintf(nil "%s/%s/%s" tmpLib tmpCell tmpView))

        tmpCvId = dbOpenCellViewByType(tmpLib tmpCell tmpView nil "r")
        tmpPreCVInstInfo = get(preCVInstInfoList symbolName)
	dbRefreshCellView(tmpCvId)

        foreach(tmpPreInstInfo tmpPreCVInstInfo
            tmpInst = dbGetInstByName(tmpCvId nth(0 tmpPreInstInfo))
            if(nth(2 tmpPreInstInfo) != tmpInst~>libName then
                printf("%s : %s\n" nth(2 tmpPreInstInfo) tmpInst~>libName)
;                printf("FAIL\n")
                return(nil)
            )
        )
    )
;    printf("SUCCESS\n")
    return(t)

))

procedure(dmCheckICMChangeNumber(preNum postNum )
prog(()
    if(postNum - preNum == 1 then
	return(t)
    else
	return(nil)
    )
))




