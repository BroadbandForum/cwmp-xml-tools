;;; ReportGuiHelp.AU3 ;;;
; Klaus.wich@nsn.com
#include-once

Func AddProfile()
	;MsgBox features: Title=Yes, Text=Yes, Buttons=Yes and No, Icon=None
	Local $profilename = GUICtrlRead($ctrl_profilecombo)
	;If $profilename <> "default" Then
	If Not IsDeclared("iMsgBoxAnswer") Then Local $iMsgBoxAnswer
	If MsgBox(8196, "Save profile", "Save current settings as profile: """ & $profilename & """ ?") = 6 Then
		SaveProfile($profilename)
		UpdateProfileComboBox($profilename)
	EndIf
	;EndIf
EndFunc   ;==>AddProfile


Func DelProfile()
	Local $profilename = GUICtrlRead($ctrl_profilecombo)
	If $profilename <> "default" Then
		If Not IsDeclared("iMsgBoxDel") Then Local $iMsgBoxDel
		If MsgBox(1, "Delete confirmation", "Delete current profile: " & @CRLF & $profilename) = 1 Then
			IniDelete($iniFilePathName, "Profiles", $profilename)
			UpdateProfileComboBox("default")
		EndIf
	EndIf
EndFunc   ;==>DelProfile


Func UpdateProfileComboBox($entry)
	Local $k, $guidata ; = "default"
	Local $var = IniReadSection($iniFilePathName, "Profiles")
	If Not @error Then
		_ArraySort($var, 0, 0, 0, 0)
		$guidata = $var[1][0]
		For $k = 2 To $var[0][0]
			$guidata &= "|" & $var[$k][0]
		Next
	Else
		$guidata = "default"
	EndIf
	GUICtrlSetData($ctrl_profilecombo, "")
	GUICtrlSetData($ctrl_profilecombo, $guidata, $entry)
EndFunc   ;==>UpdateProfileComboBox


Func SaveProfile($profilename)
	Local $profile = GUICtrlRead($ctrl_formatselect) & ";" & _
			GUICtrlRead($ctrl_options) & ";" & _
			GUICtrlRead($ctrl_ignore) & ";" & _
			GUICtrlRead($ctrl_pattern) & ";" & _
			GUICtrlRead($ctrl_ThisOnly) & ";" & _
			GUICtrlRead($ctrl_WriteOnly) & ";" & _
			GUICtrlRead($ctrl_ShowSyntax) & ";" & _
			GUICtrlRead($ctrl_NoProfiles) & ";" & _
			GUICtrlRead($ctrlLastOnly) & ";" & _
			GUICtrlRead($ctrl_autobase) & ";" & _
			GUICtrlRead($ctrl_deletedeprecated) & ";" & _
			GUICtrlRead($ctrl_marktemplates) & ";" & _
			GUICtrlRead($ctrl_automodel) & ";" & _
			GUICtrlRead($ctrl_nocomments) & ";" & _
			GUICtrlRead($ctrl_nohyphenate) & ";" & _
			GUICtrlRead($ctrl_nolinks) & ";" & _
			GUICtrlRead($ctrl_nomodels) & ";" & _
			GUICtrlRead($ctrl_notemplates) & ";" & _
			GUICtrlRead($ctrl_nowarnredef) & ";" & _
			GUICtrlRead($ctrl_showspec) & ";" & _
			GUICtrlRead($ctrl_ReadOnly) & ";" & _
			GUICtrlRead($ctrl_pedantic) & ";" & _
			GUICtrlRead($ctrl_allbibrefs) & ";" & _
			GUICtrlRead($ctrl_ShowDiffs)
	IniWrite($iniFilePathName, "Profiles", $profilename, $profile)
EndFunc   ;==>SaveProfile


Func SetNewProfile()
	Local $profilename = GUICtrlRead($ctrl_profilecombo)
	If $profilename <> "" Then
		EvaluateProfileString(IniRead($iniFilePathName, "Profiles", $profilename, "default"))
	EndIf
EndFunc   ;==>SetNewProfile


Func EvaluateProfileString($profile)
	Local $val = StringSplit($profile, ";")
	Local $k = 0
	If ($val[0] >= 23) and ($val[0] < 25) Then
		GUICtrlSetData($ctrl_formatselect, $gFormatSelection, $val[1])
		GUICtrlSetData($ctrl_options, $val[2])
		GUICtrlSetData($ctrl_ignore, $val[3])
		GUICtrlSetData($ctrl_pattern, $val[4])
		GUICtrlSetState($ctrl_ThisOnly, $val[5])
		GUICtrlSetState($ctrl_WriteOnly, $val[6])
		GUICtrlSetState($ctrl_ShowSyntax, $val[7])
		GUICtrlSetState($ctrl_NoProfiles, $val[8])
		GUICtrlSetState($ctrlLastOnly, $val[9])
		GUICtrlSetState($ctrl_autobase, $val[10])
		GUICtrlSetState($ctrl_deletedeprecated, $val[11])
		GUICtrlSetState($ctrl_marktemplates, $val[12])
		GUICtrlSetState($ctrl_automodel, $val[13])
		GUICtrlSetState($ctrl_nocomments, $val[14])
		GUICtrlSetState($ctrl_nohyphenate, $val[15])
		GUICtrlSetState($ctrl_nolinks, $val[16])
		GUICtrlSetState($ctrl_nomodels, $val[17])
		GUICtrlSetState($ctrl_notemplates, $val[18])
		GUICtrlSetState($ctrl_nowarnredef, $val[19])
		GUICtrlSetState($ctrl_showspec, $val[20])
		GUICtrlSetState($ctrl_ReadOnly, $val[21])
		GUICtrlSetState($ctrl_pedantic, $val[22])
		GUICtrlSetState($ctrl_allbibrefs, $val[23])
		If $val[0] = 24 Then
			GUICtrlSetState($ctrl_ShowDiffs, $val[24])
		EndIf
	Else
		PrintLog("Profile Error: Profile " & $profile & " is invalid, please delete and recreate it!")
		PrintLog($val[0] & " entries")
		For $k = 1 To $val[0]
			PrintLog("entry " & $k & " : " & $val[$k])
		Next
	EndIf
EndFunc   ;==>EvaluateProfileString


func getYesNo($par)
	If (BitAND(GUICtrlRead($par), $GUI_CHECKED) = $GUI_CHECKED) Then
		Return("Yes")
	Else
		Return("No")
	EndIf
EndFunc


Func PrintHelpAbout()
	DeleteLog()
	PrintLog(@CRLF & @CRLF & _
			@TAB & @TAB & @TAB  & $progname & @CRLF & @CRLF & _
			@TAB & @TAB & @TAB & @TAB & " Version: " & $progversion & @CRLF & _
			@TAB & @TAB & @TAB & @TAB & $progdate & @CRLF & @CRLF)
	PrintLog( _
			@TAB & @TAB & "    Copyright: Klaus Wich, Nokia Siemens Networks, " & $progyear & @CRLF & _
			@TAB & @TAB & @TAB & "     (Contact: klaus.wich@nsn.com)" & @CRLF & @CRLF & @CRLF  & _
			@TAB & "==================================================================" & @CRLF & @CRLF & _
			@TAB &" Used Settings:" & @CRLF & @CRLF & _
			@TAB &"  - Default include directory:      " & @CRLF & @TAB&@TAB & $g_Mainincludepath & @CRLF & _
			@TAB &"  - Additional include directories: ")
	For $k = 1 To IniRead($iniFilePathName, "Includes", "IncNo", 0)
		PrintLog(@TAB &@TAB & IniRead($iniFilePathName, "Includes", $k, ""))
	Next
	PrintLog(@TAB &"  - Report Tool:" & @CRLF & @TAB& @TAB & $gRepToolPath)
	PrintLog(@TAB &"  - Init File:" & @CRLF & @TAB& @TAB & $iniFilePathName)
	PrintLog(@CRLF &@TAB &"  - log level:" & @TAB & @TAB& @TAB & getLongLogLevel(IniRead($iniFilePathName, "Settings", "Loglevel", "unknown")))
	PrintLog(@TAB &"  - Open generated file :  " & @TAB& @TAB & getYesNo($m_OpenGen))
	PrintLog(@TAB &"  - Delete temporary file(s) :  "& @TAB & @TAB & getYesNo($m_DelTmp))
	;PrintLog(@TAB &"  - Show statistics :  " & @TAB& @TAB & @TAB & getYesNo($m_ShowStats))
	PrintLog(@TAB &"  - Show command :  " &  @TAB & @TAB & getYesNo($m_ShowCmd))
	PrintLog(@TAB &"  - Use old xml naming convention :  " &  @TAB & getYesNo($m_OldNames))
	PrintLog(@TAB &"  - Include HTML in download :  " & @TAB & getYesNo($m_em_htmlload))
EndFunc   ;==>PrintHelpAbout


Func GetReportExeVersion()
	Local $cmd = @ComSpec & " /c " & FileGetShortName($gRepToolPath) & " --info"
	Local $val = Run($cmd, $filepath, @SW_HIDE, $STDERR_CHILD + $STDOUT_CHILD)
	Local $line
	While 1
		$line = StderrRead($val)
		If @error Then ExitLoop
		If StringLen($line) > 0 Then
			ExitLoop
		Else
			Sleep(200)
			PrintLogCont(".")
		EndIf
	WEnd
	Local $a = StringRegExp($line, "report.pl\#([0-9]*)", 1)
	Return $a[0]
EndFunc   ;==>GetReportExeVersion


Func PrintHelpReport()
	DeleteLog()
	PrintLog("Help information from Report.exe:" & @CRLF & _
			"-----------------------------------------------------------------------------")
	Local $cmd = @ComSpec & " /c " & FileGetShortName($gRepToolPath) & " --info"
	Local $val = Run($cmd, $filepath, @SW_HIDE, $STDERR_CHILD + $STDOUT_CHILD)
	Local $line

	While 1
		$line = StderrRead($val)
		If @error Then ExitLoop
		If StringLen($line) > 0 Then
			PrintLog("Version:" & @CRLF & $line & _
					"-----------------------------------------------------------------------------")
		Else
			Sleep(200)
		EndIf
	WEnd

	$cmd = @ComSpec & " /c " & FileGetShortName($gRepToolPath) & " --help"
	$val = Run($cmd, $filepath, @SW_HIDE, $STDERR_CHILD + $STDOUT_CHILD)
	While 1
		$line = StdoutRead($val)
		If @error Then ExitLoop
		If StringLen($line) > 0 Then
			PrintLog($line)
		Else
			Sleep(200)
		EndIf
	WEnd
	_GUICtrlEdit_LineScroll($ctrl_loglist, 0, -_GUICtrlEdit_GetLineCount($ctrl_loglist))
EndFunc   ;==>PrintHelpReport


Func PrintHelpGui()
	DeleteLog()
	Local $var = IniReadSection($gHelpIniFileName, "GUI Helptext")
	If Not @error Then
		For $k = 1 To $var[0][0]
			PrintLog($var[$k][1])
		Next
	Else
		PrintLog("Gui Help read error:" & @error & @CRLF & "Hint: Check if help file : " & $gHelpIniFileName & " exists!")
	EndIf
	_GUICtrlEdit_LineScroll($ctrl_loglist, 0, -_GUICtrlEdit_GetLineCount($ctrl_loglist))
EndFunc   ;==>PrintHelpGui