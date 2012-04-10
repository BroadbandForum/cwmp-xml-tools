#Region ;**** Directives created by AutoIt3Wrapper_GUI ****
#AutoIt3Wrapper_Icon=Install\BBF-Icon.ico
#AutoIt3Wrapper_Outfile=ReportGui.exe
#AutoIt3Wrapper_Res_Description=Graphical user interface for report.exe
#AutoIt3Wrapper_Res_Fileversion=0.9
#AutoIt3Wrapper_Res_LegalCopyright=klaus.wich@nsn.com
#AutoIt3Wrapper_Run_Tidy=y
#AutoIt3Wrapper_Run_Obfuscator=y
#EndRegion ;**** Directives created by AutoIt3Wrapper_GUI ****
;;; MyCommonLib.AU3 ;;;
; Klaus.wich@nsn.com

#include-once
#include "CommonFunctionLib.au3"

Global $inclist
Global $g_LogHandle
Global $g_BBFWEBADDR = "http://www.broadband-forum.org"

Func CheckEnv()
	;check if report.exe exists
	If Not FileExists($gRepToolPath) Then
		setReportTool()
	EndIf
EndFunc   ;==>CheckEnv


Func GetTimeDiffString($timer)
	Local $Time = Int(TimerDiff($timer))
	Local $Secs, $Mins, $Hour

	_TicksToTime($Time, $Hour, $Mins, $Secs)
	If $Mins > 0 Then
		Return StringFormat("%02i:%02i.%03i min:s", $Mins, $Secs, Mod($Time, 1000))
	Else
		Return StringFormat("%02i.%03i s", $Secs, Mod($Time, 1000))
	EndIf
EndFunc   ;==>GetTimeDiffString


Func DeleteLog()
	GUICtrlSetData($ctrl_loglist, "", "")
	;SetColor(99)
EndFunc   ;==>DeleteLog


Func OpenLogfile($name)
	$g_LogHandle = FileOpen($name, 2)
	Local $_rc = True
	If $g_LogHandle = -1 Then
		PrintLog("Unable to open log file " & $name)
		$_rc = False
	EndIf
	Return $_rc
EndFunc   ;==>OpenLogfile


Func CloseLogfile()
	FileClose($g_LogHandle)
EndFunc   ;==>CloseLogfile


Func PrintLog2File($silent, $val)
	If $silent Then
		; TODO: check if file is open
		FileWriteLine($g_LogHandle, $val)
	Else
		PrintLog($val)
	EndIf
EndFunc   ;==>PrintLog2File


Func PrintLog($val)
	GUICtrlSetData($ctrl_loglist, $val & @CRLF, 1)
EndFunc   ;==>PrintLog


Func PrintLogCont($val)
	GUICtrlSetData($ctrl_loglist, $val, 1)
EndFunc   ;==>PrintLogCont


;~ Func DebugLog($val)
;~ 	$DGGCount += 1
;~ 	ConsoleWrite("DBG[" & $DGGCount & "]:>" & $val & "<" & @LF)
;~ EndFunc   ;==>DebugLog
Func DebugLog($val,$line = @ScriptLineNumber, $name = @ScriptName)
	ConsoleWrite(StringFormat("DBG[%12s:%04d]:>%s<", $name,$line,$val) & @CRLF)
EndFunc   ;==>DebugLog

Func OpenFile()
	Local $xmlname = FileOpenDialog("Select xml file for report generation", $filepath, "XML (*.xml;*.xsd)| ALL (*.*)", 1 + 4)
	If @error Then
	Else
		$filepath = GetPath($xmlname)
		$filename = $xmlname
		GUICtrlSetData($ctrl_filelabel, GetFileName($filename))
	EndIf
EndFunc   ;==>OpenFile


