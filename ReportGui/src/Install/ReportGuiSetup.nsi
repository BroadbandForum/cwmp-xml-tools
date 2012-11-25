# Auto-generated by EclipseNSIS Script Wizard
# 04.03.2010 15:01:19

Name ReportGui

# General Symbol Definitions
!define REGKEY "SOFTWARE\$(^Name)"
!define VERSION 2.3.0
!define COMPANY "Klaus.Wich, NSN"
!define URL ""

# MUI Symbol Definitions
!define MUI_ICON icons\Report-NSN.ico
!define MUI_FINISHPAGE_NOAUTOCLOSE
!define MUI_STARTMENUPAGE_REGISTRY_ROOT HKLM
!define MUI_STARTMENUPAGE_REGISTRY_KEY ${REGKEY}
!define MUI_STARTMENUPAGE_REGISTRY_VALUENAME StartMenuGroup
!define MUI_STARTMENUPAGE_DEFAULTFOLDER ReportGui
!define MUI_UNICON icons\Report-NSN-uninstall.ico
!define MUI_UNFINISHPAGE_NOAUTOCLOSE
!define MUI_FINISHPAGE_RUN $INSTDIR\ReportGui.exe
!define MUI_FINISHPAGE_RUN_NOTCHECKED

# Included files
!include Sections.nsh
!include MUI.nsh

# Variables
Var StartMenuGroup

# Installer pages
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE license.txt
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_STARTMENU Application $StartMenuGroup
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

# Installer languages
!insertmacro MUI_LANGUAGE English

# Installer attributes
OutFile ReportGuiSetup.exe
InstallDir $PROGRAMFILES\ReportGui
CRCCheck on
XPStyle on
ShowInstDetails show
VIProductVersion "${VERSION}.0"
VIAddVersionKey ProductName ReportGui
VIAddVersionKey ProductVersion "${VERSION}"
VIAddVersionKey CompanyName "Nokia Siemens Networks"
VIAddVersionKey Author "${COMPANY}"
VIAddVersionKey FileVersion "${VERSION}"
VIAddVersionKey FileDescription "ReportGUI and Report.exe installer"
VIAddVersionKey LegalCopyright "${COMPANY}"
InstallDirRegKey HKLM "${REGKEY}" Path
ShowUninstDetails show

# Installer sections
!macro CREATE_SMGROUP_SHORTCUT NAME PATH
    Push "${NAME}"
    Push "${PATH}"
    Call CreateSMGroupShortcut
!macroend

Section !ReportGui SEC0000
    SetOutPath $INSTDIR
    SetOverwrite ifnewer
    File ..\ReportGui.exe
    File ..\ReportUpdate.exe
    File ReportGui.ini
    File ..\ReportGuiHelp.ini
    !insertmacro CREATE_SMGROUP_SHORTCUT ReportGui $INSTDIR\ReportGui.exe
    SetOutPath $INSTDIR\plugins
    SetOverwrite ifnewer
    File ..\plugins\ostruct.pm
    File ..\plugins\nsn.pm
    WriteRegStr HKLM "${REGKEY}\Components" ReportGui 1
SectionEnd

Section "Report.exe Tool" SEC0001
    SetOutPath $INSTDIR
    SetOverwrite ifnewer
    File ..\..\ReportTool\report.exe
    WriteRegStr HKLM "${REGKEY}\Components" "Report.exe Tool" 1
    # Update REport.ini:
    
SectionEnd

Section "create Dektop Shortcut" SEC0002
    SetOutPath $INSTDIR
    CreateShortcut $DESKTOP\ReportGui.lnk $INSTDIR\ReportGui.exe
    WriteRegStr HKLM "${REGKEY}\Components" "create Dektop Shortcut" 1
SectionEnd

Section "create start menu shortcut" SEC0003
    SetOutPath $QUICKLAUNCH
    CreateShortcut "$QUICKLAUNCH\ReportGui.lnk" $INSTDIR\ReportGui.exe
    WriteRegStr HKLM "${REGKEY}\Components" "create start menu shortcut" 1
SectionEnd

Section -post SEC0004
    WriteRegStr HKLM "${REGKEY}" Path $INSTDIR
    SetOutPath $INSTDIR
    WriteUninstaller $INSTDIR\ReportGuiUninstall.exe
    !insertmacro MUI_STARTMENU_WRITE_BEGIN Application
    SetOutPath $SMPROGRAMS\$StartMenuGroup
    CreateShortcut "$SMPROGRAMS\$StartMenuGroup\Uninstall $(^Name).lnk" $INSTDIR\ReportGuiUninstall.exe
    !insertmacro MUI_STARTMENU_WRITE_END
    WriteRegStr HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$(^Name)" DisplayName "$(^Name)"
    WriteRegStr HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$(^Name)" DisplayVersion "${VERSION}"
    WriteRegStr HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$(^Name)" Publisher "${COMPANY}"
    WriteRegStr HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$(^Name)" DisplayIcon $INSTDIR\ReportGuiUninstall.exe
    WriteRegStr HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$(^Name)" UninstallString $INSTDIR\ReportGuiUninstall.exe
    WriteRegDWORD HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$(^Name)" NoModify 1
    WriteRegDWORD HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$(^Name)" NoRepair 1
