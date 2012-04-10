#RequireAdmin
#Region ;**** Directives created by AutoIt3Wrapper_GUI ****
#AutoIt3Wrapper_Res_requestedExecutionLevel=asInvoker
#AutoIt3Wrapper_Run_Obfuscator=y
#Obfuscator_Parameters=/striponly
#EndRegion ;**** Directives created by AutoIt3Wrapper_GUI ****
; Update the program with elevated rights
; Klaus.wich@nsn.com

#include <GUIConstantsEx.au3>
#include <EditConstants.au3>
#include <WindowsConstants.au3>
#include <Constants.au3>

Opt('MustDeclareVars', 1)
Opt('TrayIconHide', 1)

Global $progname = "ReportGui: Updater"
Global $gWebReportToolAddr = "https://tr69xmltool.iol.unh.edu/repos/cwmp-xml-tools"
Global $ctrl_loglist, $ctrl_donebutton, $mainWindow
Global $iniFilePathName = @AppDataDir & "\ReportGui\ReportGui.ini"
Global $gRepToolPath, $filepath
Global $DGGCount = 0

Main()

Func CreateWindow()
	$mainWindow = GUICreate($progname, 470, 200)
	$ctrl_loglist = GUICtrlCreateEdit("", 0, 0, 465, 170, BitOR($ES_READONLY, $ES_AUTOVSCROLL))
	GUICtrlSetBkColor($ctrl_loglist, 0xd0f0f0)
	$ctrl_donebutton = GUICtrlCreateButton("Done",220, 170, 50)
	GUISetState(@SW_SHOW)
EndFunc   ;==>CreateWindow


Func PrintLog($val)
	GUICtrlSetData($ctrl_loglist, $val & @CRLF, 1)
EndFunc   ;==>PrintLog


Func PrintLogCont($val)
	GUICtrlSetData($ctrl_loglist, $val, 1)
EndFunc   ;==>PrintLogCont


Func DebugLog($val)
	$DGGCount += 1
	ConsoleWrite("DBG[" & $DGGCount & "]:>" & $val & "<" & @LF)
EndFunc


; ---- Work routine ----------------------------
Func GetInitValues()
	$filepath = IniRead($iniFilePathName, "WorkingDir", "filepath", @WindowsDir & "\")
	$gRepToolPath = IniRead($iniFilePathName, "Reporttool", "toolpath", "report.exe")
EndFunc


Func GetReportExeVersion()
	Local $line = ""
	Local $cmd = @ComSpec & " /c " & FileGetShortName($gRepToolPath) & " --info"
	;DebugLog($cmd)
	Local $val = Run($cmd, $filepath, @SW_HIDE, $STDERR_CHILD + $STDOUT_CHILD)
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


Func DownloadWithLogInfo($remaddr, $locfile)
	PrintLog('- Downloading "' & $remaddr & '"')
	Local $hDownload = InetGet($remaddr, $locfile, 18, 1)
	Do
		Sleep(250)
		PrintLogCont(".")
	Until InetGetInfo($hDownload, 2) ; Check if the download is complete.
	PrintLog(" done, downloaded " & InetGetInfo($hDownload, 0) & " Bytes")
	Local $rc = InetGetInfo($hDownload, 3)
	if not $rc Then
		PrintLog("Download error is: " & InetGetInfo($hDownload, 4) & " : " & InetGetInfo($hDownload, 5))
	endif
	InetClose($hDownload)
	Return $rc
EndFunc   ;==>DownloadWithLogInfo


Func RestoreReportExe()
	PrintLog("- Restore report.exe:")
	Local $repold = StringReplace($gRepToolPath, ".exe", ".exe_old", -1)
	If FileExists($repold) Then
		PrintLogCont("- Copy report.exe backup to >" & $gRepToolPath & "<")
		If FileCopy($repold, $gRepToolPath, 1) = 0 Then
			PrintLog(" : Failed")
		Else
			PrintLog(" : Success")
			PrintLogCont("- Checking version : ")
			PrintLog("  New version is " & GetReportExeVersion())
		EndIf
	Else
		PrintLog("  No backup of report.exe found")
	EndIf
EndFunc   ;==>RestoreReportExe


Func DownloadReportExe()
	PrintLog("Download new report.exe:")
	If FileExists($gRepToolPath) Then ; Backup old file
		Local $repold = StringReplace($gRepToolPath, ".exe", ".exe_old", -1)
		PrintLogCont("- Backup old report.exe to >" & $repold & "<")
		If FileCopy($gRepToolPath, $repold, 1) = 0 Then
			PrintLog(" : Failed")
		Else
			PrintLog(" : Success")
			FileDelete($gRepToolPath)
		EndIf
	EndIf
	HttpSetProxy(0)

	Local $remexeversion = $gWebReportToolAddr & "/Report_Tool/report.exe"
	If DownloadWithLogInfo($remexeversion, $gRepToolPath) Then
		Sleep(200)
		PrintLog("Download success")
		PrintLogCont("- Checking version : ")
		PrintLog("  New version is " & GetReportExeVersion())
	Else
		PrintLog("Download error, restoring previous version:")
		RestoreReportExe()
	EndIf
EndFunc   ;==>DownloadReportExe


func StartUpdate()
	if $CmdLine[0] > 0 Then
		Select
		Case $CmdLine[1] == "u"
			DownloadReportExe()
		Case $CmdLine[1] == "r"
			RestoreReportExe()
		Case $CmdLine[1] == "t"
			PrintLog("Test")
		Case Else
			Exit(1)
		EndSelect
	Else
		Exit(1)
	endif
	PrintLog("... Done")
EndFunc


; ---- Main Program ---------------------------------------
Func Main()
	CreateWindow()
	GetInitValues()
	StartUpdate()
	While 1
		Local $msg = GUIGetMsg(1)
		Select
			Case $msg[0] = $ctrl_donebutton
				ExitLoop
			Case $msg[0] = $GUI_EVENT_CLOSE
				ExitLoop
		EndSelect
	WEnd;
EndFunc

