procedure( imgHierParse( libName cellName viewName visitedCells visitedCellViews uniqueFiles )
prog( ( cv keyC keyCV instLib instCell cellObj checkView checkViewName)
	checkView = case(ddMapGetFileViewType(ddGetObj(libName cellName viewName "*"))
					(("schematicSymbol") list(viewName "schematic") ) 
					("schematic" list(viewName "symbol"))
					("maskLayout" list(viewName)) 
					(t nil))
	unless(checkView return(nil))
	
	keyC = strcat( libName "/" cellName )
	keyCV = strcat( libName "/" cellName "/" viewName)
	unless( visitedCellViews[keyCV]
		visitedCellViews[keyCV] = t

		when(visitedCells[keyC] checkView = list(viewName))
		visitedCells[keyC] = t

		cellObj = ddGetObj( libName cellName )
		if( cellObj then
;			foreach( fObj cellObj~>files
;				if(fObj~>readPath then
;					uniqueFiles[fObj~>readPath] = t
;				)
;			)
;
			foreach( vObj cellObj~>views
				if(member(vObj->name checkView) then
					if( vObj~>readPath && isDir(vObj~>readPath) then
						foreach( fileName getDirFiles(vObj~>readPath)
							if( fileName != "," && fileName != ".." then
								fileFullPath = strcat( vObj~>readPath "/" fileName )
								if( isFile(fileFullPath) then
									uniqueFiles[fileFullPath] = t
								)
							)
						)
					)
					if(member(vObj->name list("schematic" "layout")) then
						fileFullPath = strcat(cellObj~>readPath "/data.dm")
						println(fileFullPath)
						if( isFile(fileFullPath) then
							uniqueFiles[fileFullPath] = t
						)
					)
				)
				
			)
		)

		checkViewName = case(ddMapGetFileViewType(ddGetObj(libName cellName viewName "*"))
							(("schematicSymbol" "schematic") "schematic" ) 
							("maskLayout" "layout") 
							(t nil))

		cv = dbOpenCellViewByType( libName cellName checkViewName "" "r" )
		if( cv then
			foreach(inst cv~>instances
				instLib = inst~>libName
				instCell = inst~>cellName
				instView = inst~>viewName
				if( instLib != "analogLib" && instLib != "basic" && instLib == libName then
					imgHierParse( instLib instCell instView visitedCells visitedCellViews uniqueFiles)
				)
			)
		dbClose(cv)
		)
	)
))

procedure( mgHierParse( libName cellName @optional (viewName "schematic") (outputTextFile "./text.txt") )
let( ( visitedCells visitedCellViews uniqueFiles outPort count libObj cellObj )
	libObj = ddGetObj(libName)
	unless( libObj
		error("[ERROR]Library '%s' does not exists.\n" libName)
	)
	cellObj = ddGetObj(libName cellName)
	unless( cellObj
		error("[ERROR]Cell '%s' does not exists.\n" cellName)
        )

	visitedCells = makeTable("visited" nil)
	visitedCellViews = makeTable("visited" nil)
	uniqueFiles = makeTable("files" nil)

	printf("Traversing hierarchy for %s/%s/%s...\n" libName cellName viewName)

	imgHierParse( libName cellName viewName visitedCells visitedCellViews uniqueFiles )

	outPort = outfile(outputTextFile)
	if(outPort then
		count = 0
		foreach( filePath uniqueFiles
			fprintf( outPort "%s\n" filePath )
			count++
		)
		close(outPort)
		printf( "\n[SUCCESS]Dumped %d unique file paths to: %s\n" count outputTextFile )
	else
		printf( "\n[ERROR]Cannot open file %s for writing.\n" outputTextFile )
	)
	t
))
