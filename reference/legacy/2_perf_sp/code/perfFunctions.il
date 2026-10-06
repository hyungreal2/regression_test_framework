;--------------------------------------------------------------------------------------
;# SKILL Function: Open the lib/cell/view 
; **EXAMPLE**
;openDesign("LibName" "CellName" "ViewName" "a") ;open design in edit mode.
;--------------------------------------------------------------------------------------

procedure( openDesign(lib cell view mode)
    let( (cellViewId windowId viewType)
        ; Determine the correct viewType based on the view name
        case( view
            ("schematic" viewType = "schematic")
            ("layout"    viewType = "maskLayout")
            ("symbol"    viewType = "schematicSymbol")
            (t           viewType = "schematic") ; Default fallback

        )

; Open the cellView with the detected viewType
        cellViewId = deOpenCellView(lib cell view viewType nil mode)
        if(cellViewId then
            printf("Opened %s/%s/%s as %s in %s mode.\n" lib cell view viewType mode)
            windowId = hiGetCurrentWindow()
        else
            printf("Failed to open %s/%s/%s.\n" lib cell view)

        )

        cellViewId

    )

)

;--------------------------------------------------------------------------------------------------------------------------------
;# SKILL Function: Hierarchical Copy in Non-Empty Library
; **EXAMPLE**
;HierCopy("SourceLib" "CellName" "" "DestLib" list()) ; Hier copy by Skip all library
;HierCopy("SourceLib" "CellName" "" "DestLib" list("basic")) ; Hier copy by skip the "basic" library
;HierCopy("Opamp" "DualAmp" "" "Opamp_Skip_basic_analog_Lib" list("basic" "analogLib" )) ; Hier copy by skip the "basic" & "analog" library
;--------------------------------------------------------------------------------------------------------------------------------

