;-------------------------------------
;# SKILL Function :open Design
;-------------------------------------

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

;------------------------------------------------------
;# SKILL Function Hier Copy in Non-Empty Library
;------------------------------------------------------

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


;-------------------------------------------------------------------------------------------
;Examples:-
;HierCopy("Opamp" "DualAmp" "" "Opamp_Skip_All_Libs" list())
;HierCopy("Opamp" "DualAmp" "" "Opamp_Skip_basic_Lib" list("basic"))
;HierCopy("Opamp" "DualAmp" "" "Opamp_Skip_basic_analog_Lib" list("basic" "analogLib" ))
;--------------------------------------------------------------------------------------------------------

;------------------------------------------------------
;# SKILL Function:  Hier Copy in New Empty Library
;------------------------------------------------------
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
;---------------------------------------------------------------------------------------------
; Ex: HierCopyToNewLib("Two_Stage_Opamp" "DualAmp" "" "new34" list("basic" "analogLib"))
;---------------------------------------------------------------------------------------------

;------------------------------------------------------
;# SKILL Function:  Rename Reference Library
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
;-----------------------------------------------------------------------
;Example: listHierLibCells("Two_Stage_Opamp" "DualAmp" "schematic")
;-----------------------------------------------------------------------

;------------------------------------------------------------------------
;# Load Samsung Env
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
