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

;------------------------------------------------------
;# SKILL Function:  Rename Reference Library
;------------------------------------------------------
procedure( renameRefLib(fromLibName toLibName updateLibName)
prog( (fromSpec toSpec updateList)

    when(!ddGetObj(fromLibName)
        printf("Error : Can't found fromLib(%s)\n" fromLibName)
        return(nil)
    )

    when(!ddGetObj(toLibName)
        printf("Error : Can't found toLib(%s)\n" toLibName)
        return(nil)
    )

    fromSpec   = gdmCreateSpecFromDDID(ddGetObj(fromLibName))
    toSpec     = gdmCreateSpecFromDDID(ddGetObj(toLibName))
    updateList = gdmCreateSpecList()
    gdmAddSpecToSpecList(
      gdmCreateSpecFromDDID(ddGetObj(updateLibName))
      updateList
    )

    
   if(ccpRenameReferenceLib(fromSpec toSpec updateList) then
        printf("Done : The references were renamed.\n")
   else
        printf("Error: The references were not renamed.\n")
;       return(nil)
   )
   return(t)
))


; change reference library script
; **INPUT**
; rules:        list(list(inLib fromLib toLib))
;
; **EXAMPLE**
; changeLibRef(list(list("libA" 'ALL "libA")))                                  ; in libA, change all libraries to libA
; changeLibRef(list(list("libA" "libB" "libA") list("libA" "libC" "libA")))     ; in libA, change libB and libC to libA
; changeLibRef(list(list("libA" "libB" "libA") list("libB" "libC" "libB")))     ; in libA, change libB to libA; in libB, change libC to libB
procedure(changeLibRef(rules)
prog((rule updateList spec inLib fromLib toLib)
    inLibTable = makeTable('inLibTable list())
    if(!boundp('rules) then
	printf("Error : CAT > no rules found\n")
	return(nil)
    )			
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
    return(t)
)) 

; revert ICM library after change reference library
; **INPUT**
; libName: STRING "libA"
;
; **EXAMPLE**
; changeLibRef_revertICM("libA" "managed")
; changeLibRef_revertICM("libA" "unmanaged")
;

procedure(Exec(cmd)
let((cid)
    cid=ipcBeginProcess(cmd
                        ""
                        lambda((c d) print("%s" d))
                        lambda((c d) print("%s" d)))
    ipcWaitForProcess(cid)
    while(ipcIsAliveProcess(cid) ipcSleep(1))
))



procedure(changeLibRef_revertICM(libName managed)
prog((libPath)
    unless(member(managed list("managed" "unmanaged"))
            warn("CAT > managed input only allow 'managed' or 'unmanaged'")
            return(nil)
    )

    libPath=ddGetObj(libName)->writePath
    oriPath = "/user/virtuoso.catdm/USERS/CAT_DM/paul_test/lib_MIX/"
    printf("CAT > libPath: %Y\noriPath: %Y\n" libPath oriPath)

    when(managed=="managed" Exec(strcat("xlp4 edit " libPath "/...")))
    Exec(strcat("/usr/bin/cp -rf " oriPath libName "/* " libPath))
    when(managed=="managed" Exec(strcat("xlp4 submit -d 'restore changeLibRef' " libPath "/...")))

    ddsHiRefresh()
))


procedure(renameRefLib_revertICM(libName managed)
prog((libPath oriPath)
    unless(member(managed list("managed" "unmanaged"))
        warn("managed input only allow 'managed' or 'unmanaged'")
        return(nil)
    )

    libPath=ddGetObj(libName)->writePath
    oriPath = "/user/virtuoso.catdm/USERS/CAT_DM/paul_test/lib_MIX/"
    printf("libPath: %Y\noriPath: %Y\n" libPath oriPath)

    when(managed=="managed" Exec(strcat("xlp4 edit " libPath "/...")))
    Exec(strcat("/usr/bin/cp -rf " oriPath libName "/* " libPath))
   ; when(managed=="managed" Exec(strcat("xlp4 submit -d 'restore changeRefLib' " libPath "/...")))
    when(managed=="managed" Exec(strcat("xlp4 submit -d 'restore renameRefLib' " libPath "/...")))

    ddsHiRefresh()
))
