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
LINUXL = /usr/lib/libxml2.so.2 \
         /usr/lib/libiconv_hook.so.1 \
         /lib/libz.so.1

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

# find pod2html in PATH
POD2HTML = $(lastword $(wildcard \
             $(patsubst %,%/pod2html*,$(subst :, ,$(PATH)))))
ifeq "$(POD2HTML)" ""
  $(error can\'t find pod2html* in PATH)
endif

index.html: report.pl
	$(POD2HTML) <$< >$@; /bin/rm -f pod2*.tmp

# XXX these are modules that might need to be installed via CPAN in order to
#     execute report.pl; it seems that recent Perl distributions include
#     Algorithm::Diff Clone and XML::LibXML, so these probably aren't
#     necessary
# XXX these modules used to be expicitly included in standalone executables
#     but this no longer seems to be necessary
PERLMODULES = Algorithm::Diff Clone Config::IniFiles Data::Compare \
	      String::Tokenizer XML::LibXML

# XXX this was an experiment that failed; for some reason it is sometimes
#     necessary to force various UTF-8 files to be included; using
#     'pp -M utf8' doesn't work; need to put 'use utf8;' into the Perl
#PERLMODULES2 = utf8

# XXX can't get the PATH stuff working under Windows
report.exe: report.pl
	cmd \/C pp -c -x -o $@ $(PERLMODULES2:%=-M %) $(STRAWBL:%=-l %) $<

#	(PATH=$(STRAWBC):$(STRAWBP):$(STRAWBS) pp -c -x -o $@ $(PERLMODULES:%=-M %) $(STRAWBL:%=-l %) $<)

report.darwin: report.pl
	(PATH=/usr/local/bin DYLD_LIBRARY_PATH=/usr/local/lib DYLD_FALLBACK_LIBRARY_PATH= pp -c -x -o $@ $(PERLMODULES2:%=-M %) $(DARWINL:%=-l %) $<)

report.linux report.linux32: report.pl
	(PATH=/usr/local/bin LD_LIBRARY_PATH=/usr/local/lib pp -c -x -o $@ $(PERLMODULES2:%=-M %) $(LINUXL:%=-l %) $<)

# this is one-off after a Strawberry Perl installation
# XXX better to do by hand using the Strawberry cpan client
# XXX or use pp rather than PAR::Packer? what is the difference?
strawbinst:
	@echo cpan -f $(PERLMODULES) PAR::Packer

#	(PATH=$(STRAWBC):$(STRAWBP):$(STRAWBS) $(WINDIR)/cmd \/C cpan -f $(PERLMODULES) PAR::Packer)
