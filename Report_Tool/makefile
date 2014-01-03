# XXX hacked; needs to be de-hacked

# standalone executables and installation
PLATFORM = $(shell uname | tr 'A-Z' 'a-z')
#PLATFORM = exe

# Windows-specific
CYGDRIVE = /cygdrive
PERL = perl
STRAWB = $(CYGDRIVE)/c/strawberry32
STRAWBC = $(STRAWB)/c/bin
STRAWBP = $(STRAWB)/perl/bin
STRAWBS = $(STRAWB)/perl/site/bin
#STRAWBL = $(STRAWB)/c/lib/libxml2.a  $(STRAWB)/c/bin/libxml2-2_.dll  \
#	  $(STRAWB)/c/lib/libiconv.a $(STRAWB)/c/bin/libiconv-2_.dll \
#	  $(STRAWB)/c/lib/libz.a     $(STRAWB)/c/bin/libz_.dll
#STRAWBL = $(STRAWB)/c/bin/libxml2-2_.dll  \
#	  $(STRAWB)/c/bin/libiconv-2_.dll \
#	  $(STRAWB)/c/bin/libz_.dll
STRAWBL = $(STRAWB)/c/bin/libxml2-2_.dll \
	  $(STRAWB)/c/bin/libiconv-2_.dll \
	  $(STRAWB)/c/bin/liblzma-5_.dll \
	  $(STRAWB)/c/bin/zlib1_.dll
WINDIR = $(CYGDRIVE)/c/Windows/system32

# For all targets
#INSTDIR = $(DHOME)/cwmp-xml-tools/Report_Tool
#INSTFILES = report.pl report.pl.info \
#	    report.mk makefile.example \
#	    report.$(PLATFORM) report.$(PLATFORM).info \
#	    README.txt index.html

INSTDIR = $(PWD)
INSTFILES = report.pl.info \
	    README.txt index.html

install: $(INSTFILES:%=$(INSTDIR)/%)

instclean:
	$(RM) $(INSTFILES:%=$(INSTDIR)/%)

$(INSTDIR)/report.pl.info: $(INSTDIR)/report.pl
	-$< --info 2>$@

$(INSTDIR)/report.$(PLATFORM).info: $(INSTDIR)/report.$(PLATFORM)
	-$< --info 2>$@

$(INSTDIR)/README.txt: $(INSTDIR)/report.pl
	-$< --help >$@

$(INSTDIR)/index.html: $(INSTDIR)/report.pl
	pod2html5.12 <$< >$@; /bin/rm -f pod2*.tmp

#$(INSTDIR)/%: %
#	cp -pf $< $@

pp: report.$(PLATFORM)

# XXX no longer maintaining the Cygwin version
report.cygwin: report.pl
	pp -o $@ $<

PERLMODULES = Algorithm::Diff Clone Config::IniFiles Data::Compare XML::LibXML

report.exe.william: report.pl makefile
	(PATH=$(STRAWBC):$(STRAWBP):$(STRAWBS) $(WINDIR)/cmd /C pp -c -x -o $@ $(PERLMODULES:%=-M %) $(STRAWBL:%=-l %) $<)

OSXL = /usr/lib/libxml2.dylib \
       /usr/lib/libiconv.2.dylib \
       /usr/lib/libz.1.dylib
report.darwin: report.pl makefile
	(PATH=/usr/local/bin DYLD_LIBRARY_PATH=/usr/local/lib DYLD_FALLBACK_LIBRARY_PATH= pp -c -x -o $@ $(PERLMODULES:%=-M %) $(OSXL:%=-l %) $<)

# this is one-off after a Strawberry Perl installation
# XXX should include pp (PAR::Packer) here too
strawbinst:
	(PATH=$(STRAWBC):$(STRAWBP) $(WINDIR)/cmd /C cpan -f CPAN $(PERLMODULES))
