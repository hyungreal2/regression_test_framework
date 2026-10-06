procedure(Validate(ddid expectedState preVerList expectedVersion)
prog((speclist result tokens postVersionList)
    result = t
    speclist=gdmCreateSpecList()
    gdmAddSpecToSpecList(gdmCreateSpecFromDDID(ddid) speclist)
    rexCompile("(\\.cdslck.*)|(\\.oacache.*)|(\\.tmp\\.[a-z])")

    foreach(spec gdmstatus(speclist 6)
        tokens = parseString(car(spec))
    
        ;;Exclude Thumbnail
        unless(or(rexMatchp("\\.cdslck.*" car(tokens)) rexMatchp("\\.oacache.*" car(tokens)) rexMatchp("\\.tmp\\.[a-z]" car(tokens)) rexMatchp("data\\.dm" car(tokens)) rexMatchp("thumbnail" car(tokens)) rexMatchp("maestro" car(tokens)))
            printf("A%s\n" car(tokens))
            if(strcmp(cadr(tokens) expectedState) != 0 then
                printf("ERROR: CAT > %s expected %s but got %s\n" car(tokens) expectedState cadr(tokens))
                result = nil
            )
        )
    )

    gdmResetSpecList(speclist)
    foreach(spec gdmstatus(speclist 10)
        tokens=parseString(car(spec))
        ;;Exclude Thumbnail
        unless(or(rexMatchp("\\.cdslck.*" car(tokens)) rexMatchp("\\.oacache.*" car(tokens)) rexMatchp("\\.tmp\\.[a-z]" car(tokens)) rexMatchp("data\\.dm" car(tokens)) rexMatchp("thumbnail" car(tokens)) rexMatchp("maestro" car(tokens)))
            postVersionList = car(setof(obj preVerList car(obj) == car(tokens)))
            if( postVersionList then
                if(evalstring(cadr(tokens)) != evalstring(cadr(postVersionList)) + expectedVersion then
                    printf("ERROR: CAT > %s expected version %d but got %d\n" car(tokens) evalstring(cadr(postVersionList)) + expectedVersion  evalstring(cadr(tokens)))
                    result=nil
                )
                else
                    printf("ERROR: CAT > postVersionList is not expected value.\n")
            )
        )
    )
    return(result)
))

