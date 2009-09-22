CWMP XML TOOLS README
09/22/2009

---------------------------
Contents of this repository
---------------------------

Report_Tool: directory for source script(s) and executable for William Lupton's CWMP Data Model Report tool
	* report.pl: Perl script
	* report.exe: standalone Windows executable (built using Strawberry Perl)

TRminator: main directory for Jeff Houle's BBF XML document parser/tabler tool
	* bin: binary jar file(s) for running TRminator "out of the box."
	* doc: documentation directory
		- users_guide: guides to using the user interfaces of TRminator
		- dev_guide: guide to developing Threepio and TRminator
	* src: source directory
		- threepio: source for the XML parsing/tabling framework
		- trminator: source for the BBF-specific processors and user interfaces that run on top of threepio