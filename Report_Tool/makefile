# standalone executable is report.$(PLATFORM): darwin, exe, ...
PLATFORM = $(shell uname | tr 'A-Z' 'a-z' | sed -e 's/cygwin.*/exe/')

# Windows-specific
CYGDRIVE = /cygdrive
PERL = perl
STRAWB = $(CYGDRIVE)/c/strawberry32
STRAWBC = $(STRAWB)/c/bin
STRAWBP = $(STRAWB)/perl/bin
STRAWBS = $(STRAWB)/perl/site/bin
STRAWBL = $(STRAWB)/c/bin/libxml2-2_.dll \
	  $(STRAWB)/c/bin/libiconv-2_.dll \
	  $(STRAWB)/c/bin/liblzma-5_.dll \
	  $(STRAWB)/c/bin/zlib1_.dll
WINDIR = $(CYGDRIVE)/c/Windows/system32

# Darwin-specific (OS X)
DARWINL = /usr/lib/libxml2.dylib \
          /usr/lib/libiconv.2.dylib \
          /usr/lib/libz.1.dylib

FILES = report.$(PLATFORM) report.$(PLATFORM).info

# don't assume that can execute ./report.pl under Windows
ifneq "$(PLATFORM)" "exe"
    FILES += report.pl.info README.txt index.html
endif

all: $(FILES)

clean:
	$(RM) $(FILES)

report.pl.info: report.pl
	-./$< --info 2>$@

report.$(PLATFORM).info: report.$(PLATFORM)
	-./$< --info 2>$@

README.txt: report.pl
	-./$< --help >$@

index.html: report.pl
	pod2html5.12 <$< >$@; /bin/rm -f pod2*.tmp

PERLMODULES = Algorithm::Diff Clone Config::IniFiles Data::Compare String::Tokenizer XML::LibXML

report.exe: report.pl
	(PATH=$(STRAWBC):$(STRAWBP):$(STRAWBS) $(WINDIR)/cmd /C pp -c -x -o $@ $(PERLMODULES:%=-M %) $(STRAWBL:%=-l %) $<)

report.darwin: report.pl
	(PATH=/usr/local/bin DYLD_LIBRARY_PATH=/usr/local/lib DYLD_FALLBACK_LIBRARY_PATH= pp -c -x -o $@ $(PERLMODULES:%=-M %) $(DARWINL:%=-l %) $<)

# this is one-off after a Strawberry Perl installation
# XXX should include pp (PAR::Packer) here too
strawbinst:
	(PATH=$(STRAWBC):$(STRAWBP):$(STRAWBS) $(WINDIR)/cmd /C cpan -f CPAN $(PERLMODULES))