Func SearchStringInFile($filename, $str)
	Local $line, $found = 0, $eof = 0, $filehandle = FileOpen($filename, 0)
	Do
		$line = FileReadLine($filehandle)
		If @error = -1 Then
			$eof = 1
		Else
			If StringInStr($line, $str) Then
				$found = 1
			EndIf
		EndIf
	Until ($found = 1) Or (@error) Or $eof
	FileClose($filehandle)
	Return $found
EndFunc   ;==>SearchStringInFile


Func SaveLog2File()
	Local $lgfile = FileSaveDialog("Specify logfile destination:", $filepath, "log files (*.log) | All (*.*)", 16, GetFileName($filename) & ".log")
	Local $fhdl = FileOpen($lgfile, 1)
	If $fhdl = -1 Then
		PrintLog("Error: Unable to open file " & $lgfile & " - log not saved!")
	Else
		FileWrite($fhdl, GUICtrlRead($ctrl_loglist))
		FileClose($fhdl)
	EndIf
EndFunc   ;==>SaveLog2File


Func mGUICreateRadioBtn($name, $col, $line, $width)
	Local $handle
	If $width = 0 Then
		$handle = GUICtrlCreateRadio($name, $col, $line)
	Else
		$handle = GUICtrlCreateRadio($name, $col, $line, $width)
	EndIf
	GUICtrlSetResizing($handle, $GUI_DOCKLEFT + $GUI_DOCKTOP+ $GUI_DOCKHEIGHT)
	setToolTip($handle, $name) ;set tool tip
	Return $handle
EndFunc   ;==>mGUICreateRadioBtn


Func mGUICreateSetCheckbox($name, $col, $line)
	Local $handle = GUICtrlCreateCheckbox($name, $col, $line)
	GUICtrlSetResizing($handle, $GUI_DOCKLEFT + $GUI_DOCKTOP+ $GUI_DOCKHEIGHT)
	setToolTip($handle, $name) ;set tool tip
	Return $handle
EndFunc   ;==>mGUICreateSetCheckbox


Func mGUICreateMenueItem($name, $menu)
	Local $handle = GUICtrlCreateMenuItem($name, $menu)
	GUICtrlSetResizing($handle, $GUI_DOCKLEFT + $GUI_DOCKTOP+ $GUI_DOCKHEIGHT)
	setToolTip($handle, $name) ;set tool tip
	Return $handle
EndFunc   ;==>mGUICreateMenueItem


Func mGUICreateLabel($name, $col, $line)
	Local $handle = GUICtrlCreateLabel($name & ":", $col, $line)
	GUICtrlSetResizing($handle, $GUI_DOCKLEFT + $GUI_DOCKTOP+ $GUI_DOCKHEIGHT)
	setToolTip($handle, $name) ;set tool tip
	;Return $handle
EndFunc   ;==>mGUICreateLabel


Func mGUICreateButton($name, $col, $line, $width)
	Local $handle
	If $width = 0 Then
		$handle = GUICtrlCreateButton($name, $col, $line)
	Else
		$handle = GUICtrlCreateButton($name, $col, $line, $width)
	EndIf
	GUICtrlSetResizing($handle, $GUI_DOCKLEFT + $GUI_DOCKTOP+ $GUI_DOCKHEIGHT)
	setToolTip($handle, $name) ;set tool tip
	Return $handle
EndFunc   ;==>mGUICreateButton


Func setToolTip($handle, $name)
	GUICtrlSetTip($handle, ReadToolTipFromIni($name), $name & ":", 1, 0) ;set tool tip
EndFunc   ;==>setToolTip


Func ReadToolTipFromIni($name)
	Local $k, $tip, $var = IniReadSection($gHelpIniFileName, $name)
	If Not @error Then
		For $k = 1 To $var[0][0]
			$tip &= $var[$k][1] & @CRLF
		Next
		$tip = StringLeft($tip, StringLen($tip) - 2)
	EndIf
	If StringLen($tip) = 0 Then
		DebugLog("Missing Tooltip: " & $name)
	EndIf
	Return $tip
EndFunc   ;==>ReadToolTipFromIni


