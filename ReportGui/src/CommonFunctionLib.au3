; common function library
; Klaus.wich@nsn.com
#include-once
#include <Array.au3>

Opt('MustDeclareVars', 1)


; compare two stringarrays and return the differences as new seperated string
Func compSeparatedStringDiffs($str1, $str2, $sep)
	Local $resstr, $b, $a, $sl = StringLen($sep)
	If StringLeft($str2, $sl) <> $sep Then
		$str2 = $sep & $str2
	EndIf
	If StringRight($str1, $sl) == $sep Then
		$str1 = StringTrimRight($str1, $sl)
	EndIf
	Local $cmparr = StringSplit($str1 & $str2, $sep, 2)
	_ArraySort($cmparr, 0, 0)
	$a = _ArrayPop($cmparr)
	While UBound($cmparr)
		$b = _ArrayPop($cmparr)
		If $a == $b Then
			$a = _ArrayPop($cmparr)
		Else
			$resstr &= $a & $sep
			$a = $b
		EndIf
	WEnd
	If $a <> "" And $a <> $b Then
		$resstr &= $a & $sep
	EndIf
	Return StringTrimRight($resstr, 1)
EndFunc   ;==>compSeparatedStringDiffs


; returns the differences form the secondto the first string array new seperated string
Func StringinStringDiffs($str1, $str2, $sep)
	Local $resstr
	For $element In StringSplit($str2, $sep, 2)
		If StringInStr($str1, $element) == 0 Then
			$resstr &= $element & $sep
		EndIf
	Next
	Return StringTrimRight($resstr, 1)
EndFunc   ;==>StringinStringDiffs
