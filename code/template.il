\i ;; Change schematic and layout editor license ordering to always useNext
\i lbuiLicMgtForm->tabsField->page3->_lbuiOrderScrollReg->_lbuiOrderFamilyInfo->useNext_VSE="L:always"
\i lbuiLicMgtForm->tabsField->page3->_lbuiOrderScrollReg->_lbuiOrderFamilyInfo->useNext_VLS="XL:always"
\i lbuiLicMgtForm->tabsField->page3->_lbuiOrderScrollReg->_lbuiOrderFamilyInfo->useNext_VLS="GXL:always"
\i
\i code_path = "../../../code/"
\i result_path = "../../../result/"
\i load( strcat( code_path "validate.il" ))
\i load( strcat( code_path "virtuosoVer.il"))
\i load( strcat( code_path "mgHierParse.il"))
\i 
\i ;; create result folder and get test case number
\i unique_result_folder = strcat( result_path CDS_PV_REG_RES_NO)
\i system(strcat("mkdir -p " unique_result_folder  ))
\i user_name = getShellEnvVar("USER")
\i fd=outfile(strcat( unique_result_folder "/test_" CDS_PV_REGGRESION_NO "_" virtuosoVer() ".log") "w")
\i fprintf(fd strcat("Start Time: " getCurrentTime() "\n"))   
\i 
\i ;;; Test Scenario::Begin 
\i ;;; Test Scenario::End
\i  
\i fprintf(fd strcat("End Time: " getCurrentTime() "\n"))
\i close(fd)
\i exit()
\i geSaveAllForm->none->value= t
\i hiFormDone(geSaveAllForm)
