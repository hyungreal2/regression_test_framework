\i ;; Change schematic and layout editor license ordering to always useNext
\i lbuiLicMgtForm->tabsField->page3->_lbuiOrderScrollReg->_lbuiOrderFamilyInfo->useNext_VSE="L:always"
\i lbuiLicMgtForm->tabsField->page3->_lbuiOrderScrollReg->_lbuiOrderFamilyInfo->useNext_VLS="XL:always"
\i lbuiLicMgtForm->tabsField->page3->_lbuiOrderScrollReg->_lbuiOrderFamilyInfo->useNext_VLS="GXL:always"
\i
\i code_path = "../../../../code/"
\i result_path = "../../../../result/"
\i load(strcat(code_path "validate.il" ))
\i load(strcat(code_path "date_virtuosoVer.il"))
\i load(strcat(code_path "sm_env.il"))
\i load(strcat(code_path "functions.il"))
\i envLoadFile(strcat(code_path ".cdsenv"))
\i mode = "default"
\i user_name = getShellEnvVar("USER")
\i expValue = 0

\i ;; Get dateno from main
\i inport = infile(strcat("../../../../temp/func_date_" user_name "_" mode))
\i gets(main_date inport)
\i main_date = substring(main_date 1 strlen(main_date)-1)
\i close(inport)

\i ;; Create result folder 
\i system(strcat("mkdir -p " result_path mode "/" main_date ))

\i ;; Get test case number
\i inport = infile(strcat("../../../../temp/CDS_PV_REG_NO_" user_name "_" mode))
\i gets(CDS_PV_REG_NO inport)
\i CDS_PV_REG_NO = substring(CDS_PV_REG_NO 1 strlen(CDS_PV_REG_NO)-1)
\i close(inport)

\i ;; Get outfile
\i fd=outfile(strcat(result_path mode "/" main_date "/test_" CDS_PV_REG_NO "_" date_virtuosoVer(code_path mode) ".log") "w")
\i fprintf(fd strcat("Start Time: " getCurrentTime() "\n"))  


\i ;;; Test Scenario::Begin
\i ;;; Test Scenario::End
\i 
\i fprintf(fd strcat("\nEnd Time: " getCurrentTime() "\n"))
\i close(fd)
\i exit()
\i geSaveAllForm->none->value= t
\i hiFormDone(geSaveAllForm)
