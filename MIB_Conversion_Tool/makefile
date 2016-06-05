# makefile for generating DM XML from ASN/1 MIBs
#
# assumes that libsmi has been installed; I did "brew install libsmi", which
# installs smidump etc to /usr/local/bin, and MIBs to /usr/local/share/mibs

# MIBs distributed with libsmi (also irtf ones but they have lots of problems)
MIBBASE = /usr/local/share/mibs
MIBTYPES = iana ietf tubs

# directories containing additional MIBs
EXTRA += cablelabs
EXTRA += ecosMibs
EXTRA += ieee
EXTRA += ietf
EXTRA += itu

# these MIBs are so bad that we have to exclude them
BADS += RFC1158-MIB
BADS += ESAFE-MIB
BADS += SEC-MIB
BADS += IEEE8021-CFM-MIB

VPATH = $(MIBTYPES:%=$(MIBBASE)/%) $(EXTRA)

EMPTY :=
SMIPATH = $(subst $(empty) $(empty),:,$(VPATH))

MIBS0 = $(notdir $(wildcard $(VPATH:%=%/*)))
MIBS1 = $(notdir $(wildcard $(VPATH:%=%/*~)))
MIBS2 = $(filter-out $(MIBS1), $(MIBS0))
MIBS = $(filter-out $(BADS), $(MIBS2))

MIB2DM  = ./mib2dm.pl --components
SMIDUMP = SMIPATH=$(SMIPATH) smidump --keep-going
PYANG   = pyang --path=yang
REPORT  = ../Report_Tool/report.pl --loglevel=error --nowarnbibref --include=../Data_Models/cwmp-trs --include=xml --report=html

DIRS = xsm xml html yang yin

########################################################################
# all
all: .mkdir xml
.PHONY: all

########################################################################
# rest
rest: .mkdir $(DIRS)

########################################################################
# xsm
xsm: .mkdir.xsm $(MIBS:%=xsm/%.xsm)
.PHONY: xsm

xsm/%.xsm: %
	$(SMIDUMP) --format=xml $< >$@
.PRECIOUS: $(MIBS:%=xsm/%.xsm)

########################################################################
# xml
xml: .mkdir.xml $(MIBS:%=xml/%.xml)
.PHONY: xml

xml/%.xml: xsm/%.xsm
	$(MIB2DM) $< >$@

########################################################################
# html
html: .mkdir.html $(MIBS:%=html/%.html)
.PHONY: html

html/%.html: xml/%.xml
	$(REPORT) $< >$@

########################################################################
# yang
yang: .mkdir.yang $(MIBS:%=yang/%.yang)
.PHONY: yang

# XXX these sed scripts are heuristic based on the fact that names of standard
#     YANG modules appear to have changed and to be inconsistent between
#     smidump v0.4.8 and pyang v1.4.1
yang/%.yang: %
	$(SMIDUMP) --format=yang $< | \
	    sed -e 's/import inet-types/import yang-inet-types/' | \
	    sed -e 's/import yang-smi/import ietf-yang-smiv2/' | \
	    sed -e 's/import yang-types/import ietf-yang-types/' | \
	    sed -e 's/type keyref/type leafref/g' | \
	    cat >$@

########################################################################
# yin
yin: .mkdir.yin $(MIBS:%=yin/%.yin)
.PHONY: yin

# XXX there are various warnings and errors, probably because of the mismatch
#     mentioned above, e.g. keyref
yin/%.yin: yang/%.yang
	-$(PYANG) --format=yin --trim-yin --yin-canonical \
		--yin-pretty-strings $< >$@

# XXX this is how to run pyang to generate a script that can tell OmniGraffle
#     to create a pretty picture; the sed script is work around the assumption
#     that it's OmniGraffle 6
#
# pyang --format=omni IF-MIB.yang | \
#     sed -e 's/application id "com.omnigroup.OmniGraffle6"/ <line break>
#               application "OmniGraffle Professional 5"/' | osascript
#
# (will want a tool to convert YIN to DM, and a BBF Report Tool format or
# plugin to generate YIN -> YANG)

########################################################################
# util
.mkdir:
	mkdir -p $(DIRS)
	touch $@

.mkdir.%:
	mkdir -p $*
	touch $@

########################################################################
# clean
clean:
	$(RM) -rf $(DIRS) .mkdir*
.PHONY: clean
