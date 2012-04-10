#region ;**** Directives created by AutoIt3Wrapper_GUI ****
#AutoIt3Wrapper_Icon=Install\icons\Report-NSN.ico
#AutoIt3Wrapper_Outfile=ReportGui.exe
#AutoIt3Wrapper_UseX64=n
#AutoIt3Wrapper_Res_Description=Graphical user interface for report.exe
#AutoIt3Wrapper_Res_Fileversion=2.0.0.0
#AutoIt3Wrapper_Res_FileVersion_AutoIncrement=p
#AutoIt3Wrapper_Res_LegalCopyright=2011 Klaus Wich (klaus.wich@nsn.com)
#AutoIt3Wrapper_Res_Language=1033
#endregion ;**** Directives created by AutoIt3Wrapper_GUI ****
#include-once
#include <GUIConstantsEx.au3>
#include <EditConstants.au3>
#include <WindowsConstants.au3>
#include <IE.au3>
#include <GUIListBox.au3>
#include <Constants.au3>
#include <GuiEdit.au3>
#include <Array.au3>
#include <INet.au3>

Opt('MustDeclareVars', 1)

; include functions
#include "ReportGuiLib.au3"
#include "ReportGuiHelp.au3"


Func GetInitValues()
	If Not FileExists($iniFilePathName) Then
		FileCopy(@ScriptDir & "\" & $iniFileName, $iniFilePathName, 8)
	EndIf
	$gHelpIniFileName = FileGetShortName(@ScriptDir & "\" & $gHelpIniFileName)
	$filepath = IniRead($iniFilePathName, "WorkingDir", "filepath", @WindowsDir & "\")
	$comppath = IniRead($iniFilePathName, "WorkingDir", "comppath", $filepath)
	$filename = IniRead($iniFilePathName, "WorkingDir", "filename", "<unknown>")
	$g_Mainincludepath = IniRead($iniFilePathName, "WorkingDir", "defaultincpath", @AppDataDir & "\ReportGui\includes")
	$gRepToolPath = IniRead($iniFilePathName, "Reporttool", "toolpath", "report.exe")
	If StringLen(GetPath($gRepToolPath)) = 0 Then
		$gRepToolPath = FileGetShortName(@ScriptDir & "\" & $gRepToolPath)
	EndIf
EndFunc   ;==>GetInitValues


Func CheckInitValues()
	Local $inif, $k
	If Not FileExists($g_Mainincludepath) Then
		DirCreate($g_Mainincludepath)
		PrintLog("Include directory " & $g_Mainincludepath & " created")
	EndIf
	For $k = 1 To IniRead($iniFilePathName, "Includes", "IncNo", 0)
		$inif = IniRead($iniFilePathName, "Includes", $k, "")
		If Not FileExists(IniRead($iniFilePathName, "Includes", $k, "")) Then
			PrintLog("Warning: Additional include directory " & $inif & " does not exist")
		EndIf
	Next
EndFunc   ;==>CheckInitValues


Func SaveInitValues()
	IniWrite($iniFilePathName, "WorkingDir", "filepath", $filepath)
	IniWrite($iniFilePathName, "WorkingDir", "filename", $filename)
	IniWrite($iniFilePathName, "WorkingDir", "comppath", $comppath)
	IniWrite($iniFilePathName, "WorkingDir", "defaultincpath", $g_Mainincludepath)
	IniWrite($iniFilePathName, "Reporttool", "toolpath", $gRepToolPath)
	IniWrite($iniFilePathName, "Settings", "OpenGen", (BitAND(GUICtrlRead($m_OpenGen), $GUI_CHECKED) = $GUI_CHECKED))
	IniWrite($iniFilePathName, "Settings", "DelTmp", (BitAND(GUICtrlRead($m_DelTmp), $GUI_CHECKED) = $GUI_CHECKED))
	IniWrite($iniFilePathName, "Settings", "ShowStats", (BitAND(GUICtrlRead($m_ShowStats), $GUI_CHECKED) = $GUI_CHECKED))
	IniWrite($iniFilePathName, "Settings", "ShowCmd", (BitAND(GUICtrlRead($m_ShowCmd), $GUI_CHECKED) = $GUI_CHECKED))
	IniWrite($iniFilePathName, "Settings", "OldNames", (BitAND(GUICtrlRead($m_OldNames), $GUI_CHECKED) = $GUI_CHECKED))

	;IniWrite($iniFilePathName, "Settings", "AutoUpdate", (BitAND(GUICtrlRead($m_AutoUpdate), $GUI_CHECKED) = $GUI_CHECKED))
	IniWrite($iniFilePathName, "Settings", "HtmlLoad", (BitAND(GUICtrlRead($m_em_htmlload), $GUI_CHECKED) = $GUI_CHECKED))
	IniWrite($iniFilePathName, "Settings", "Tab", GUICtrlRead($tab))
	;read radio button state
	Local $rad = 0
	If GUICtrlRead($ctrlRepHtml) = $GUI_CHECKED Then
		$rad = 0
	ElseIf GUICtrlRead($ctrlRepHtmlLast) = $GUI_CHECKED Then
		$rad = 1
	ElseIf GUICtrlRead($ctrlRepErrCheck) = $GUI_CHECKED Then
		$rad = 2
	ElseIf GUICtrlRead($ctrlRepHtmlFlat) = $GUI_CHECKED Then
		$rad = 3
	ElseIf GUICtrlRead($ctrlRepPublish) = $GUI_CHECKED Then
		$rad = 4
	ElseIf GUICtrlRead($ctrlRepCompare) = $GUI_CHECKED Then
		$rad = 5
	ElseIf GUICtrlRead($ctrlRepFullCompare) = $GUI_CHECKED Then
		$rad = 6
	EndIf
	IniWrite($iniFilePathName, "Settings", "BasRad", $rad)
	SaveProfile("default")
EndFunc   ;==>SaveInitValues


Func Publish($f, $fp, $man, $silent)
	Local $name, $com, $minor, $cmd[9], $disp[9], $suffix, $k, $ofile, $oname, $outpath, $ploglev
	$name = GetFileName($f)
	$ploglev = " --loglevel=w1"
	If (BitAND(GUICtrlRead($cbRepPublishWar), $GUI_CHECKED) = $GUI_CHECKED) Then
		$ploglev &= " --nowarnreport"
	EndIf
	PrintLog("Publish: " & $name)
	PrintLog("- Requested file(s):")
	$name = StringLeft($name, StringInStr($name, ".", 0, -1) - 1)
	$ofile = FileGetShortName($name)
	$com = StringSplit($name, "-")
	If @error = 0 Then
		$minor = $com[4]
	Else
		$minor = 0
	EndIf
	$cmd[0] = 0
	$disp[0] = 0
	If SearchStringInFile($f, "<model name=""Device") And SearchStringInFile($f, "<model name=""InternetGatewayDevice") Then
		$cmd[0] += 1
		$oname = $ofile & ".html"
		$cmd[$cmd[0]] = GetCommandString($f, "html", "--nomodels --automodel" & $ploglev, $fp & $oname)
		$disp[$cmd[0]] = $oname
		PrintLog("  * generic HTML report (" & $oname & ")")
		If $minor > 0 Then
			$cmd[0] += 1
			If (BitAND(GUICtrlRead($m_OldNames), $GUI_CHECKED) = $GUI_CHECKED) Then
				$oname = $ofile & "-last.html"
			Else
				$oname = $ofile & "-diffs.html"
			EndIf
			$cmd[$cmd[0]] = GetCommandString($f, "html", "--nomodels --automodel --lastonly" & $ploglev, $fp & $oname)
			$disp[$cmd[0]] = $oname
			PrintLog("  * generic HTML report lastonly   (" & $oname & ")")
		EndIf
		$cmd[0] += 1
		$oname = $ofile & "-dev.html"
		$cmd[$cmd[0]] = GetCommandString($f, "html", "--ignore Internet" & $ploglev, $fp & $oname)
		$disp[$cmd[0]] = $oname
		PrintLog("  * HTML report Device model   (" & $oname & ")")
		If $minor > 0 Then
			$cmd[0] += 1
			If (BitAND(GUICtrlRead($m_OldNames), $GUI_CHECKED) = $GUI_CHECKED) Then
				$oname = $ofile & "-dev-last.html"
			Else
				$oname = $ofile & "-dev-diffs.html"
			EndIf
			$cmd[$cmd[0]] = GetCommandString($f, "html", "--ignore Internet --lastonly" & $ploglev, $fp & $oname)
			$disp[$cmd[0]] = $oname
			PrintLog("  * HTML report Device lastonly   (" & $oname & ")")
		EndIf
		$cmd[0] += 1
		$oname = $ofile & "-igd.html"
		$cmd[$cmd[0]] = GetCommandString($f, "html", "--ignore Device" & $ploglev, $fp & $oname)
		$disp[$cmd[0]] = $oname
		PrintLog("  * HTML report IGD model   (" & $oname & ")")
		If $minor > 0 Then
			$cmd[0] += 1
			If (BitAND(GUICtrlRead($m_OldNames), $GUI_CHECKED) = $GUI_CHECKED) Then
				$oname = $ofile & "-igd-last.html"
			Else
				$oname = $ofile & "-igd-diffs.html"
			EndIf
			$cmd[$cmd[0]] = GetCommandString($f, "html", "--ignore Device --lastonly" & $ploglev, $fp & $oname)
			$disp[$cmd[0]] = $oname
			PrintLog("  * HTML report IGD lastonly   (" & $oname & ")")
		EndIf
	Else
		$cmd[0] += 1
		$oname = $ofile & ".html"
		$cmd[$cmd[0]] = GetCommandString($f, "html", $ploglev, $fp & $oname)
		$disp[$cmd[0]] = $oname
		PrintLog("  * HTML report   (" & $oname & ")")
		If $minor > 0 Then
			$cmd[0] += 1
			If (BitAND(GUICtrlRead($m_OldNames), $GUI_CHECKED) = $GUI_CHECKED) Then
				$oname = $ofile & "-last.html"
			Else
				$oname = $ofile & "-diffs.html"
			EndIf
			$cmd[$cmd[0]] = GetCommandString($f, "html", "--lastonly" & $ploglev, $fp & $oname)
			$disp[$cmd[0]] = $oname
			PrintLog("  * HTML report lastonly   (" & $oname & ")")
		EndIf
	EndIf
	; generate flattend xml too:
	$cmd[0] += 1
	If (BitAND(GUICtrlRead($m_OldNames), $GUI_CHECKED) = $GUI_CHECKED) Then
		$oname = $ofile & "-all.xml"
	Else
		$oname = $ofile & "-full.xml"
	EndIf
	$cmd[$cmd[0]] = GetCommandString($f, "xml", $ploglev, $fp & $oname)
	$disp[$cmd[0]] = $oname
	PrintLog("  * Flattened xml   (" & $oname & ")")

	Local $_sc = 0 ; success counter

	For $k = 1 To $cmd[0]
		Local $_m = @CRLF & " (" & $k & "/" & $cmd[0] & ")" & " Report " & $disp[$k] & ":"
		PrintLog($_m)
		If $silent Then
			PrintLog2File(True, $_m)
		EndIf
		If GenReport($cmd[$k], $man, $silent) Then
			$_sc += 1
			;	PrintLog(" [success]")
			;Else
			;		PrintLog(" [error]")
		EndIf
	Next
	If $_sc < $cmd[0] Then
		PrintLog("Failure; " & $_sc & " of requested " & $cmd[0] & " report(s) generated")
	Else
		PrintLog("Success; " & $cmd[0] & " report(s) generated")
	EndIf
	Return $_sc
EndFunc   ;==>Publish


Func PublishEverything()
	DeleteLog()
	PrintLogcont("Publish everything from directory ")
	Local $_Path = FileSelectFolder("Select directory with xml files:", "", 2, $g_Mainincludepath)
	Local $file
	Local $count = 0
	Local $repcount = 0
	Local $_m
	If $_Path <> "" Then
		Local $_OldDir = @WorkingDir
		PrintLog($_Path)
		FileChangeDir($_Path)
		Local $search = FileFindFirstFile($_Path & "\*.xml")
		; Check if the search was successful
		If $search = -1 Then
			PrintLog("No xml files for publishing found, aborting")
			Return
		EndIf

		OpenLogfile($_Path & "\Publish.log")
		PrintLog2File(True, $progname & " " & $progversion & " " & $progdate)
		PrintLog2File(True, "--------------------------------------------------------------------------")
		PrintLog2File(True, "Publish content of " & $_Path)
		While 1
			$file = FileFindNextFile($search)
			If @error Then ExitLoop
			If StringRegExp($file, "\A[rtwTRW]{2}\-[\d\-]+.\.[xX][mM][lL]", 0) = 1 Then
				$count += 1
				$_m = @CRLF & @CRLF & StringFormat("== [%02d] %s ===", $count, $file)
				PrintLog($_m)
				PrintLog2File(True, $_m)
				$repcount += Publish($_Path & "\" & $file, $_Path & "\", False, True)
				;EndIf
			EndIf
		WEnd
		$_m = @CRLF & "============================" & @CRLF & StringFormat("Done, %d files published: %d reports generated", $count, $repcount)
		PrintLog($_m)
		PrintLog2File(True, $_m)
		; Close the search handle
		FileClose($search)
		FileChangeDir($_OldDir)
		CloseLogfile()
		; show logfile
		ShellExecute($_Path & "\Publish.log")
	Else
		PrintLog(" .. no path selected, done")
	EndIf
EndFunc   ;==>PublishEverything


Func genCompareCmd($Afile, $BFile, $outfile, $last)
	Local $target = "html"
	Local $cmd, $k
	$cmd = @ComSpec & " /c " & FileGetShortName($gRepToolPath)
	For $k = 1 To IniRead($iniFilePathName, "Includes", "IncNo", 0)
		$cmd &= " --include=" & FileGetShortName(IniRead($iniFilePathName, "Includes", $k, ""))
	Next
	$cmd &= " --report=" & $target
	If $last And (BitAND(GUICtrlRead($ctrlCpmpLO), $GUI_CHECKED) = $GUI_CHECKED) Then
		$cmd &= " --LastOnly"
		If (BitAND(GUICtrlRead($m_OldNames), $GUI_CHECKED) = $GUI_CHECKED) Then
			$outfile &= "-last"
		Else
			$outfile &= "-diffs"
		EndIf
		GUICtrlSetState($ctrlCpmpLO, $GUI_UNCHECKED)
	EndIf
	$outfile &= '.html'
	$cmd &= ' --compare "' & $BFile & '" "' & GetFileName($Afile) & '"'
	$cmd &= ' > "' & $outfile & '"'
	$gOutFile = $outfile ;set global outfile (for open)
	Return $cmd
EndFunc   ;==>genCompareCmd


Func Compare($full)
	Local $cmpfile = FileOpenDialog("Select xml file for comparison", $comppath, "XML (*.xml;*.xsd)| ALL (*.*)", 1 + 4)
	Local $flatA, $flatB
	If Not @error Then
		$comppath = GetPath($cmpfile)
		If $full Then
			$gOutFile = FileGetShortName($filepath) & GetFileNameWoE($filename) & "-cmp-full"
			; generate flat files:
			If (BitAND(GUICtrlRead($m_OldNames), $GUI_CHECKED) = $GUI_CHECKED) Then
				$flatA = FileGetShortName($filepath) & GetFileNameWoE($filename) & "-all-tmp.xml"
				$flatB = FileGetShortName($filepath) & GetFileNameWoE($cmpfile) & "-all-tmp.xml"
			Else
				$flatA = FileGetShortName($filepath) & GetFileNameWoE($filename) & "-full-tmp.xml"
				$flatB = FileGetShortName($filepath) & GetFileNameWoE($cmpfile) & "-full-tmp.xml"
			EndIf
			If GenReport(GetCommandString($filename, "xml", "", $flatA), False, False) Then
				If GenReport(GetCommandString($cmpfile, "xml", "", $flatB), False, False) Then
					GenReport(genCompareCmd($flatA, $flatB, $gOutFile, False), True, False)
				EndIf
				; TODO error messages
			EndIf
			If (BitAND(GUICtrlRead($m_DelTmp), $GUI_CHECKED) = $GUI_CHECKED) Then
				FileDelete($flatA)
				FileDelete($flatB)
			EndIf
		Else
			$gOutFile = FileGetShortName($filepath) & GetFileNameWoE($filename) & "-cmp"
			GenReport(genCompareCmd($filename, $cmpfile, $gOutFile, True), True, False)
		EndIf
	Else
		PrintLog("No file to compare selected, abort comparison!")
	EndIf
EndFunc   ;==>Compare


Func GetCommandString($input, $target, $options, $output)
	Local $cmd, $k, $inif
	$cmd = @ComSpec & " /c " & FileGetShortName($gRepToolPath)
	; add local directory for includes:
	$cmd &= " --include=" & FileGetShortName(GetPath($input))
	For $k = 1 To IniRead($iniFilePathName, "Includes", "IncNo", 0)
		$inif = IniRead($iniFilePathName, "Includes", $k, "")
		If FileExists($inif) Then
			$cmd &= " --include=" & FileGetShortName(IniRead($iniFilePathName, "Includes", $k, ""))
		Else
			PrintLog("Warning: Additional include directory " & $inif & " does not exist")
		EndIf
	Next
	$cmd &= " --include=" & FileGetShortName($g_Mainincludepath)
	If Not StringInStr($options, "--special") Then
		$cmd &= " --report=" & $target
	EndIf
	$cmd &= " --option ReportGUI=" & $progversion
	$cmd &= " " & $options & ' "' & GetFileName($input) & '"'
	If ($output <> "") Then
		If ($target <> "null") Then
			$cmd &= ' > "' & $output & '"'
		EndIf
	EndIf
	Return $cmd
EndFunc   ;==>GetCommandString


Func BasicCommand()
	; Get Type to be created
	Local $target = "html"
	Local $repoptions = ""
	Local $outfile = GetFileNameWoE($filename)
	If GUICtrlRead($ctrlRepHtml) = $GUI_CHECKED Then
		; Nothing special here
		If (BitAND(GUICtrlRead($cbShowDiff), $GUI_CHECKED) = $GUI_CHECKED) Then
			$repoptions &= " --showDiffs"
			$outfile &= "-diffs"
			GUICtrlSetState($cbShowDiff, $GUI_UNCHECKED)
		EndIf
		If SearchStringInFile($filename, "<model name=""Device") And SearchStringInFile($filename, "<model name=""InternetGatewayDevice") Then
			$repoptions &= "--nomodels --automodel"
		EndIf
	ElseIf GUICtrlRead($ctrlRepHtmlLast) = $GUI_CHECKED Then
		$repoptions = " --LastOnly"
		If (BitAND(GUICtrlRead($m_OldNames), $GUI_CHECKED) = $GUI_CHECKED) Then
			$outfile &= "-last"
		Else
			$outfile &= "-diffs"
		EndIf
		If (BitAND(GUICtrlRead($cbShowDiff), $GUI_CHECKED) = $GUI_CHECKED) Then
			$repoptions &= " --showDiffs"
			$outfile &= "-diff"
			GUICtrlSetState($cbShowDiff, $GUI_UNCHECKED)
		EndIf
		If SearchStringInFile($filename, "<model name=""Device") And SearchStringInFile($filename, "<model name=""InternetGatewayDevice") Then
			$repoptions &= "--nomodels --automodel"
		EndIf
	ElseIf GUICtrlRead($ctrlRepHtmlFlat) = $GUI_CHECKED Then
		$target = "xml"
		If (BitAND(GUICtrlRead($m_OldNames), $GUI_CHECKED) = $GUI_CHECKED) Then
			$outfile &= "-all"
		Else
			$outfile &= "-full"
		EndIf
	ElseIf GUICtrlRead($ctrlRepErrCheck) = $GUI_CHECKED Then
		$target = "txt"
		$repoptions = " --pedantic=99 --special=nonascii --verbose=99 --warnbibref=99"
		$outfile = $outfile & "-err"
	EndIf
	$gOutFile = FileGetShortName($filepath) & $outfile & "." & $target
	; add Loglevel
	$repoptions &= " --loglevel=" & IniRead($iniFilePathName, "Settings", "Loglevel", "w1")
	Return GetCommandString($filename, $target, $repoptions, $gOutFile)
EndFunc   ;==>BasicCommand


Func CreateCommand()
	; create command string
	Local $target = GUICtrlRead($ctrl_formatselect)
	$gOutFile = $filepath & GetFileNameWoE($filename)
	If $target = "xml" Then
		$gOutFile &= "-xml"
	EndIf
	$gOutFile = $gOutFile & "." & $target
	Local $repoptions = ""
	Local $ignore = GUICtrlRead($ctrl_ignore)
	If StringLen($ignore) > 0 Then
		$repoptions &= " --ignore=" & $ignore & " "
	EndIf
	Local $pattern = GUICtrlRead($ctrl_pattern)
	If StringLen($pattern) > 0 Then
		$repoptions &= " --objpat=" & $pattern & " "
	EndIf
	If GUICtrlRead($ctrlLastOnly) = $GUI_CHECKED Then
		$repoptions &= "--lastonly "
	EndIf
	If GUICtrlRead($ctrl_ThisOnly) = $GUI_CHECKED Then
		$repoptions &= "--thisonly "
	EndIf
	If GUICtrlRead($ctrl_WriteOnly) = $GUI_CHECKED Then
		$repoptions &= "--writonly "
	EndIf
	If GUICtrlRead($ctrl_ShowSyntax) = $GUI_CHECKED Then
		$repoptions &= "--showsyntax "
	EndIf
	If GUICtrlRead($ctrl_ShowDiffs) = $GUI_CHECKED Then
		$repoptions &= "--showdiffs "
	EndIf
	If GUICtrlRead($ctrl_NoProfiles) = $GUI_CHECKED Then
		$repoptions &= "--noprofiles "
	EndIf
	If GUICtrlRead($ctrl_autobase) = $GUI_CHECKED Then
		$repoptions &= "--autobase "
	EndIf
	If GUICtrlRead($ctrl_deletedeprecated) = $GUI_CHECKED Then
		$repoptions &= "--deletedeprecated "
	EndIf
	If GUICtrlRead($ctrl_marktemplates) = $GUI_CHECKED Then
		$repoptions &= "--marktemplates "
	EndIf
	If GUICtrlRead($ctrl_automodel) = $GUI_CHECKED Then
		$repoptions &= "--automodel "
	EndIf
	If GUICtrlRead($ctrl_nocomments) = $GUI_CHECKED Then
		$repoptions &= "--nocomments "
	EndIf
	If GUICtrlRead($ctrl_nohyphenate) = $GUI_CHECKED Then
		$repoptions &= "--nohyphenate "
	EndIf
	If GUICtrlRead($ctrl_nolinks) = $GUI_CHECKED Then
		$repoptions &= "--nolinks "
	EndIf
	If GUICtrlRead($ctrl_nomodels) = $GUI_CHECKED Then
		$repoptions &= "--nomodels "
	EndIf
	If GUICtrlRead($ctrl_notemplates) = $GUI_CHECKED Then
		$repoptions &= "--notemplates "
	EndIf
	If GUICtrlRead($ctrl_nowarnredef) = $GUI_CHECKED Then
		$repoptions &= "--nowarnredef "
	EndIf
	If GUICtrlRead($ctrl_showspec) = $GUI_CHECKED Then
		$repoptions &= "--showspec "
	EndIf
	If GUICtrlRead($ctrl_ReadOnly) = $GUI_CHECKED Then
		$repoptions &= "--showreadonly "
	EndIf
	If GUICtrlRead($ctrl_pedantic) = $GUI_CHECKED Then
		$repoptions &= "--pedantic=99 "
	EndIf
	If GUICtrlRead($ctrl_allbibrefs) = $GUI_CHECKED Then
		$repoptions &= "--allbibrefs "
	EndIf
	$repoptions &= GUICtrlRead($ctrl_options)
	; add loglevel
	$repoptions &= " --loglevel=" & IniRead($iniFilePathName, "Settings", "Loglevel", "w1")
	Return GetCommandString($filename, $target, $repoptions, $gOutFile)
EndFunc   ;==>CreateCommand


Func ParseErrors($line)
	Return (StringInStr($line, "Schema parsers error") == 0)
EndFunc   ;==>ParseErrors


Func EvaluateOutputInd(ByRef $outputarray, ByRef $statstr, $indcode, $indname, $silent)
	Local $sum, $ts
	Local $scmp = "urn:broadband-forum-org:" ;used to detect statistic
	Local $sl = StringLen($scmp) + 2
	Local $f = $indcode & "-%02d: %s"
	Local $ecount = 0

	For $element In $outputarray
		If StringLeft($element, 1) == $indcode And StringInStr($element, $scmp) == 0 Then
			PrintLog2File($silent, @CRLF & $indname & ":")
			ExitLoop
		EndIf
	Next
	For $element In $outputarray
		If StringLeft($element, 1) == $indcode Then
			$ts = StringMid($element, 2, StringLen($element) - 2)
			If StringInStr($ts, $scmp) == 0 Then
				$ecount += 1
				PrintLog2File($silent, StringFormat($f, $ecount, $ts))
			Else
				$statstr = $statstr & StringTrimLeft($ts, $sl) & "@"
			EndIf
		EndIf
	Next
	If $ecount > 1 Then
		$sum = $ecount & " " & $indname
		PrintLog2File($silent, $sum)
	ElseIf $ecount = 1 Then
		$sum = "1 " & StringTrimRight($indname, 1)
		PrintLog2File($silent, $sum)
	Else
		$sum = "no " & $indname ; & " found"
	EndIf
	;PrintLog2File($silent, $sum)
	Return $sum
EndFunc   ;==>EvaluateOutputInd


Func EvaluateOutput(ByRef $outputarray, $indcode, $indname, $silent)
	Local $sum
	Local $f = $indcode & "-%02d: %s"
	For $element In $outputarray
		If StringLeft($element, 1) == $indcode Then
			PrintLog2File($silent, @CRLF & $indname & ":")
			ExitLoop
		EndIf
	Next
	Local $ecount = 0
	For $element In $outputarray
		If StringLeft($element, 1) == $indcode Then
			$ecount += 1
			PrintLog2File($silent, StringFormat($f, $ecount, StringMid($element, 2, StringLen($element) - 2)))
		EndIf
	Next
	If $ecount > 1 Then
		$sum = $ecount & " " & $indname
		PrintLog2File($silent, $sum)
	ElseIf $ecount = 1 Then
		$sum = "1 " & StringTrimRight($indname, 1)
		PrintLog2File($silent, $sum)
	Else
		$sum = "no " & $indname
	EndIf
	Return $sum
EndFunc   ;==>EvaluateOutput


Func GenReport($cmd, $allowOpen, $silent)
	Local $rc = False
	Local $outfile = ""
	Local $sstat, $timer, $statdata
	Local $lla = StringLeft(IniRead($iniFilePathName, "Settings", "Loglevel", "w1"), 1)
	Dim $summary[8]

	If FileExists($gRepToolPath) Then
		$timer = TimerInit()
		;PrintLog2File($silent, "Report generation started ..." & @CRLF)
		If (BitAND(GUICtrlRead($m_ShowCmd), $GUI_CHECKED) = $GUI_CHECKED) Then
			PrintLog2File($silent, "Command:" & @CRLF & $cmd & @CRLF)
		EndIf
		PrintLogCont(".. generating report ")
		Local $val = Run($cmd, $filepath, @SW_HIDE, $STDERR_CHILD + $STDOUT_CHILD)
		If $val == 0 Then
			PrintLog("RUN Error " & $val)
		EndIf
		Local $line, $out
		While 1
			$line = StdoutRead($val)
			If @error Then ExitLoop
			PrintLogCont(".")
			If StringLen($line) > 0 Then
				$out &= $line
			Else
				Sleep(500)
			EndIf
		WEnd

		While 1
			$line = StderrRead($val)
			If @error Then ExitLoop
			PrintLogCont(".")
			If StringLen($line) > 0 Then
				$out &= $line
			Else
				Sleep(500)
			EndIf

		WEnd
		; Evaluate and print output:
		PrintLog("")
		Local $array = StringSplit($out, '(', 2)
		_ArrayAdd($summary, EvaluateOutput($array, "E", "errors", $silent))
		If $lla <> "e" Then
			_ArrayAdd($summary, EvaluateOutputInd($array, $statdata, "I", "indications", $silent))
			If $lla <> "i" Then
				_ArrayAdd($summary, EvaluateOutput($array, "W", "warnings", $silent))
				If $lla <> "w" Then
					_ArrayAdd($summary, EvaluateOutput($array, "D", "debug infos", $silent))
				EndIf
			EndIf
		EndIf

		If (BitAND(GUICtrlRead($m_ShowStats), $GUI_CHECKED) = $GUI_CHECKED) And $lla <> "e" Then
			Local $sarray = StringSplit($statdata, '@', 2)
			If UBound($sarray) > 0 Then
				PrintLog2File($silent, @CRLF & "Statistics: ")
				For $element In $sarray
					PrintLog2File($silent, $element)
				Next
			EndIf
		EndIf
		Local $pos = StringInStr($cmd, ">") ; determine name
		If $pos > 0 Then
			$outfile = StringRight($cmd, StringLen($cmd) - $pos - 1)
			$outfile = StringReplace($outfile, '"', '')
			If FileExists($outfile) Then ; check outfile
				If FileGetSize($outfile) > 0 Then
					$rc = True
				Else
					FileDelete($outfile) ; delete empty file
					PrintLog2File($silent, "Error: " & $outfile & " generated with size of 0 => file deleted, please check for errors!")
				EndIf
			Else
				PrintLog2File($silent, "Error: " & $outfile & " not generated, please check for errors!")
			EndIf

			; open output if requested
			If $rc And $allowOpen Then
				If (BitAND(GUICtrlRead($m_OpenGen), $GUI_CHECKED) = $GUI_CHECKED) Then
					ShellExecute($outfile)
				EndIf
			EndIf
		Else
			PrintLog2File($silent, "No output file defined, please see log for results")
		EndIf
		_ArrayAdd($summary, "Time needed: " & GetTimeDiffString($timer))
		; print summary
		PrintLog2File($silent, @CRLF & "Summary:")
		For $element In $summary
			If StringLen($element) > 0 Then
				PrintLog2File($silent, "- " & $element)
			EndIf
		Next
	Else
		PrintLog2File($silent, "ERROR: 'Report.exe' not found, please select tool with 'Settings'-'Set report tool'!")
	EndIf

	Return $rc
EndFunc   ;==>GenReport


Func ShowReport()
	If FileExists($gOutFile) Then
		PrintLog("Open >" & $gOutFile & "<")
		ShellExecute($gOutFile)
	Else
		PrintLog("Error: file >" & $gOutFile & "< does not exist!")
	EndIf
EndFunc   ;==>ShowReport