SectionEnd

# Macro for selecting uninstaller sections
!macro SELECT_UNSECTION SECTION_NAME UNSECTION_ID
    Push $R0
    ReadRegStr $R0 HKLM "${REGKEY}\Components" "${SECTION_NAME}"
    StrCmp $R0 1 0 next${UNSECTION_ID}
    !insertmacro SelectSection "${UNSECTION_ID}"
    GoTo done${UNSECTION_ID}
next${UNSECTION_ID}:
    !insertmacro UnselectSection "${UNSECTION_ID}"
done${UNSECTION_ID}:
    Pop $R0
!macroend

# Uninstaller sections
!macro DELETE_SMGROUP_SHORTCUT NAME
    Push "${NAME}"
    Call un.DeleteSMGroupShortcut
!macroend

Section /o "-un.create start menu shortcut" UNSEC0003
    Delete /REBOOTOK "$QUICKLAUNCH\Quicklaunch Shortcut.lnk"
    DeleteRegValue HKLM "${REGKEY}\Components" "create start menu shortcut"
SectionEnd

Section /o "-un.create Dektop Shortcut" UNSEC0002
    Delete /REBOOTOK $DESKTOP\ReportGui.lnk
    DeleteRegValue HKLM "${REGKEY}\Components" "create Dektop Shortcut"
SectionEnd

Section /o "-un.Report.exe Tool" UNSEC0001
    Delete /REBOOTOK $INSTDIR\report.exe
    DeleteRegValue HKLM "${REGKEY}\Components" "Report.exe Tool"
SectionEnd

Section /o -un.ReportGui UNSEC0000
    !insertmacro DELETE_SMGROUP_SHORTCUT ReportGui
    Delete /REBOOTOK $INSTDIR\ReportGuiHelp.ini
    Delete /REBOOTOK $INSTDIR\ReportGui.ini
    Delete /REBOOTOK $INSTDIR\ReportGui.exe
    Delete /REBOOTOK $INSTDIR\ReportUpdate.exe
    DeleteRegValue HKLM "${REGKEY}\Components" ReportGui
SectionEnd

Section -un.post UNSEC0004
    DeleteRegKey HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$(^Name)"
    Delete /REBOOTOK "$SMPROGRAMS\$StartMenuGroup\Uninstall $(^Name).lnk"
    Delete /REBOOTOK $INSTDIR\ReportGuiUninstall.exe
    DeleteRegValue HKLM "${REGKEY}" StartMenuGroup
    DeleteRegValue HKLM "${REGKEY}" Path
    DeleteRegKey /IfEmpty HKLM "${REGKEY}\Components"
    DeleteRegKey /IfEmpty HKLM "${REGKEY}"
    RmDir /REBOOTOK $SMPROGRAMS\$StartMenuGroup
    RmDir /REBOOTOK $INSTDIR
    Push $R0
    StrCpy $R0 $StartMenuGroup 1
    StrCmp $R0 ">" no_smgroup
no_smgroup:
    Pop $R0
SectionEnd

# Installer functions
Function .onInit
    InitPluginsDir
FunctionEnd

Function CreateSMGroupShortcut
    Exch $R0 ;PATH
    Exch
    Exch $R1 ;NAME
    Push $R2
    StrCpy $R2 $StartMenuGroup 1
    StrCmp $R2 ">" no_smgroup
    SetOutPath $SMPROGRAMS\$StartMenuGroup
    CreateShortcut "$SMPROGRAMS\$StartMenuGroup\$R1.lnk" $R0
no_smgroup:
    Pop $R2
    Pop $R1
    Pop $R0
FunctionEnd

# Uninstaller functions
Function un.onInit
    ReadRegStr $INSTDIR HKLM "${REGKEY}" Path
    !insertmacro MUI_STARTMENU_GETFOLDER Application $StartMenuGroup
    !insertmacro SELECT_UNSECTION ReportGui ${UNSEC0000}
    !insertmacro SELECT_UNSECTION "Report.exe Tool" ${UNSEC0001}
    !insertmacro SELECT_UNSECTION "create Desktop Shortcut" ${UNSEC0002}
    !insertmacro SELECT_UNSECTION "create start menu shortcut" ${UNSEC0003}
FunctionEnd

Function un.DeleteSMGroupShortcut
    Exch $R1 ;NAME
    Push $R2
    StrCpy $R2 $StartMenuGroup 1
    StrCmp $R2 ">" no_smgroup
    Delete /REBOOTOK "$SMPROGRAMS\$StartMenuGroup\$R1.lnk"
no_smgroup:
    Pop $R2
    Pop $R1
FunctionEnd

# Section Descriptions
!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
!insertmacro MUI_DESCRIPTION_TEXT ${SEC0000} "Graphical User Interface for report.exe"
!insertmacro MUI_DESCRIPTION_TEXT ${SEC0001} "Report generation tool, provided by wLupton"
!insertmacro MUI_FUNCTION_DESCRIPTION_END