Func GetFileNameWoE($_filepathname)
	Local $k = StringRight($_filepathname, StringLen($_filepathname) - StringInStr($_filepathname, "\", 0, -1))
	Return StringLeft($k, StringInStr($k, ".", 0, -1) - 1)
EndFunc   ;==>GetFileNameWoE


Func GetFileName($_filepathname)
	Return StringRight($_filepathname, StringLen($_filepathname) - StringInStr($_filepathname, "\", 0, -1))
EndFunc   ;==>GetFileName


Func GetPath($_filepathname)
	Return StringLeft($_filepathname, StringInStr($_filepathname, "\", 0, -1))
EndFunc   ;==>GetPath


Func IncludeDirAdd()
	Local $dirname = FileSelectFolder("Select include directory", "@WindowsDir", 3, $filepath)
	If Not @error Then
		GUICtrlSetData($inclist, $dirname)
	EndIf
EndFunc   ;==>IncludeDirAdd


Func IncludeDirDel()
	Local $i = _GUICtrlListBox_GetCurSel($inclist)
	If $i >= 0 Then
		_GUICtrlListBox_DeleteString($inclist, $i)
	EndIf
EndFunc   ;==>IncludeDirDel


Func IncludeDirUp()
	Local $i = _GUICtrlListBox_GetCurSel($inclist)
	If $i > 0 Then
		_GUICtrlListBox_SwapString($inclist, $i, ($i - 1))
	EndIf
EndFunc   ;==>IncludeDirUp


Func setReportTool()
	Local $_RepToolPath = FileOpenDialog("Select report.exe to be used:", GetPath($gRepToolPath), "Executable files (*.exe)", "Report.exe")
	If @error = 0 Then
		$gRepToolPath = $_RepToolPath
		IniWrite($iniFilePathName, "Reporttool", "toolpath", $gRepToolPath)
		PrintLog("New report tool selected is " & $gRepToolPath)
	else
		PrintLog("No new report tool selected ")
	EndIf
EndFunc   ;==>setReportTool


Func selectDefaultIncludeDir()
	Local $_Path = FileSelectFolder("Select directory to be used as default include directory:", "", -1, $g_Mainincludepath)
	If $_Path <> "" Then
		$g_Mainincludepath = $_Path
		PrintLog("New default include directory is " & $g_Mainincludepath)
	EndIf
	CheckMainInclude()
EndFunc   ;==>selectDefaultIncludeDir


Func getShortLogLevel($lev)
	Local $a = StringLeft($lev, 1)
	Local $e = StringRight($lev, 1)
	If StringIsInt($e) Then
		Return $a & $e
	Else
		Return $a
	EndIf
EndFunc   ;==>getShortLogLevel


Func getLongLogLevel($lev)
	Local $a = StringLeft($lev, 1)
	Select
		Case $a = "i"
			$a = "info"
		Case $a = "e"
			$a = "error"
		Case $a = "w"
			$a = "warning"
		Case $a = "d"
			$a = "debug"
	EndSelect
	Local $e = StringRight($lev, 1)
	If StringIsInt($e) Then
		$a &= "-" & $e
	EndIf
	Return $a
EndFunc   ;==>getLongLogLevel


;~ Func setLogLevel()
;~ 	Local $lWindow = GUICreate("Select Loglevel", 145, 180, -1, -1, $WS_POPUP or $DS_MODALFRAME)
;~ 	Local $ctrl_okbutton = GUICtrlCreateButton("Ok", 15, 120, 50)
;~ 	Local $ctrl_clcbutton = GUICtrlCreateButton("Cancel", 75, 120, 50)
;~ 	Local $mylist = GUICtrlCreateList("", 5, 10, 120, 100, BitOR($WS_BORDER, $WS_VSCROLL, $LBS_NOTIFY))
;~ 	Local $d = getLongLogLevel(IniRead($iniFilePathName, "Settings", "Loglevel", "w1"))
;~ 	GUICtrlSetData($mylist, "|error|info|warning-0|warning-1|warning-2|warning-3|debug-0|debug-1|debug-2|debug-3", $d)
;~ 	GUISetState(@SW_SHOW, $lWindow)
;~
;~ 	While 1
;~ 		Local $msg = GUIGetMsg()
;~ 		Select
;~ 			Case $msg = $ctrl_clcbutton
;~ 				ExitLoop
;~ 			Case $msg = $ctrl_okbutton
;~ 				IniWrite($iniFilePathName, "Settings", "Loglevel", getShortLogLevel(GUICtrlRead ($mylist)))
;~ 				ExitLoop
;~ 		EndSelect
;~ 	WEnd

;~ 	;write log settings

;~ 	;delete window
;~ 	GUIDelete($lWindow)
;~
;~ EndFunc


Func setIncludeDir()
	$incWindow = GUICreate("Select Include directories", 600, 180, -1, -1, $WS_POPUP Or $DS_MODALFRAME)
	GUICtrlCreateLabel("Include Directories:", 10, 12 + 2)
	$inclist = GUICtrlCreateList("", 10, 28, 550, 80, BitOR($WS_BORDER, $WS_VSCROLL))
	$ctrl_incaddbutton = GUICtrlCreateButton("Add", 560, 28, 30)
	$ctrl_incdelbutton = GUICtrlCreateButton("Del", 560, 53, 30)
	$ctrl_incupbutton = GUICtrlCreateButton("Up", 560, 78, 30)
	setToolTip($ctrl_incupbutton, "Add")
	setToolTip($ctrl_incupbutton, "Del")
	setToolTip($ctrl_incupbutton, "Up")
	Local $ctrl_okbutton = GUICtrlCreateButton("Ok", 260, 110, 80)

	;read include directories:
	For $k = 1 To IniRead($iniFilePathName, "Includes", "IncNo", 0)
		GUICtrlSetData($inclist, IniRead($iniFilePathName, "Includes", $k, ""))
	Next

	GUISetState(@SW_SHOW, $incWindow)

	While 1
		Local $msg = GUIGetMsg()
		Select
			Case $msg = $ctrl_incaddbutton
				IncludeDirAdd()

			Case $msg = $ctrl_incdelbutton
				IncludeDirDel()

			Case $msg = $ctrl_incupbutton
				IncludeDirUp()

			Case $msg = $ctrl_okbutton
				ExitLoop
		EndSelect
	WEnd

	;write include directories:
	IniWrite($iniFilePathName, "Includes", "IncNo", _GUICtrlListBox_GetCount($inclist))
	For $k = 1 To _GUICtrlListBox_GetCount($inclist)
		IniWrite($iniFilePathName, "Includes", $k, _GUICtrlListBox_GetText($inclist, $k - 1))
	Next
	;delete window
	GUIDelete($incWindow)
EndFunc   ;==>setIncludeDir


Func CheckForUpdates()
	PrintLog("Check for available updates:" & @LF)
	Local $remversion = $gWebReportToolAddr & "/ReportGui/README.txt"
	Local $remexeversion = $gWebReportToolAddr & "/Report_Tool/report.exe.info"
	Local $pat = "([0-9]*\/[0-9]*\/[0-9]*)\s*ReportGuiSetup\s*(.*),.*ReportGui\s*(.+),.+\#([0-9]*)"
	PrintLogCont("- getting version of used report.exe ")
	Local $repexever = GetReportExeVersion()
	PrintLog(" .. done")
	; Use IE defaults for proxy
	HttpSetProxy(0)
	; Retrieve Version Information for ReportGUI
	PrintLogCont("- retrieving ReportGui installer version(s) info from server")
	Local $sData = InetRead($remversion, 18)
	Local $nBytesRead = @extended
	Local $repexavailable = 0
	Local $repexsaavailable = 0
	Local $guiavailable = 0
	Local $err = 0
	Local $err2 = 0
	Local $loadrepSA = 0
	Local $loadGui = 0
	PrintLog(" .. done")
	If $nBytesRead > 0 Then
		Local $a = StringRegExp(BinaryToString($sData), $pat, 1)
		If @error == 0 Then
			$repexavailable = $a[3]
			$guiavailable = $a[2]
		Else
			$err = 1
		EndIf
	Else
		$err = 1
		PrintLog(" => Download error for ReportGui version info, check Internet connectivity and retry later")
	EndIf

	; Retrieve version info for standalone Report.exe
	PrintLogCont("- retrieving Report.exe version info from server")
	$sData = InetRead($remexeversion, 18)
	$nBytesRead = @extended
	PrintLog(" .. done")
	If $nBytesRead > 0 Then
		Local $a = StringRegExp(BinaryToString($sData), "report.pl\#([0-9]*)", 1)
		If @error == 0 Then
			$repexsaavailable = $a[0]
		Else
			$err2 = 1
		EndIf
	Else
		$err2 = 1
	EndIf

	If $err2 > 0 Then
		PrintLog(" => Download error for Report.exe version info, check Internet connectivity and retry later")
	EndIf

	;$repexsaavailable = 192 ;TEST!!!
	;$err2 = 0
	;$guiavailable = "2.3"

	If ($err = 0) And ($err2 = 0) Then
		; both file version are available:
		If $repexsaavailable > $repexavailable Then ; use standalone report.exe
			$repexavailable = $repexsaavailable
			If $repexavailable > $repexever Then
				$loadrepSA = 1
			EndIf
		EndIf
	EndIf

	If $err = 0 Then
		$loadGui = StringCompare($guiavailable, $progversion)
	EndIf

	; Display result
	If $err = 0 Then
		PrintLog(@LF & "- Version info" & @CRLF & "  * ReportGUI installed version is : " & $progversion & @TAB & " available download version is : " & $guiavailable)
		PrintLog("  * Report.exe used version is :" & $repexever & @TAB & " available download version is : " & $repexavailable)
		If $loadGui > 0 And (MsgBox(4, "ReportGui installer download", "A new version of the ReportGui (reportGui " & $guiavailable & _
				") is available, do you want to download it now ?" & @CRLF & "(Program will be closed)") == 6) Then
			;DownloadReportGui()
			ShellExecute($gWebReportToolAddr & "/ReportGui/ReportGuiSetup.exe")
			Exit
		EndIf
		If ($loadrepSA > 0) And (MsgBox(4, "Report.exe download", "A new version of the Report.exe (report.exe#" & $repexavailable & _
				") is available, do you want to download it now ?") == 6) Then
			ShellExecuteWait(@ScriptDir & "\ReportUpdate.exe", "u")
		EndIf
		If ($loadrepSA <= 0) And ($loadGui <= 0) Then
			PrintLog(@CRLF & @TAB & "No updates available!" & @CRLF)
		EndIf
	Else
		PrintLog("Error while checking for updates, retry later")
	EndIf
	PrintLog("Done")
EndFunc   ;==>CheckForUpdates


Func DownloadReportGui()
	PrintLog("Download new ReportGUI to " & @TempDir)
	Local $remexeversion = $gWebReportToolAddr & "/ReportGui/ReportGuiSetup.exe"
	If DownloadWithLogInfo($remexeversion, @TempDir & "\") Then
		Sleep(200)
		PrintLog("Download success for reportGui intaller")
		Run(@TempDir & "/ReportGuiSetup.exe")
	Else
		PrintLog("Download error, retry later or go to webpage")
	EndIf
EndFunc   ;==>DownloadReportGui


Func RestoreReportExe()
	PrintLog("Restore report.exe:")
	ShellExecuteWait(@ScriptDir & "\ReportUpdate.exe", "r")
	;PrintLog("command is " & @ScriptDir & "\ReportUpdate.exe r")
	PrintLog("Done")
EndFunc   ;==>RestoreReportExe


Func CheckMainInclude()
	Local $nofls = False
	If DirGetSize($g_Mainincludepath) == 0 Then
		$nofls = True
	Else
		Local $search = FileFindFirstFile($g_Mainincludepath & "\*.xml")
		If $search = -1 Then
			$nofls = True
		EndIf
		FileClose($search)
	EndIf
	If $nofls And (MsgBox(4, "Include check", "The default include directory '" & @CR & $g_Mainincludepath & "' does not contain any xml files, do you want to download them now ?" & _
			@CR & @CR & 'Notes' & @CR & 'The files can be downloaded later with the option "Help"->"Get BBF xml files"' & _
			@CR & @CR & 'The default include path can be changed with the option "Settings"->"Select default include directory"') == 6) Then
		DownloadallBBFXML()
	EndIf
EndFunc   ;==>CheckMainInclude


;========= update functions =========
Func DownloadallBBFXML()
	PrintLog("Download all files from BBF web page:")
	Local $remastr, $sp = "@"
	;Local $inchtml = (BitAND(GUICtrlRead($m_em_htmlload), $GUI_CHECKED) == $GUI_CHECKED)
	PrintLog("- Retrieving list of remote files")
	If getBBFFileListstr($remastr, (BitAND(GUICtrlRead($m_em_htmlload), $GUI_CHECKED) == $GUI_CHECKED)) > 0 Then
		PrintLog('Retrieved files will be stored in main include path "' & $g_Mainincludepath & '"' & @CR)
		Local $arr = StringSplit($remastr, $sp, 2)
		;downloadFileListFromBBFSite(StringSplit($remastr,$sp,2))
		downloadFileListFromBBFSite($arr)
	Else
		PrintLog("could not get BBF file list, aborting!")
	EndIf
	PrintLog("Done")
EndFunc   ;==>DownloadallBBFXML


Func CheckForNewBBFXML()
	PrintLog("Check for updated or changed XML")
	Local $remastr, $i, $k, $locastr, $b, $a, $sp = "@"
	Local $inchtml = (BitAND(GUICtrlRead($m_em_htmlload), $GUI_CHECKED) == $GUI_CHECKED)
	PrintLog("- Retrieving list of remote files")
	If getBBFFileListstr($remastr, $inchtml) > 0 Then
		PrintLog("- Reading local files from main include directory " & $g_Mainincludepath)
		Local $search = FileFindFirstFile($g_Mainincludepath & "\*.x*")
		If $search <> -1 Then
			While 1
				Local $file = FileFindNextFile($search)
				If @error Then ExitLoop
				$locastr &= $file & $sp
			WEnd
			FileClose($search)
		EndIf
		If $inchtml Then
			Local $search = FileFindFirstFile($g_Mainincludepath & "\*.htm*")
			If $search <> -1 Then
				While 1
					Local $file = FileFindNextFile($search)
					If @error Then ExitLoop
					$locastr &= $file & $sp
				WEnd
				FileClose($search)
			EndIf
		EndIf
		$locastr = StringTrimRight($locastr, 1)
		PrintLog("- Comparing lists")
		Local $diff = compSeparatedStringDiffs($remastr, $locastr, $sp)
		If StringLen($diff) > 0 Then
			Local $da = StringinStringDiffs($locastr, $diff, $sp)
			If StringLen($da) > 0 Then
				Local $diffa = StringSplit($da, $sp, 2)
				PrintLog("- " & ubound($diffa) & " Files missing in main include directory")
				For $element In $diffa
					PrintLog("  * " & $element)
				Next
				If MsgBox(4, "Update??", "Do you want to download the missing files?") == 6 Then
					PrintLog("- Download missing files:")
					downloadFileListFromBBFSite($diffa)
				Else
					PrintLog("=> " & ubound($diffa) & " Files missing, no download requested")
				EndIf
			Else
				PrintLog("=> Main include directory is complete, no files are missing !")
			EndIf
		Else
			PrintLog("- No new files found")
		EndIf
		PrintLog("Done")
	Else
		PrintLog("could not get BBF file list, aborting!")
	EndIf
EndFunc   ;==>CheckForNewBBFXML


Func downloadFileListFromBBFSite(ByRef $alist)
	Local $ec = 0
	For $element In $alist
		;PrintLog($g_BBFWEBADDR & "/cwmp/" & $element & " =>" & $g_Mainincludepath & "\" & $element)
		If Not DownloadWithLogInfo($g_BBFWEBADDR & "/cwmp/" & $element, $g_Mainincludepath & "\" & $element) Then
			$ec += 1
		EndIf
	Next
	PrintLogCont(UBound($alist) & " files downloaded, ")
	If $ec = 0 Then
		PrintLog("no errors")
	Else
		PrintLog($ec & "errors")
	EndIf
	Return
EndFunc   ;==>downloadFileListFromBBFSite


; Read BBF main page to get list of released xml and xsd
; if $inchtml is set include the htmls
; list is returned as string with @ as seperator
Func getBBFFileListstr(ByRef $liststr, $inchtml)
	Local $remxml = $g_BBFWEBADDR & "/cwmp.php"
	Local $locxml = @TempDir & "\xml"
	Local $k = 0
	Local $line, $file, $bp, $ep
	Local $count = 0
	; Use IE defaults for proxy
	HttpSetProxy(0)
	$k = InetGet($remxml, $locxml) ; Retrieve Version Information
	$file = FileOpen($locxml, 0)
	If $file = -1 Then
		PrintLog("Error - Unable to read remote file")
	Else
		While 1
			$line = FileReadLine($file)
			If @error = -1 Then ExitLoop
			$bp = StringInStr($line, '<a href="/cwmp/')
			If $bp > 0 Then
				$ep = StringInStr($line, '</a>', ($bp + 1))
				If $ep > 0 Then
					$line = StringMid($line, ($bp + 15), ($ep - $bp - 9))
					; filter for xml & xsd Files
					$ep = StringInStr($line, '.x')
					If $ep > 0 Then
						$liststr &= StringLeft($line, $ep + 3) & "@"
						$count += 1
					Else
						If $inchtml Then
							$ep = StringInStr($line, '.html')
							If $ep > 0 Then
								$liststr &= StringLeft($line, $ep + 4) & "@"
								$count += 1
							EndIf
						EndIf
					EndIf
				EndIf
			EndIf
		WEnd
	EndIf
	FileClose($file)
	$liststr = StringTrimRight($liststr, 1)
	Return $count
EndFunc   ;==>getBBFFileListstr


Func DownloadWithLogInfo($remaddr, $locfile)
	PrintLog('Downloading "' & $remaddr & '"')
	Local $hDownload = InetGet($remaddr, $locfile, 18, 1)
	Do
		Sleep(250)
		PrintLogCont(".")
	Until InetGetInfo($hDownload, 2) ; Check if the download is complete.
	PrintLog(" done, downloaded " & InetGetInfo($hDownload, 0) & " Bytes")
	Local $rc = InetGetInfo($hDownload, 3)
	If Not $rc Then
		PrintLog("Download error is: " & InetGetInfo($hDownload, 4) & " : " & InetGetInfo($hDownload, 5))
	EndIf
	InetClose($hDownload)
	Return $rc
EndFunc   ;==>DownloadWithLogInfo


Func SendFeedback()
	;local $msgbody = "enter your message here" & @CRLF & "===LOG CONTENT: ===================" & @CRLF & "'" & GUICtrlRead($ctrl_loglist) &"'"
	Local $msgbody = ""
	_INetMail("klaus.wich@nsn.com", "ReportGui Version " & $progversion & " - Feedback", $msgbody)
EndFunc   ;==>SendFeedback