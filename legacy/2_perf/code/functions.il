;;Check Out 
procedure(dmCheckOut(fd RowNo libname cellname)
prog(();cv id rval str 

    ICM_Sensitivity_popup( "popup_V" libname cellname "schematic" "" "" ) 
    ICM_Hier_View_CO( "ICMHierVIEWCO" libname cellname "schematic" "" "" )
    hiSetCurrentForm('hier_operationForm) "\n" hiFormDone(hier_operationForm)
    win=deOpen(list(nil 'libName libname 'cellName cellname 'viewName "schematic") nil "a") 
    cv=gec() 
    id = cv~>view 
    rval=Validate(id "gdmStateCO" EXPECTED_VER) 
    if(boundp('rval) && rval then
	str =  "Check out PASS" 
	EXPECTED_VER++ 
    else 
	str = "Check out FAIL"
    )
    fprintf(fd "%s_%s_%s: %s\n" RowNo libname cellname str)  
    printf("%s_%s_%s: %s\n" RowNo libname cellname str)  

))


procedure(dmOpenTopCell(fd RowNo libname cellname )
prog(()

    win=deOpen(list(nil 'libName libname 'cellName cellname 'viewName "schematic") nil "a") 
    if(win then 
	fprintf(fd "RowNo_libname_cellname: deOpen UNEXPECTED pass\n")
    else 
	fprintf(fd "RowNo_libname_cellname: deOpen EXPECTED fail\n") 
	win=deOpen(list(nil 'libName libname 'cellName cellname 'viewName "schematic") nil "r"))
	cv=gec()  
	id=cv~>view 
	rval=Validate(id "gdmStateCI" EXPECTED_VER ) 
	if(DM_AUTO_CHECKOUT == t then
	    if(boundp('rval) && rval then 
	   	str = "Expected : Check Out , Current: Check Out"
	    else 
	   	str = "Expected : Check Out , Current: Check In"
	    )
	else
	    if(boundp('rval) && rval then 
	   	str = "Expected : Check In, Current: Check Out"
	    else 
	   	str = "Expected : Check In , Current: Check In"
	    )
	)
	fprintf(fd "%s_%s_%s: %s\n" RowNo libname cellname str)  
	printf("%s_%s_%s: %s\n" RowNo libname cellname str)  

))

procedure(controlInit()
prog(()

    DM_AUTO_CHECKOUT = t
    DM_AUTO_CHECKIN = t
    
    EXPECTED_VER = 1
))

procedure(checkoutValidate(fd RowNo libName cellName ) 
prog(()
    cv=gec()
    id=cv~>view 
    rval1=Validate(id "gdmStateCI" EXPECTED_VER ) 

    if(boundp('rval1) && rval1 then 
	str = "Check out PASS" 
    else 
	str = "Check out FAIL"
    )
    fprintf(fd "%s_%s_%s: %s\n" RowNo libName cellName str)

))

procedure(checkinValidate(fd RowNo libName cellName ) 
prog(()
    cv=gec()
    id=cv~>view
    rval1=Validate(id "gdmStateCI" EXPECTED_VER )

    if(boundp('rval1) && rval1 then
        str = "Check in PASS"
        EXPECTED_VER++
    else
        str = "Check in FAIL"
    )
    fprintf(fd "%s_%s_%s: %s\n" RowNo libName cellName str)
))


procedure(dmDeleteAllMarkers(cv fd saveOnOff @optional (RowNo "RowNo") (libname "libname") (cellname "cellname"))
prog(()

    initMarkerNum = length(cv~>markers)

    if(initMarkerNum == 0 then
	dbCreateMarker(cv "test_marker" "" list(0:0))
	initMarkerNum = length(cv~>markers)
    )

    geDeleteAllMarkerForm->type->all->value =  t
    geDeleteAllMarkerForm->scope->value="hierarchy starting from top cellview"
    geDeleteAllMarkerForm->geDelMarkerAccessMode->value="edit"
    if(saveOnOff then 
	geDeleteAllMarkerForm->geDelMarkerAutoSave->value = t	
    else
	geDeleteAllMarkerForm->geDelMarkerAutoSave->value = nil 	
    ) 
    
    hiFormDone(geDeleteAllMarkerForm)
    postMarkerNum = length(cv~>markers)
    if(postMarkerNum == 0 then
	;fprintf(fd "\tRowNo_libname_cellname: %s\n" "Validate PASS(All markers removed)" postMarkerNum)
	fprintf(fd "\t%s_%s_%s: All Marker Delete : Validate PASS\n" RowNo libname cellname)
	;printf("===\tDelete Markers Validate (Except PASS)\t===\n")
	;printf("\t All Marker Delete : Validate PASS\n")
	;result
    else
	;printf("===\tDelete Markers Validate (Except PASS)\t===\n")
	;printf("\t %d Makrker Remain : Validate FAIL\n" postMarkerNum )
	;fprintf(fd "\tRowNo_libname_cellname: %s, %d Markers Remain\n" "Validate FAIL(Not all markers removed)" postMarkerNum)
	fprintf(fd "\t%s_%s_%s: %d Makrker Remain : Validate FAIL\n" RowNo libname cellname postMarkerNum )
	;result = nil
    )
))


procedure(dmRenameRefLib(fd fromLib toLib libname )
prog(()

    libId = ddGetObj(libname)

    fromLibNum = checkInstNumByLibName(libId fromLib) 

    renameRefLib(fromLib toLib libname) 
    
    toLibNum = checkInstNumByLibName(libId toLib) 

    if(toLibNum == fromLibNum then
	return(t)
    else
	return(nil)
    )
))


procedure(checkInstNumByLibName(libId libname)
prog(()

    targetCellViews = nil 
    checkCell = libId~>cells 
    foreach(tmpCell checkCell
	targetCellViews = append(targetCellViews setof(obj tmpCell~>views obj~>name == "schematic" || obj~>name == "layout"  ))
    )


    fromInstNum = 0

    foreach(targetCellView targetCellViews
	tmpCellViewId = dbOpenCellViewByType(targetCellView~>lib~>name targetCellView~>cell~>name targetCellView~>name nil nil "r")
	dbRefreshCellView(tmpCellViewId)
	fromInstNum = fromInstNum + length(setof(obj tmpCellViewId~>instances obj~>libName == libname))
    )
    return(fromInstNum)
))



procedure(dmICMCancleCheckOut(fd popup_V libName cellName expectValue )
prog(()
    cvId = dbOpenCellViewByType(libName cellName "schematic" nil nil "r")
    CheckInCellList = dmGetHierInst(cvId)
    

    foreach(tmpCV CheckInCellList
	ICM_CancelCheckoutButton(tmpCV popup_V libName cellName)
	printf("xx")
    )

    rval1 = t
    foreach(tmpCV CheckInCellList
	rval1 = dmRunICMCancleCheckOutValidate(tmpCV~>view expectValue)
	printf("yy")
	if(!rval1 then	
    	    fprintf(fd "\tRowNo_libname_cellname: %s\n"  "Check in FAIL") 
	    return(nil)
	)
	
    )
    fprintf(fd "\tRowNo_libname_cellname: %s\n" "Check in PASS") 
    return(t)
    
))


procedure(dmRunICMCancleCheckOut(cv popup_V libName cellName)
let(()
   
    ICM_Sensitivity_popup(popup_V libName cellName "schematic" "" "")
    ICM_CancelCheckoutButton( "ICMCheckInButton" libName cellName "schematic" "" "" ) 
    hiDBoxUser(ICM_intHierWarning nil 2)

))

procedure(dmRunICMCancleCheckOutValidate(viewId expectValue)
let((val1)
    val1=Validate(viewId "gdmStateCO" expectValue) 
))

procedure(dmICMCheckIn(popup_V checkCellList)
prog((replayFId)

    replayFId = outfile("./checkin.replay")
    foreach(tmpCV checkCellList
	libName = tmpCV~>libName
	cellName = tmpCV~>cellName
	dmRunICMCheckIn(replayFId popup_V libName cellName)
	printf("add checkin %s %s\n" libName cellName)
    )
    close(replayFId)
))

procedure(testValidation(checkList expectValue)
prog((rval1)
    rval1 = t
    foreach(tmpCV  checkList
	rval1 = dmRunICMCheckInValidate(tmpCV~>view expectValue)
	if(!rval1 then	
    	    fprintf(fd "\tRowNo_libname_cellname: %s\n"  "Check in FAIL") 
	    rval1 = nil
	)
    )
    fprintf(fd "\tRowNo_libname_cellname: %s\n" "Check in PASS") 
    return(rval1)
))

procedure(dmRunICMCheckInValidate(viewId expectValue)
let((val1)
    val1=Validate(viewId "gdmStateCI" expectValue) 
))

procedure(dmRunICMCheckIn(rfd popup_V libName cellName)
let(()
   
    fprintf(rfd "\\i ICM_Sensitivity_popup(\"%s\" \"%s\" \"%s\" \"schematic\" \"\" \"\")\n" popup_V libName cellName)
    fprintf(rfd "\\i ICM_CheckInButton( \"ICMCheckInButton\" \"%s\" \"%s\" \"schematic\" \"\" \"\" )\n" libName cellName) 
    fprintf(rfd "\\i hiDBoxUser(ICM_intHierWarning nil 2)\n")
    fprintf(rfd "\\i hiDBoxUser(ICM_intHierWarning nil 1)\n")
    fprintf(rfd "\\i hiSetCurrentForm('ICM_menuCIform)\n")
    fprintf(rfd "\\i hiFormDone(ICM_menuCIform)\n") 
    fprintf(rfd "\\i iDBoxUser(ICM_intHierOkay nil 1)\n")
    fprintf(rfd "\\i hiDBoxUser(ICM_intHierError nil 1)\n")
    fprintf(rfd "\\i printf(\"xx\\n\")\n")
    
    
))

procedure(dmGetHierInst(cvId @optional (instList nil))
prog((targetInst tmpCVId )
	targetInst = setof(obj cvId~>instances obj~>purpose == "cell")
	foreach(tmpInst targetInst
	    if(ddGetObj(tmpInst~>libName tmpInst~>cellName "schematic" ) then
		tmpCVId = dbOpenCellViewByType(tmpInst~>libName tmpInst~>cellName "schematic" nil nil "r") 
		when( length(geGetEditCellView()~>instances) > 0
		    instList = cons(tmpCVId instList)
		    instList = append(instList dmGetHierInst(tmpCVId instList))
		)
	    )
	)
    return(removeListDuplicates(instList))
))


;----------------------------------------------------------
;; Add the property on schematic instances:- 
;----------------------------------------------------------
procedure(AddInstProperty(propName propValue)
let(( cv (cnt 0) propType visited )
	cv = geGetWindowCellView()
	visited = makeTable("visited" nil)

    propType = case(type(propValue)
        (fixnum  "int")
        (flonum  "float")
        (string  "string")
        (boolean "boolean")
        (t       "string")
    )

	cnt = iAddInstProperty(cv propName propType propValue visited 0)
))


procedure(iAddInstProperty(cv propName propType propValue visited cnt)
let(( tmpSCId masterName )
	visited[cv~>cellName] = t
	foreach( inst cv~>instances
		if( dbReplaceProp(inst propName propType propValue) then
			cnt++
		)
		masterName = inst~>cellName
		if( !visited[masterName] then
			visited[masterName] = t
			tmpSCId = dbOpenCellViewByType(inst~>libName inst~>cellName "schematic" nil "a")
			if( tmpSCId then
				cnt = iAddInstProperty( tmpSCId propName propType propValue visited cnt )
			)
		)
	)	
	dbSave(cv)
	dbClose(cv)
	cnt
))

;----------------------------------------------------------
;;Verify that property added
;----------------------------------------------------------
procedure(VerifyInstPropValue(total propName propValue)
let(( cv (cnt 0) visited )
	cv = geGetWindowCellView()
	visited = makeTable("visited" nil)

	cnt = iVerifyInstPropValue(cv propName propValue visited cnt)
    if(cnt == total && total > 0 then
        printf("Success: All %d instances have %s = %L\n" cnt propName propValue)
        t
    else
        printf("Failure: Only %d/%d instances match %s = %L\n" cnt total propName propValue)
        nil
    )
))

procedure(iVerifyInstPropValue(cv propName propValue visited cnt)
let(( tmSCId masterName )
	visited[cv~>cellName] = t
	foreach( inst cv~>instances
		if( dbFindProp(inst propName)~>value == propValue then
			cnt++
		)
		masterName = inst~>cellName
		if( !visited[masterName] then
			visited[masterName] = t
			tmpSCId = dbOpenCellViewByType(inst~>libName inst~>cellName "schematic" nil nil "a")
			if( tmpSCId then
				cnt = iVerifyInstPropValue(tmpSCId propName propValue visited cnt)
			)
		)
	)
	dbSave(cv)
	dbClose(cv)
	cnt
))


;----------------------------------------------------------
;;Add property & Verify END.
;----------------------------------------------------------
