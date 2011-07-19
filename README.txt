CWMP XML TOOLS README
03/18/2010

---------------------------
Contents of this repository
---------------------------

Report_Tool: directory for source script(s) and executable for William Lupton's CWMP Data Model Report tool
	* report.pl: Perl script
	* report.exe: standalone Windows executable (built using Strawberry Perl)

Threepio: XML parsing/tabling framework by Jeff Houle. Stable build. ("free")
	* src: source
	
TRminator: main directory for Jeff Houle's BBF XML document parser/tabler tool ("non-free")
	* bin: binary jar file(s) for running TRminator "out of the box."
	* doc: documentation directory
		- users_guide: guides to using the user interfaces of TRminator
		- dev_guide: guide to developing Threepio and TRminator
	* src: source directory
		- threepio: source for the XML parsing/tabling framework: MAY differ from other threepio (see above). 
			# Guaranteed to be compatible with current trminator source.
		- trminator: source for the BBF-specific processors and user interfaces that run on top of threepio
	* T2: "JudgementDay" experimental build(s) (to keep from ruining current, "good," rev of TRminator).

ReportGUI: Graphical user interface for Report_Tool
	* ReportGuiSetup.exe: Windows installer including report.exe and ReportGUI

