#region ;**** Directives created by AutoIt3Wrapper_GUI ****
#AutoIt3Wrapper_Icon=Install\icons\Report-NSN.ico
#AutoIt3Wrapper_Outfile=ReportGui.exe
#AutoIt3Wrapper_Res_Description=Graphical user interface for report.exe
#AutoIt3Wrapper_Res_Fileversion=2.0.0.0
#AutoIt3Wrapper_Res_Fileversion_AutoIncrement=p
#AutoIt3Wrapper_Res_LegalCopyright=2012 Klaus Wich (klaus.wich@nsn.com)
#AutoIt3Wrapper_Res_Language=1033
#AutoIt3Wrapper_Res_requestedExecutionLevel=asInvoker
#AutoIt3Wrapper_Run_Tidy=y
#AutoIt3Wrapper_Run_Obfuscator=y
#Obfuscator_Parameters=/striponly
#endregion ;**** Directives created by AutoIt3Wrapper_GUI ****

#include <GUIConstantsEx.au3>
#include <EditConstants.au3>
#include <WindowsConstants.au3>
#include <IE.au3>
#include <GUIListBox.au3>
#include <Constants.au3>
#include <GuiEdit.au3>
#include <Array.au3>
#include <INet.au3>
;#include <GuiTab.au3>

Opt('MustDeclareVars', 1)
Opt('TrayIconHide', 1)
Opt("GUIResizeMode", 0)

Global $progversion = "2.2"
Global $progdate = "(2012/02/29)"
Global $progyear = "2012"
Global $progname = "ReportGui: BBF report.exe Frontend"
Global $iniFileName = "ReportGui.ini"
Global $iniFilePathName = @AppDataDir & "\ReportGui\" & $iniFileName
Global $gHelpIniFileName = "ReportGuiHelp.ini"

Global $gWebReportToolAddr = "https://tr69xmltool.iol.unh.edu/repos/cwmp-xml-tools"

; Global variables
Global $DGGCount = 0
Global $filename
Global $gOutFile
Global $filepath, $comppath, $g_Mainincludepath
Global $gFormatSelection = "|html|tab|text|xls|xml|xml2|xsd|null"
;$outext
Global $gRepToolPath, $repoptions, $ctrl_options, $ctrl_ignore, $ctrl_pattern, $ctrl_selbutton, $ctrl_showrepbutton, _
		$ctrl_filelabel, $ctrlLastOnly, $ctrl_filebutton, $ctrl_incbutton, $ctrl_incaddbutton, $ctrl_incdelbutton, $ctrl_incupbutton, _
		$ctrl_genbutton, $ctrl_helpbutton, $ctrl_loglist, $ctrl_formatselect, $ctrl_logbutton, $ctrl_showbutton, $ctrl_publishbutton, _
		$ctrl_ThisOnly, $ctrl_WriteOnly, $ctrl_ShowSyntax, $ctrl_NoProfiles, $ctrl_ShowDiffs, $cbShowDiff, _
		$ctrl_autobase, $ctrl_deletedeprecated, $ctrl_marktemplates, $ctrl_automodel, $ctrl_nocomments, $ctrl_nohyphenate, _
		$ctrl_nolinks, $ctrl_nomodels, $ctrl_notemplates, $ctrl_nowarnredef, $ctrl_showspec, _
		$ctrl_profilecombo, $lbl_profile, $btn_profile_add, $btn_profile_del, _
		$ctrl_ReadOnly, $ctrl_pedantic, $ctrl_allbibrefs, _
		$lbl_OtherOpt, $lbl_IgnPattern, $lbl_ObjPattern, $lbl_ActFile, $lbl_RepFormat, _
		$RepGrp, $ctrlRepHtml, $ctrlRepHtmlLast, $ctrlRepErrCheck, $ctrlRepHtmlFlat, $ctrlRepPublish, $ctrlRepCompare, $ctrlRepFullCompare, $ctrlCpmpLO
Global $mainWindow, $incWindow
Global $m_filemenu, $m_fileitem, $m_exititem, $m_settmenu, $m_OpenGen, $m_helpmenu, $m_incitem, $m_incdefitem, $m_repsett, $m_DelTmp, $m_ShowCmd, _
		$m_helpreport, $m_helpgui, $m_helpabout, $m_helpupdate, $m_helpxmlupdate, $m_helpfeedback, $m_helprestore, $m_AutoUpdate, $m_extramenu, $m_em_htmlload, _
		$m_extra_puball, $m_extra_check, $m_helpwiki, $m_OldNames, $m_log_combo, $m_ShowStats
