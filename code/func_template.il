\i ;; Change schematic and layout editor license ordering to always useNext
\i lbuiLicMgtForm->tabsField->page3->_lbuiOrderScrollReg->_lbuiOrderFamilyInfo->useNext_VSE="L:always"
\i lbuiLicMgtForm->tabsField->page3->_lbuiOrderScrollReg->_lbuiOrderFamilyInfo->useNext_VLS="XL:always"
\i lbuiLicMgtForm->tabsField->page3->_lbuiOrderScrollReg->_lbuiOrderFamilyInfo->useNext_VLS="GXL:always"
\i
\i code_path = "../../../code/"
\i result_path = "../../../result/"
\i load( strcat( code_path "validate.il" ))
\i load( strcat( code_path "virtuosoVer.il"))
\i load(strcat(code_path "sm_env.il"))
\i load(strcat(code_path "functions.il"))
\i envLoadFile(strcat(code_path ".cdsenv"))
\i mode = "default"
\i
\i ;; create result folder and get test case number
\i system(strcat("mkdir -p " result_path date_virtuosoVer(code_path) ))
\i user_name = getShellEnvVar("USER")
\i inport = infile("../uniqueid.txt")
\i gets(CDS_PV_REG_NO inport)
\i CDS_PV_REG_NO = substring(CDS_PV_REG_NO 1 strlen(CDS_PV_REG_NO)-1)
\i close(inport)
\i fd=outfile(strcat(result_path date_virtuosoVer(code_path) "/test_" CDS_PV_REG_NO "_" date_virtuosoVer(code_path) ".log") "w")
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
\i hiDBoxUser(ICM_intHierQuestion nil 2)