procedure( HierCopy(srcLib srcCell srcView destLib skipLibs)
  let( (src dst skip)
    ;; source & destination specs
    src  = gdmCreateSpecFromDDID(ddGetObj(srcLib srcCell srcView))
    dst  = gdmCreateSpecFromDDID(ddGetObj(destLib))
    ;; skip list
    skip = gdmCreateSpecList()
    foreach(lib skipLibs
      gdmAddSpecToSpecList(
        gdmCreateSpecFromDDID(ddGetObj(lib))
        skip
      )
    )
;; Hier copy
ccpCopyDesign(src dst t 'CCP_EXPAND_ALL skip nil list("schematic" "symbol"))
 )
  )


;----------------------------------------------------------------------------------------------------------------------------------------------------------
;# SKILL Function:  Hierarchical Copy in New Empty Library
; **EXAMPLE**
;HierCopyToNewLib("SourceLib" "CellName" "" "NewDestLib" list("basic" "analogLib")) ;Hier copy to new library by skip the "basic" & "analog" library
;----------------------------------------------------------------------------------------------------------------------------------------------------------
procedure( HierCopyToNewLib(srcLib srcCell srcView destLib skipLibs)
  let( (src dst skip)
;; source & destination specs
src  = gdmCreateSpecFromDDID(ddGetObj(srcLib srcCell srcView))
dst = gdmCreateSpec(destLib "" "" "" "CDBA" 0)
;dst  = gdmCreateSpecFromDDID(ddGetObj(destLib))
;; skip list
    skip = gdmCreateSpecList()
    foreach(lib skipLibs
      gdmAddSpecToSpecList(
        gdmCreateSpecFromDDID(ddGetObj(lib))
        skip
      )
    )
;; Hier copy
    ccpCopyDesign(src dst t 'CCP_EXPAND_ALL skip nil list("schematic" "symbol"))
    )
       )

;------------------------------------------------------
;# SKILL Function:  Rename Reference Library
; **EXAMPLE**
;renameRefLib(fromLibName toLibName updateLibName)
;------------------------------------------------------
procedure( renameRefLib(fromLibName toLibName updateLibName)
  let( (fromSpec toSpec updateList)
    fromSpec   = gdmCreateSpecFromDDID(ddGetObj(fromLibName))
    toSpec     = gdmCreateSpecFromDDID(ddGetObj(toLibName))
    updateList = gdmCreateSpecList()
    gdmAddSpecToSpecList(
      gdmCreateSpecFromDDID(ddGetObj(updateLibName))
      updateList
    )
    ccpRenameReferenceLib(fromSpec toSpec updateList)

  )

)

;------------------------------------------------------
;# SKILL Function: Delete Library
;------------------------------------------------------
procedure( deleteLibrary(libName)
    let( (libObj)
        libObj = ddGetObj(libName)
        if(libObj then
            ddDeleteObj(libObj)
            printf("Library %s deleted.\n" libName)
        else
            printf("Library %s not found.\n" libName)
        )
    )
)

;------------------------------------------------------
;# SKILL Function:  Dump Hier Cell Names
; **EXAMPLE**
;Example: listHierLibCells("LibName" "CellName" "schematic")
;------------------------------------------------------
procedure( listHierLibCells(libName cellName @optional (viewName "schematic"))
  let( (seen pairs)
    seen  = makeTable('seen nil)  ; set by "lib/cell" key
    pairs = nil
    procedure( _walk(l c)
      let( (cv key)
        key = sprintf(nil "%s/%s" l c)
        unless(seen[key]
          seen[key] = t
          pairs     = cons(key pairs)
          cv = dbOpenCellViewByType(l c "schematic" "" "r")
          when(cv
            foreach(inst cv~>instances
              when(inst~>master
                _walk(inst~>master~>libName inst~>master~>cellName)
              )
            )
            dbClose(cv)
          )
        )
      )
    )
    _walk(libName cellName)
    sort(pairs 'alphalessp)
  )
)

;------------------------------------------------------------------------
;# Load Samsung Env
; **EXAMPLE**
;LoadSamsungEnv() ;Will load samsung variables.
;------------------------------------------------------------------------
procedure( LoadSamsungEnv()
 schHiSRC("editOptions")
 schSRCForm->tabField->page1->floatingGlobalNets->value="error"
 schSRCForm->tabField->page8->scrollRegion->localNetNameUniqueCaseFold->value="error"
 schSRCForm->tabField->page8->scrollRegion->globalNetNameUniqueCaseFold->value="error"
 schSRCForm->tabField->page8->scrollRegion->instNameUniqueCaseFold->value="error"
 schSRCForm->tabField->page8->scrollRegion->propertyNameSyntax->value="error"
 schSRCForm->tabField->page8->scrollRegion->net_name_start_with_number->value="error"
 schSRCForm->tabField->page9->scrollRegion->inconsistent_bus_directions->value="error"
 schSRCForm->tabField->page9->scrollRegion->instance_shorted_to_global_all->value="error"
 schSRCForm->tabField->page9->scrollRegion->instance_input_port_shorted_to_global_signal->value="error"
 schSRCForm->tabField->page9->scrollRegion->instance_output_port_shorted_to_global_signal->value="error"
 schSRCForm->tabField->page9->scrollRegion->instance_bidir_port_shorted_to_global_signal->value="error"
 schSRCForm->tabField->page9->scrollRegion->instance_shorted_to_global_spice_primitive_ignore->value="error"
 schSRCForm->tabField->page10->scrollRegion->overlap_among_instances->value="error"
 schSRCForm->tabField->page10->scrollRegion->instances_in_blockage_area->value="error"
 schSRCForm->tabField->page10->scrollRegion->instance_with_homonym_master->value="error"
hiFormDone(schSRCForm)
 )


;------------------------------------------------------------------------
; change reference library script
; **INPUT**
; rules:	list(list(inLib fromLib toLib))
;
; **EXAMPLE**
; changeRefLib(list(list("libA" 'ALL "libA")))					; in libA, change all libraries to libA
; changeRefLib(list(list("libA" "libB" "libA") list("libA" "libC" "libA")))	; in libA, change libB and libC to libA
; changeRefLib(list(list("libA" "libB" "libA") list("libB" "libC" "libB")))	; in libA, change libB to libA; in libB, change libC to libB
;
;------------------------------------------------------------------------
procedure(changeRefLib(rules)
	let((rule updateList spec inLib fromLib toLib)
		inLibTable = makeTable('inLibTable list())
		foreach(rule rules
			inLib = nthelem(1 rule)
			fromLib = nthelem(2 rule)
			toLib = nthelem(3 rule)
			
			if(member(fromLib list('ALL 'All 'all)) then	
				inLibTable[inLib] = cons(list('fromLibAll nil 'fromCellAll nil 'fromViewAll nil 'toLib toLib 'toCellAsIs nil 'toViewAsIs nil) inLibTable[inLib])
			else
				inLibTable[inLib] = cons(list('fromLib fromLib 'fromCellAll nil 'fromViewAll nil 'toLib toLib 'toCellAsIs nil 'toViewAsIs nil) inLibTable[inLib])
			)
		)

		foreach(inLib inLibTable	
			updateList = gdmCreateSpecList()
			spec = gdmCreateSpec(inLib nil nil nil "CDBA")
			gdmAddSpecToSpecList(spec updateList)
			ccpChangeRefsByRule(updateList inLibTable[inLib] nil t)
		)	
	)
)

;-------------------------------------------------------------------------------
; revert ICM library after change reference library
; **INPUT**
; libName: STRING "libA"
;
; **EXAMPLE**
; changeRefLib_revertICM("libA" "managed")
; changeRefLib_revertICM("libA" "unmanaged")
;
;-------------------------------------------------------------------------------
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
				


procedure(changeRefLib_revertICM(libName managed)
prog((libPath)
	unless(member(managed list("managed" "unmanaged")) 
		warn("managed input only allow 'managed' or 'unmanaged'")
		return(nil)
	)

	libPath=ddGetObj(libName)->writePath
	oriPath = "/user/virtuoso.catdm/USERS/CAT_DM/paul_test/lib_MIX/"
	printf("libPath: %Y\noriPath: %Y\n" libPath oriPath)

	when(managed=="managed" Exec(strcat("xlp4 edit " libPath "/...")))
	Exec(strcat("/usr/bin/cp -rf " oriPath libName "/* " libPath))
	when(managed=="managed" Exec(strcat("xlp4 submit -d 'restore changeRefLib' " libPath "/...")))
	
	ddsHiRefresh()
)
)