Global $gToolTip, $tab, $tab0, $tab1, $cbRepPublishWar
; include functions
#include "ReportGuiGenerate.au3"

Main()


Func WM_GETMINMAXINFO($hWnd, $MsgID, $wParam, $lParam)
	If $hWnd = $mainWindow Then; the main GUI-limited
		Local $minmaxinfo = DllStructCreate("int;int;int;int;int;int;int;int;int;int", $lParam)
		DllStructSetData($minmaxinfo, 7, 580); min width
		DllStructSetData($minmaxinfo, 8, 500); min height
	EndIf
	Return 0
EndFunc   ;==>WM_GETMINMAXINFO


Func CreateWindow()
	Local $height = @DesktopHeight - 100
	If $height < 600 Then
		$height = 600
	ElseIf $height > 900 Then
		$height = 900
	EndIf
	$mainWindow = GUICreate($progname, 570, $height)
	GUIRegisterMsg($WM_GETMINMAXINFO, 'WM_GETMINMAXINFO')
	Local $line = 10
	Local $line2 = 10
	Local $col = 10
	Local $col2 = 100
	Local $col3 = 190
	Local $col4 = 300
	Local $col5 = 390
	Local $col6 = 480
	; menu
	$m_filemenu = GUICtrlCreateMenu("&File")
	$m_fileitem = mGUICreateMenueItem("Open", $m_filemenu)
	$m_exititem = mGUICreateMenueItem("Exit", $m_filemenu)

	$m_settmenu = GUICtrlCreateMenu("&Settings")
	$m_incdefitem = GUICtrlCreateMenuItem("Select default include directory", $m_settmenu)
	$m_incitem = GUICtrlCreateMenuItem("Set additional include dirs", $m_settmenu)
	$m_repsett = GUICtrlCreateMenuItem("Set report tool", $m_settmenu)

	; settings menu
	GUICtrlCreateMenuItem("", $m_settmenu)
	$m_OpenGen = GUICtrlCreateMenuItem("Open generated file", $m_settmenu)
	If IniRead($iniFilePathName, "Settings", "OpenGen", "False") = "True" Then
		GUICtrlSetState($m_OpenGen, $GUI_CHECKED)
	EndIf
	$m_DelTmp = GUICtrlCreateMenuItem("Delete temporary files", $m_settmenu)
	If IniRead($iniFilePathName, "Settings", "DelTmp", "False") = "True" Then
		GUICtrlSetState($m_DelTmp, $GUI_CHECKED)
	EndIf
	$m_ShowStats = GUICtrlCreateMenuItem("Show statistics", $m_settmenu)
	If IniRead($iniFilePathName, "Settings", "ShowStats", "True") = "True" Then
		GUICtrlSetState($m_ShowStats, $GUI_CHECKED)
	EndIf
	$m_ShowCmd = GUICtrlCreateMenuItem("Show command", $m_settmenu)
	If IniRead($iniFilePathName, "Settings", "ShowCmd", "False") = "True" Then
		GUICtrlSetState($m_ShowCmd, $GUI_CHECKED)
	EndIf
	$m_OldNames = GUICtrlCreateMenuItem("Use old xml names", $m_settmenu)
	If IniRead($iniFilePathName, "Settings", "OldNames", "False") = "True" Then
		GUICtrlSetState($m_OldNames, $GUI_CHECKED)
	EndIf
	;$m_AutoUpdate = GUICtrlCreateMenuItem("Automatic update check", $m_settmenu)
	;If IniRead($iniFilePathName, "Settings", "AutoUpdate", "True") = "True" Then
	;	GUICtrlSetState($m_AutoUpdate, $GUI_CHECKED)
	;EndIf

	; extra menu
	$m_extramenu = GUICtrlCreateMenu("&Extras")
	$m_extra_puball = GUICtrlCreateMenuItem("Publish all files in directory", $m_extramenu)
	$m_helpxmlupdate = GUICtrlCreateMenuItem("Download BBF published XML files", $m_extramenu)
	GUICtrlCreateMenuItem("", $m_extramenu)
	$m_extra_check = GUICtrlCreateMenuItem("Check for new files on BBF homepage", $m_extramenu)
	GUICtrlCreateMenuItem("", $m_extramenu)
	$m_em_htmlload = GUICtrlCreateMenuItem("Include html files in BBF XML download", $m_extramenu)
	If IniRead($iniFilePathName, "Settings", "HtmlLoad", "False") = "True" Then
		GUICtrlSetState($m_em_htmlload, $GUI_CHECKED)
	EndIf

	; help menu
	$m_helpmenu = GUICtrlCreateMenu("&Help")
	$m_helpgui = mGUICreateMenueItem("GUI help", $m_helpmenu)
	$m_helpreport = mGUICreateMenueItem("Report help", $m_helpmenu)
	$m_helpwiki = GUICtrlCreateMenuItem("Goto Wiki page", $m_helpmenu)
	GUICtrlCreateMenuItem("", $m_helpmenu)
	$m_helpupdate = GUICtrlCreateMenuItem("Check for updates", $m_helpmenu)
	$m_helprestore = GUICtrlCreateMenuItem("Restore report.exe from backup", $m_helpmenu)
	GUICtrlCreateMenuItem("", $m_helpmenu)
	$m_helpfeedback = GUICtrlCreateMenuItem("Send feedback", $m_helpmenu)
	GUICtrlCreateMenuItem("", $m_helpmenu)
	$m_helpabout = GUICtrlCreateMenuItem("About", $m_helpmenu)

	; input menu
	GUICtrlCreateGroup("Input file:", $col - 5, $line, 560, 45)
	GUICtrlSetResizing(-1, $GUI_DOCKLEFT + $GUI_DOCKTOP + $GUI_DOCKHEIGHT)
	$ctrl_filelabel = GUICtrlCreateLabel(GetFileName($filename), $col + 50, $line + 18, 370, 15)
	GUICtrlSetResizing(-1, $GUI_DOCKLEFT + $GUI_DOCKTOP + $GUI_DOCKHEIGHT)
	GUICtrlSetFont($ctrl_filelabel, 11, 100)
	GUICtrlSetBkColor($ctrl_filelabel, 0xf0f090)
	setToolTip($ctrl_filelabel, "Input file")
	$ctrl_selbutton = GUICtrlCreateButton("Select", $col + 445, $line + 13, 50)
	GUICtrlSetResizing(-1, $GUI_DOCKRIGHT + $GUI_DOCKTOP + $GUI_DOCKHEIGHT + $GUI_DOCKWIDTH)
	setToolTip($ctrl_showbutton, "Select")
	$ctrl_showbutton = GUICtrlCreateButton("Show", $col + 495, $line + 13, 50)
	GUICtrlSetResizing(-1, $GUI_DOCKRIGHT + $GUI_DOCKTOP + $GUI_DOCKHEIGHT + $GUI_DOCKWIDTH)
	setToolTip($ctrl_showbutton, "Show")

	$line += 50

	Local $tabNo = IniRead($iniFilePathName, "Settings", "Tab", 0)
	;
	; Basic tab
	;
	$tab = GUICtrlCreateTab(2, $line, 596, 20)
	GUICtrlSetResizing(-1, $GUI_DOCKLEFT + $GUI_DOCKTOP + $GUI_DOCKHEIGHT)
	$tab0 = GUICtrlCreateTabItem("Standard Report function")
	GUICtrlSetResizing(-1, $GUI_DOCKLEFT + $GUI_DOCKTOP + $GUI_DOCKHEIGHT)
	If $tabNo = 0 Then
		GUICtrlSetState($tab0, $GUI_SHOW);
	EndIf

	$line += 30
	$RepGrp = GUICtrlCreateGroup("Select report(s) to be generated:", $col - 5, $line, 560, 200)
	GUICtrlSetResizing(-1, $GUI_DOCKLEFT + $GUI_DOCKTOP + $GUI_DOCKHEIGHT)

	Local $rad = IniRead($iniFilePathName, "Settings", "BasRad", 0)
	$ctrlRepHtml = mGUICreateRadioBtn("HTML Report", $col2, $line + 20, 0)
	$ctrlRepHtmlLast = mGUICreateRadioBtn("HTML Report (latest only)", $col2, $line + 40, 0)
	$cbShowDiff = mGUICreateSetCheckbox("(Show Diffs)", $col4 - 20, $line + 30)
	$ctrlRepCompare = mGUICreateRadioBtn("Compare against ...", $col2, $line + 65, 0)
	$ctrlCpmpLO = mGUICreateSetCheckbox("(latest changes only)", $col4 - 20, $line + 65)
	$ctrlRepFullCompare = mGUICreateRadioBtn("Full compare against ...", $col2, $line + 85, 0)
	$ctrlRepErrCheck = mGUICreateRadioBtn("Error checking", $col2, $line + 110, 0)
	$ctrlRepHtmlFlat = mGUICreateRadioBtn("'flattened' XML file", $col2, $line + 130, 0)
	$ctrlRepPublish = mGUICreateRadioBtn("Publish xml ", $col2, $line + 155, 0)
	$cbRepPublishWar = mGUICreateSetCheckbox("(without warnings)", $col4 - 20, $line + 155)
	Switch IniRead($iniFilePathName, "Settings", "BasRad", 0)
		Case 0
			GUICtrlSetState($ctrlRepHtml, $GUI_CHECKED)
		Case 1
			GUICtrlSetState($ctrlRepHtmlLast, $GUI_CHECKED)
		Case 2
			GUICtrlSetState($ctrlRepErrCheck, $GUI_CHECKED)
		Case 3
			GUICtrlSetState($ctrlRepHtmlFlat, $GUI_CHECKED)
		Case 4
			GUICtrlSetState($ctrlRepPublish, $GUI_CHECKED)
		Case 5
			GUICtrlSetState($ctrlRepCompare, $GUI_CHECKED)
		Case 6
			GUICtrlSetState($ctrlRepFullCompare, $GUI_CHECKED)
	EndSwitch


	;
	; Expert tab
	;
	$tab1 = GUICtrlCreateTabItem("Expert Report functions")
	GUICtrlSetResizing(-1, $GUI_DOCKLEFT + $GUI_DOCKTOP + $GUI_DOCKHEIGHT + $GUI_DOCKWIDTH)
	If $tabNo = 1 Then
		GUICtrlSetState($tab1, $GUI_SHOW);
	EndIf
	$line2 = $line
	GUICtrlCreateGroup("Profile:", $col4 - 5, $line, 270, 45)
	GUICtrlSetResizing(-1, $GUI_DOCKLEFT + $GUI_DOCKTOP + $GUI_DOCKHEIGHT + $GUI_DOCKWIDTH)
	$ctrl_profilecombo = GUICtrlCreateCombo("default", $col4, $line + 15, 175)
	GUICtrlSetResizing(-1, $GUI_DOCKLEFT + $GUI_DOCKTOP + $GUI_DOCKHEIGHT + $GUI_DOCKWIDTH)
	setToolTip($ctrl_profilecombo, "Profiles")
	$btn_profile_add = GUICtrlCreateButton("Save", $col4 + 180, $line + 13, 35)
	GUICtrlSetResizing(-1, $GUI_DOCKLEFT + $GUI_DOCKTOP + $GUI_DOCKHEIGHT + $GUI_DOCKWIDTH)
	setToolTip($btn_profile_add, "Save profile")
	$btn_profile_del = GUICtrlCreateButton("Del", $col4 + 220, $line + 13, 35)
	GUICtrlSetResizing(-1, $GUI_DOCKLEFT + $GUI_DOCKTOP + $GUI_DOCKHEIGHT + $GUI_DOCKWIDTH)
	setToolTip($btn_profile_del, "Delete profile")
	UpdateProfileComboBox("default")

	GUICtrlCreateGroup("Include options:", $col - 5, $line, $col4 - 20, 115)
	GUICtrlSetResizing(-1, $GUI_DOCKLEFT + $GUI_DOCKTOP + $GUI_DOCKHEIGHT + $GUI_DOCKWIDTH)
	$line += 15
	;Input Options
	$ctrlLastOnly = mGUICreateSetCheckbox("LastOnly", $col, $line)
	$ctrl_ThisOnly = mGUICreateSetCheckbox("ThisOnly", $col2, $line)
	$ctrl_WriteOnly = mGUICreateSetCheckbox("WriteOnly", $col3, $line)
	$line += 20
	$ctrl_NoProfiles = mGUICreateSetCheckbox("NoProfiles", $col, $line)
	$ctrl_notemplates = mGUICreateSetCheckbox("notemplates", $col2, $line)
	$ctrl_ReadOnly = mGUICreateSetCheckbox("ReadOnly", $col3, $line)

	$line += 25
	mGUICreateLabel("Object pattern", $col, $line + 2)
	$ctrl_pattern = GUICtrlCreateEdit("", $col2, $line, 180, -1, $ES_WANTRETURN)
	GUICtrlSetResizing(-1, $GUI_DOCKLEFT + $GUI_DOCKTOP + $GUI_DOCKHEIGHT + $GUI_DOCKWIDTH)
	setToolTip($ctrl_pattern, "Object pattern")
	$line += 25
	mGUICreateLabel("Ignore pattern", $col, $line + 2)
	$ctrl_ignore = GUICtrlCreateEdit("", $col2, $line, 180, -1, $ES_WANTRETURN)
	GUICtrlSetResizing(-1, $GUI_DOCKLEFT + $GUI_DOCKTOP + $GUI_DOCKHEIGHT + $GUI_DOCKWIDTH)
	setToolTip($ctrl_ignore, "Ignore pattern")

	$line += 35
	GUICtrlCreateGroup("Output options:", $col - 5, $line, $col4 - 20, 85)
	GUICtrlSetResizing(-1, $GUI_DOCKLEFT + $GUI_DOCKTOP + $GUI_DOCKHEIGHT + $GUI_DOCKWIDTH)
	$line += 15
	mGUICreateLabel("Report format", $col, $line + 2)
	$ctrl_formatselect = GUICtrlCreateCombo("", $col2, $line) ; create first item
	GUICtrlSetResizing(-1, $GUI_DOCKLEFT + $GUI_DOCKTOP + $GUI_DOCKHEIGHT + $GUI_DOCKWIDTH)
	setToolTip($ctrl_formatselect, "Report format")
	GUICtrlSetData($ctrl_formatselect, $gFormatSelection, "html")

	$ctrl_ShowDiffs = mGUICreateSetCheckbox("showdiffs", $col3, $line)

	$line += 22
	$ctrl_ShowSyntax = mGUICreateSetCheckbox("showsyntax", $col, $line)
	$ctrl_nolinks = mGUICreateSetCheckbox("nolinks", $col2, $line)
	$ctrl_showspec = mGUICreateSetCheckbox("showspec", $col3, $line)
	$line += 20
	$ctrl_nocomments = mGUICreateSetCheckbox("nocomments", $col, $line)
	$ctrl_nohyphenate = mGUICreateSetCheckbox("nohyphenate", $col2, $line)
	$ctrl_nomodels = mGUICreateSetCheckbox("nomodels", $col3, $line)

	;Other Options
	$line2 += 50
	GUICtrlCreateGroup("Additonal options", $col4 - 5, $line2, 270, 155)
	GUICtrlSetResizing(-1, $GUI_DOCKLEFT + $GUI_DOCKTOP + $GUI_DOCKHEIGHT + $GUI_DOCKWIDTH)
	$line2 += 15
	$ctrl_automodel = mGUICreateSetCheckbox("automodel", $col4, $line2)
	$ctrl_marktemplates = mGUICreateSetCheckbox("marktemplates", $col5, $line2)
	$ctrl_autobase = mGUICreateSetCheckbox("autobase", $col6, $line2)

	$line2 += 20
	$ctrl_nowarnredef = mGUICreateSetCheckbox("nowarnredef", $col4, $line2)
	$ctrl_deletedeprecated = mGUICreateSetCheckbox("deletedeprecated", $col5, $line2)
	;new v1.1
	$line2 += 20
	$ctrl_pedantic = mGUICreateSetCheckbox("pedantic", $col4, $line2)
	$ctrl_allbibrefs = mGUICreateSetCheckbox("allbibrefs", $col5, $line2)
	$line2 += 25
	mGUICreateLabel("Other options", $col4, $line2 + 2)
	$line2 += 20
	$ctrl_options = GUICtrlCreateEdit("", $col4, $line2, 260, -1, $ES_WANTRETURN)
	GUICtrlSetResizing(-1, $GUI_DOCKLEFT + $GUI_DOCKTOP + $GUI_DOCKHEIGHT + $GUI_DOCKWIDTH)
	setToolTip($ctrl_options, "Other options")


	GUICtrlCreateTabItem("") ; end tabitem definition
	;IniRead($iniFilePathName, "Settings", "Tab", 0)

	$line += 40
	; create loglevel selector
	mGUICreateLabel("Log level", $col - 5, $line + 5)
	GUICtrlSetResizing(-1, $GUI_DOCKLEFT + $GUI_DOCKTOP + $GUI_DOCKHEIGHT + $GUI_DOCKWIDTH)
	$m_log_combo = GUICtrlCreateCombo("", $col + 45, $line + 2, 70, -1, -1)
	GUICtrlSetResizing(-1, $GUI_DOCKLEFT + $GUI_DOCKTOP + $GUI_DOCKHEIGHT + $GUI_DOCKWIDTH)
	setToolTip($m_log_combo, "Log level")
	Local $d = getLongLogLevel(IniRead($iniFilePathName, "Settings", "Loglevel", "w1"))
	GUICtrlSetData($m_log_combo, "|error|info|warning-0|warning-1|warning-2|warning-3|debug-0|debug-1|debug-2|debug-3", $d)
	; create buttons:
	$ctrl_genbutton = GUICtrlCreateButton("Generate Report", $col2 + 40, $line - 10, 240, 40)
	GUICtrlSetResizing(-1, $GUI_DOCKTOP + $GUI_DOCKHEIGHT)
	setToolTip($ctrl_genbutton, "Generate Report")
	$ctrl_showrepbutton = mGUICreateButton("Show Report", $col4 + 90, $line, 80)
	GUICtrlSetResizing(-1, $GUI_DOCKRIGHT + $GUI_DOCKTOP + $GUI_DOCKHEIGHT + $GUI_DOCKWIDTH)
	$ctrl_logbutton = mGUICreateButton("Save Log", $col5 + 80, $line, 90)
	GUICtrlSetResizing(-1, $GUI_DOCKRIGHT + $GUI_DOCKTOP + $GUI_DOCKHEIGHT + $GUI_DOCKWIDTH)

	$line += 35
	$ctrl_loglist = GUICtrlCreateEdit("", 0, $line, 570, $height - $line - 20, BitOR($ES_READONLY, $ES_AUTOVSCROLL, $WS_VScroll))
	GUICtrlSetResizing(-1, $GUI_DOCKBORDERS)
	GUICtrlSetBkColor($ctrl_loglist, 0xd0f0f0)
	GUISetStyle(BitOR($WS_MINIMIZEBOX, $WS_CAPTION, $WS_SIZEBOX, $WS_SYSMENU), 0)

	UpdateProfileComboBox("default")
	SetNewProfile()

	GUISetState(@SW_SHOW)