;;Not need checkinout value(nil) when checkinList exist
procedure(libraryValidate(preICMChangeN preHierVerInfo libName checkinout expectNum @optional (cellName "cellname") (checkinList nil) (ChangeNum 1))
prog(( rval1 lockFiles objDir fileList lockFiles targetCellViews checkCell nonEmptyTargetCellViews str preVerInfo ddid ddIdCheckInList )
    rval1 = t
    lockFiles = list()
    printf("########## %L %L #########\n" libName cellName)
    objDir = ddGetObj(libName cellName "schematic")~>readPath
    printf("########## %L #########\n" objDir)
    fileList = getDirFiles(objDir)
    printf("########## %L #########\n" fileList)

    when( !boundp('objDir) || objDir == nil
        printf("ERROR: CAT > There is no objDir: %s/%s/%s\n" libName cellName "schematic")
        rval1 = nil
        return(rval1)
    )

    lockFiles = setof(file fileList rexMatchp("\\.cdslck$" file))
    when( lockFiles
        rval1 = nil
        printf("Error: CAT > .cdslck file Detected.\n")
        return(rval1)
    )

    targetCellViews = nil
    checkCell = ddGetObj(libName)~>cells
    when(!checkCell
        printf("Error: CAT > Can't find checkCell : <%s> lib\n" libname)
        return(nil)
    )

    foreach(tmpCell checkCell
        targetCellViews = append(targetCellViews setof(obj tmpCell~>views obj~>name == "schematic" || obj~>name == "layout"  ))
    )
    nonEmptyTargetCellViews = nil
    foreach(tmpView targetCellViews
        if(dbOpenCellViewByType(libName tmpView~>cell~>name tmpView~>name nil "r")~>instances then
            nonEmptyTargetCellViews = cons(tmpView nonEmptyTargetCellViews)
        )
    )

    foreach(targetCellView nonEmptyTargetCellViews
        str = sprintf(nil "%s/%s/%s" targetCellView~>lib~>name targetCellView~>cell~>name  targetCellView~>name)
        preVerInfo = get(preHierVerInfo str)
        ddid = ddGetObj(libName targetCellView~>cell~>name targetCellView~>name)
        when(!ddid
            printf("Error: CAT > Can't find ddid : <%s> <%s> <%s>\n" libname targetCellView~>cell~>name targetCellView~>name)
            return(nil)
        )
        if(checkinList == nil then
            ddid = ddGetObj(libName targetCellView~>cell~>name targetCellView~>name)
            when(!ddid
                printf("Error: CAT > Can't find ddid : <%s> <%s> <%s>\n" libname targetCellView~>cell~>name targetCellView~>name)
                return(nil)
            )
            if(checkinout == "out" then
                rval1 = Validate(ddid "gdmStateCO" preVerInfo  expectNum)
            else
                rval1 = Validate(ddid "gdmStateCI" preVerInfo  expectNum)
            )
            if(boundp('rval1) && !rval1 then
                return(nil)
            )
        else

            ddIdCheckInList = nil
            foreach(tmpCellView checkinList
                tmpddView = ddGetObj(libName tmpCellView~>cellName tmpCellView~>viewName)
                when(!ddid
                    printf("Error: CAT > Can't find tmpddView : <%s> <%s> <%s>\n" libname targetCellView~>cell~>name targetCellView~>name)
                    return(nil)
                )
                ddIdCheckInList = cons(tmpddView ddIdCheckInList)
            )


            if(member(ddid ddIdCheckInList) then
                printf("CheckIn:")
                rval1 = Validate(ddid "gdmStateCI" preVerInfo  expectNum)
            )
        )
            if(boundp('rval1) && !rval1 then
                return(nil)
            )
    )

    return(rval1)
))

procedure(hierValidation(preICMChangeN preHierVerInfo checkList expectValue @optional (RowNo "RowNo") (libname "libname") (cellname "cellname") (expectedGdmState "gdmStateCI"))
prog((rval1 rvals lockFiles)
    rval1 = nil
    rvals = nil
    if( expectedGdmState == "gdmStateCI" then
        lockFiles = nil
        objDir = ddGetObj(libname cellname "schematic")~>readPath
        when( !boundp('objDir) || objDir == nil
            rval1 = nil
            printf("ERROR: CAT > There is no objDir: %s/%s/%s\n" libName cellName "schematic")
            return(rval1)
        )
        fileList = getDirFiles(objDir)
        lockFiles = setof(file fileList rexMatchp("\\.cdslck$" file))
    
        when( lockFiles
            rval1 = nil
            printf("Error: CAT > .cdslck file Detected.\n")
            return(rval1)
        )

        foreach(tmpCV checkList
            str = sprintf(nil "%s/%s/%s" tmpCV~>libName tmpCV~>cellName tmpCV~>viewName)
            preVerInfo = get(preHierVerInfo str)
            rval1 = Validate(tmpCV~>view "gdmStateCI" preVerInfo expectValue)
            if(!rval1 then
                rvals = cons(rval1 rvals)
            )
        )

    else ;; when expectedGdmState == "gdmStateCO"
;        ;;Check number of revision 
;        if(Validate_ICMchanges() != preICMChangeN then
;            printf("%d:%d" Validate_ICMchanges() preICMChangeN)
;            printf("Error: CAT > Change Number is not 0\n")
;        )

        foreach(tmpCV checkList
            str = sprintf(nil "%s/%s/%s" tmpCV~>libName tmpCV~>cellName tmpCV~>viewName)
            preVerInfo = get(preHierVerInfo str)
            rval1 = Validate(tmpCV~>view "gdmStateCO" preVerInfo expectValue)
            if(!rval1 then
                rvals = cons(rval1 rvals)
            )
        )
    )

    printf("@@@@@@@@@@@@@@@@@ %L @@@@@@@@@@@@@@@\n" rvals)
    when( memq(nil rvals)
        return(nil)
    )

    rval1= t
    return(rval1)
))

procedure(Validate_ICMchanges()
let((changesCnt)
    if(isCallable('ICM_runP4) then
    ICM_runP4("changes ... 2>/dev/null| wc -l")
    changesCnt=atoi(car(parseString(ICM_IPCBuffer "\n")))
    changesCnt
    else
    println("ICM is not loaded")
          0
    )
))
