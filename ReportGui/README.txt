ReportGUI:
==========

This utility provides a graphical frontend for the "report.exe" tool to generate reports from CWMP 
xml data files.

The windows installer includes the frontend and the report.exe tool. For installation please 
execute the ReportGuiSetup and follow the instructions. The tool runs under Windows (XP, Vista, 7)
and with some effort under MACOS with Wine

For questions and comments please contact klaus.wich@axiros.com


History
--------
11/25/2012 ReportGuiSetup 2.4, ReportGui 2.4, report.exe#209 (report.pl#209)
	new ReportGui version 2.4:
	- Changed functions:
	  * Sort report setting default is now "False"
	  * Setting "set report tool" now allows also to select the perl script directly
	  * Icons and colors adapted
	  * Other option field length limit removed
	- New functions:
	  * New Option Extras->"Create CWMP Index page" to create index pages according to OD-290 
	    during publishing (report.hmlbbf)
	    The creation can also be included in the publishing automatically with the settings 
	    Extras->"Include CWMP Index page in publish all files"
	    
04/13/2012 ReportGuiSetup 2.3, ReportGui 2.3, report.exe#209 (report.pl#209)
	new version of report.exe (report.pl#209) included in installer
	new ReportGui version 2.3:
	- New functions:
	  * New setting to sort reports. If enabled all reports will be generated with the 
	    --sortobjects option availabe with report.exe#209. Option defaults to "True"
	  * Support for plugins in the Expert mode. Plugins can in the <programdir>\plugins directory 
	    be selected via drop down list to be executed during report generation
	
02/29/2012 ReportGuiSetup 2.2, ReportGui 2.2, report.exe#206 (report.pl#206)
	new ReportGui version 2.2:
	- Changed functions:
	  * HTML report functions now generates generic HTML with the --nomodels --automodel 
	    option for component models
	  * Publish uses option -loglevel=w1 for all reports
	  * Publish additional generates generic HTML with the --nomodels --automodel option 
	    for component models
	  * Publish log includes program version
	  * new formatted output, differentiated by error, warning, indent
	  * Select new report tool: confirmation in log file
	  * improved windows resize to adapt to screen, keep item positions, minimum size 500x580
	- New functions:
	  * log level can be selected in panel, output split depending on log level
	  * New option: Check for new file from BBF home page
	- Fixed Error(s):
	  * Capital spelling for options Showdiffs and Lastonly removed

12/09/2011 ReportGuiSetup 2.1, ReportGui 2.1, report.exe#198 (report.pl#198)
	new version of report.exe (report.pl#198) included in installer
	bug fixes and enhancements:
	* perform report tool updates with admin rights
	* compact command output for readability, new option to show command string
	* input field for additional include directories extended 
	* Publish all does not work from any directory due to missing include of own directory
	* time stamps for generation
	* new naming conventions for generated xmls: last becomes diffs and all becomes full
	* new Setting "Use Old xml names" to switch back to old naming conventions
	* automatic adaptation of window height to vertical screen size

08/15/2011 ReportGuiSetup 2.0, ReportGui 2.0, report.exe#186 (report.pl#186)
	new version of report.exe (report.pl#186) included in installer
	new ReportGui version 2.0:
	- Changed functions:
	  * ReportGui now runs with user rights under Windows 7, Ini file was moved into %USER/appdata 
	    directory
	  * Deprecated 'noautomodel' option replaced with new option 'automodel'
	  * 'ShowDiffs' option added to expert mode and as option to standard html reports
	  * Report.exe output separated for errors and statistics
	  * New setting to show or hide statistic display
	  * Publish option also generates flattened xml file
	
	- New functions:
	  * New option to download all released xml and schema files from BBF website into default
	    include directory
	  * New upgrade option to check for new versions
	  * "Publish all files" option to generate files to be published for a whole directory
	  * New feedback option
	  
	- Fixed Error(s): 
	  * Error checking crashed program, due to variable error

02/24/2011 ReportGuiSetup 1.0.6, ReportGui 1.1, report.exe (report.pl#182)
	new version of report.exe (report.pl#182) included in installer.

02/11/2011 ReportGuiSetup 1.0.5, ReportGui 1.1, report.exe (report.pl#181) 
	Update ReportGUI 1.1 :
	- New standard report options to compare two files
	- Improved handling of include directories, possible to sort list. 
	- prevent overwrite of source xml for xml targets in expert handling

01/25/2011 ReportGuiSetup 1.0.4, ReportGui 1.0.2
	new version of report.exe (report.pl#181) included in installer. 
	Error correction in ReportGUI: Include directories and filenames with spaces are now correctly processed

11/20/2010 ReportGuiSetup 1.0.3, ReportGui 1.0.1
	new version of report.exe (report.pl#177) included in installer. 
	
10/14/2010 ReportGuiSetup 1.0.2, ReportGui 1.0.1
	new version of report.exe (report.pl#175) included in installer. 
	Installer will now override report.exe during reinstall if it includes newer version.

10/08/2010 ReportGuiSetup 1.0.1, ReportGui 1.0.1 
	new version of report.exe (report.pl#174) included in installer. 
	Please uninstall old version first.