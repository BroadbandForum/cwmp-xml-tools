# standalone executable is report.darwin, .linux, .linux32, .exe, ...
KERNEL = $(shell uname -s | tr 'A-Z' 'a-z' | sed -e 's/cygwin.*/exe/' -e 's/mingw32.*/exe/')
MACHINE = $(shell uname -m | tr 'A-Z' 'a-z' | sed  -e 's/i.86/32/' -e 's/x86_64//')
PLATFORM = $(KERNEL)$(MACHINE)

ifeq (exe32, $(PLATFORM))
    PLATFORM = exe
endif

# Windows-specific
# XXX should use the 32-bit version in order to maximise applicability
ifneq (,$(findstring cygwin,$(shell uname -s | tr 'A-Z' 'a-z')))
    CYGDRIVE = /cygdrive
else
    CYGDRIVE = 
endif
PERL = perl
STRAWB = $(CYGDRIVE)/c/strawberry32
STRAWBC = $(STRAWB)/c/bin
STRAWBP = $(STRAWB)/perl/bin
STRAWBS = $(STRAWB)/perl/site/bin
STRAWBL = $(STRAWB)/c/bin/libxml2-2_.dll \
	  $(STRAWB)/c/bin/libiconv-2_.dll \
	  $(STRAWB)/c/bin/liblzma-5_.dll \
	  $(STRAWB)/c/bin/zlib1_.dll
WINDIR = $(CYGDRIVE)/c/Windows/System32

# Darwin-specific (OS X)
DARWINL = /usr/lib/libxml2.dylib \
          /usr/lib/libiconv.2.dylib \
          /usr/lib/libz.1.dylib

# Linux-specific
LINUXL = /usr/lib/libxml2.so \
         /usr/lib/libiconv.2.so \
         /usr/lib/libz.1.so

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
	pod2html5.18 <$< >$@; /bin/rm -f pod2*.tmp

PERLMODULES = Algorithm::Diff Clone Config::IniFiles Data::Compare String::Tokenizer XML::LibXML

report.exe: report.pl
	(PATH=$(STRAWBC):$(STRAWBP):$(STRAWBS) pp -c -x -o $@ $(PERLMODULES:%=-M %) $(STRAWBL:%=-l %) $<)

report.darwin: report.pl
	(PATH=/usr/local/bin DYLD_LIBRARY_PATH=/usr/local/lib DYLD_FALLBACK_LIBRARY_PATH= pp -c -x -o $@ $(PERLMODULES:%=-M %) $(DARWINL:%=-l %) $<)

report.linux report.linux32: report.pl
	(PATH=/usr/local/bin LD_LIBRARY_PATH=/usr/local/lib pp -c -x -o $@ $(PERLMODULES:%=-M %) $(LINUXL:%=-l %) $<)

# this is one-off after a Strawberry Perl installation
# XXX have removed CPAN from the list; maybe it was causing problems but
#     there is something wrong with the environment (do in Command Prompt)
strawbinst:
	(PATH=$(STRAWBC):$(STRAWBP):$(STRAWBS) $(WINDIR)/cmd /C cpan -f $(PERLMODULES) PAR::Packer)
