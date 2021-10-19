# do 'make COMPARE=' to see the output (suggest defining a 'makec' alias for this)

# makefiles set TOPDIR to point to here; the tool is in the parent directory
TOOLDIR = $(TOPDIR)/..

# can set DMXMLDIR to be the location of additional XML (it's searched first)

# can set REPORTFLAGS to additional report tool flags
USERREPORTFLAGS := $(REPORTFLAGS)

# this needs to point to directory that contains schemas and support files
INCLUDE = $(TOOLDIR)/../../../install/cwmp

targetdir = out/
expectdir = exp/

REPORT = $(TOOLDIR)/report.pl

REPORTFLAGS += $(DMXMLDIR:%=--include=%)
REPORTFLAGS += $(INCLUDE:%=--include=%)
REPORTFLAGS += --nowarnreport
REPORTFLAGS += --canonical
REPORTFLAGS += --quiet

REPORTXMLFLAGS = --report=xml
REPORTHTMLFLAGS = --report=html
REPORTTEXTFLAGS = --report=text

REPORTDIFFSFLAGS = --diffs --showdiffs

CP = /bin/cp
MKDIR = /bin/mkdir
RM = /bin/rm

DIFF = diff
DIFFFLAGS =

DMXML += $(wildcard *.xml)
ifneq "$(DMFULL)" "false"
  DMFULLXML += $(DMXML:%.xml=$(targetdir)%-full.xml)
endif

DMHTML += $(DMXML:%.xml=$(targetdir)%-diffs.html) \
	  $(DMXML:%.xml=$(targetdir)%.html)
DMFULLHTML += $(DMFULLXML:%.xml=%-diffs.html) \
	      $(DMFULLXML:%.xml=%.html)
DMTEXT +=

vpath %.xml $(DMXMLDIR) $(targetdir)

TARGETS += $(DMHTML) $(DMTEXT) \
	   $(DMFULLXML) $(DMFULLHTML)

PREFIX = $(notdir $(CURDIR))/$(notdir $@):

PROGRESS = echo $(PREFIX)$(USERREPORTFLAGS)

ADDPREFIX = 2>&1 | sed -e 's|^|$(PREFIX)|'

COMPARE = >$@.err 2>&1; \
	  $(DIFF) $(DIFFFLAGS) $(@:$(targetdir)%=$(expectdir)%) $@ $(ADDPREFIX); \
	  $(DIFF) $(DIFFFLAGS) $(@:$(targetdir)%=$(expectdir)%).err $@.err $(ADDPREFIX)

all: mkdir $(TARGETS)

mkdir:
	@$(MKDIR) -p $(targetdir)

$(targetdir)%-full.xml: %.xml
	@$(PROGRESS)
	@-$(REPORT) $(REPORTFLAGS) $(REPORTXMLFLAGS) --outfile=$@ $< $(COMPARE)
.PRECIOUS: $(targetdir)%-full.xml

$(targetdir)%.html: %.xml
	@$(PROGRESS)
	@-$(REPORT) $(REPORTFLAGS) $(REPORTHTMLFLAGS) --outfile=$@ $< $(COMPARE)

$(targetdir)%-diffs.html: %.xml
	@$(PROGRESS)
	@-$(REPORT) $(REPORTFLAGS) $(REPORTDIFFSFLAGS) $(REPORTHTMLFLAGS) --outfile=$@ $< $(COMPARE)

$(targetdir)%-full.html: $(targetdir)%-full.xml
	@$(PROGRESS)
	@-$(REPORT) $(REPORTFLAGS) $(REPORTHTMLFLAGS) --outfile=$@ $< $(COMPARE)
.PRECIOUS: $(targetdir)%-full.html

$(targetdir)%-full-diffs.html: $(targetdir)%-full.xml
	@$(PROGRESS)
	@-$(REPORT) $(REPORTFLAGS) $(REPORTDIFFSFLAGS) $(REPORTHTMLFLAGS) --outfile=$@ $< $(COMPARE)
.PRECIOUS: $(targetdir)%-full-diffs.html

$(targetdir)%.txt: %.xml
	@$(PROGRESS)
	@-$(REPORT) $(REPORTFLAGS) $(REPORTTEXTFLAGS) --outfile=$@ $< $(COMPARE)

$(TARGETS): FORCE
.PHONY: FORCE

clean:
	$(RM) -f $(TARGETS) $(TARGETS:%=%.err)
.PHONY: clean

distclean:
	$(RM) -rf $(targetdir) $(expectdir)
.PHONY: distclean

snapshot:
	$(RM) -rf $(expectdir)
	$(MKDIR) $(expectdir)
	$(CP) -af $(targetdir) $(expectdir)
.PHONY: snapshot