EndFunc   ;==>CreateWindow


; ---- Main Program ---------------------------------------
Func Main()
	GetInitValues()
	CreateWindow()
	CheckInitValues()
	CheckEnv()
	CheckMainInclude()
	While 1
		Local $msg = GUIGetMsg(1)

		Select
			Case $msg[0] = $m_fileitem
				OpenFile()
			Case $msg[0] = $m_helpreport
				PrintHelpReport()
			Case $msg[0] = $m_helpgui
				PrintHelpGui()
			Case $msg[0] = $m_helpabout
				PrintHelpAbout()
			Case $msg[0] = $m_helpfeedback
				SendFeedback()
			Case $msg[0] = $m_helprestore
				DeleteLog()
				RestoreReportExe()
			Case $msg[0] = $m_helpupdate
				DeleteLog()
				CheckForUpdates()
			Case $msg[0] = $m_helpxmlupdate
				DeleteLog()
				DownloadallBBFXML()
			Case $msg[0] = $m_extra_puball
				PublishEverything()
			Case $msg[0] = $m_extra_check
				DeleteLog()
				CheckForNewBBFXML()
			Case $msg[0] = $ctrl_genbutton
				GUICtrlSetState($ctrl_genbutton, $GUI_DISABLE)
				DeleteLog()
				CheckMainInclude()
				If GUICtrlRead($tab) = 1 Then
					GenReport(CreateCommand(), True, False)
				Else
					If GUICtrlRead($ctrlRepPublish) = $GUI_CHECKED Then
						DeleteLog()
						Publish($filename, $filepath, True, False)
					ElseIf GUICtrlRead($ctrlRepCompare) = $GUI_CHECKED Then
						Compare(False)
					ElseIf GUICtrlRead($ctrlRepFullCompare) = $GUI_CHECKED Then
						Compare(True)
					Else
						GenReport(BasicCommand(), True, False)
					EndIf
				EndIf
				GUICtrlSetState($ctrl_genbutton, $GUI_ENABLE)
				PrintLog("... done!")
			Case $msg[0] = $ctrl_showbutton
				ShellExecute(FileGetShortName($filename))
			Case $msg[0] = $ctrl_showrepbutton
				ShowReport()
			Case $msg[0] = $ctrl_selbutton
				OpenFile()
			Case $msg[0] = $ctrl_logbutton
				SaveLog2File()
				; settings menu commands
			Case $msg[0] = $m_incitem
				setIncludeDir()
			Case $msg[0] = $m_log_combo
				IniWrite($iniFilePathName, "Settings", "Loglevel", getShortLogLevel(GUICtrlRead($m_log_combo)))
			Case $msg[0] = $m_incdefitem
				selectDefaultIncludeDir()
			Case $msg[0] = $m_repsett
				setReportTool()
			Case $msg[0] = $m_OpenGen
				If BitAND(GUICtrlRead($m_OpenGen), $GUI_CHECKED) = $GUI_CHECKED Then
					GUICtrlSetState($m_OpenGen, $GUI_UNCHECKED)
				Else
					GUICtrlSetState($m_OpenGen, $GUI_CHECKED)
				EndIf
			Case $msg[0] = $m_DelTmp
				If BitAND(GUICtrlRead($m_DelTmp), $GUI_CHECKED) = $GUI_CHECKED Then
					GUICtrlSetState($m_DelTmp, $GUI_UNCHECKED)
				Else
					GUICtrlSetState($m_DelTmp, $GUI_CHECKED)
				EndIf
			Case $msg[0] = $m_ShowStats
				If BitAND(GUICtrlRead($m_ShowStats), $GUI_CHECKED) = $GUI_CHECKED Then
					GUICtrlSetState($m_ShowStats, $GUI_UNCHECKED)
				Else
					GUICtrlSetState($m_ShowStats, $GUI_CHECKED)
				EndIf
			Case $msg[0] = $m_ShowCmd
				If BitAND(GUICtrlRead($m_ShowCmd), $GUI_CHECKED) = $GUI_CHECKED Then
					GUICtrlSetState($m_ShowCmd, $GUI_UNCHECKED)
				Else
					GUICtrlSetState($m_ShowCmd, $GUI_CHECKED)
				EndIf
			Case $msg[0] = $m_OldNames
				If BitAND(GUICtrlRead($m_OldNames), $GUI_CHECKED) = $GUI_CHECKED Then
					GUICtrlSetState($m_OldNames, $GUI_UNCHECKED)
				Else
					GUICtrlSetState($m_OldNames, $GUI_CHECKED)
				EndIf
				;Case $msg[0] = $m_AutoUpdate
				;	If BitAND(GUICtrlRead($m_AutoUpdate), $GUI_CHECKED) = $GUI_CHECKED Then
				;		GUICtrlSetState($m_AutoUpdate, $GUI_UNCHECKED)
				;	Else
				;		GUICtrlSetState($m_AutoUpdate, $GUI_CHECKED)
				;	EndIf
			Case $msg[0] = $m_em_htmlload
				If BitAND(GUICtrlRead($m_em_htmlload), $GUI_CHECKED) = $GUI_CHECKED Then
					GUICtrlSetState($m_em_htmlload, $GUI_UNCHECKED)
				Else
					GUICtrlSetState($m_em_htmlload, $GUI_CHECKED)
				EndIf
			Case $msg[0] = $btn_profile_add
				AddProfile()
			Case $msg[0] = $btn_profile_del
				DelProfile()
			Case $msg[0] = $ctrl_profilecombo
				SetNewProfile()
			Case $msg[0] = $m_exititem
				ExitLoop
			Case $msg[0] = $GUI_EVENT_CLOSE
				If ($msg[1] = $mainWindow) Then
					ExitLoop
				EndIf
			Case $msg[0] = $m_helpwiki
				ShellExecute("https://tr69xmltool.iol.unh.edu/wiki/ReportGUI")
				;Case $msg[0] = $GUI_EVENT_RESIZED
				;DebugLog("Resize")
		EndSelect
	WEnd;
	SaveInitValues()
EndFunc   ;==>Main
