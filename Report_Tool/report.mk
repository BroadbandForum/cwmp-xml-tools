# Copyright (C) 2011, 2012  Pace Plc
# All Rights Reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# - Redistributions of source code must retain the above copyright notice,
#   this list of conditions and the following disclaimer.
# - Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# - Neither the name of Pace Plc nor the names of its contributors may be
#   used to endorse or promote products derived from this software without
#   specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

# report.pl make rules
# XXX can now remove support for -all.xml and -last.html

# find report.pl in PATH
# XXX not perfect, e.g. won't find it in a directory whose name includes
#     whitespace, and would find report.pl* too, but good enough
REPORT = $(firstword $(wildcard \
	   $(patsubst %,%/report.pl,$(subst :, ,$(PATH)))))
ifeq "$(REPORT)" ""
  $(error can\'t find report.pl in PATH)
endif

# REPORTFLAGS can be set in main makefile or passed on command line
ifndef REPORTFLAGS
REPORTFLAGS =
endif

# type:suff:opts (use _ in place of space in opts)
# XXX could auto-generate REPORTSPECS to give various combinations
REPORTSPECS = html:.html \
	      html:-ugly.html:--ugly \
	      html:-synt.html:--showsyntax \
	      html:-nol.html:--nolinks \
	      html:-nolh.html:--nolinks_--nohyphenate \
	      html:-dev.html:--ignore_Internet \
              html:-igd.html:--ignore_Device \
              html:-last.html:--lastonly_--showdiffs \
              html:-diffs.html:--lastonly_--showdiffs \
              html:-nop.html:--noprofiles \
              html:-nop-nol.html:--noprofiles_--nolinks \
              html:-upnpdm.html:--upnpdm \
              html:-upnpdm-nol.html:--upnpdm_--nolinks \
              html:-dev-diffs.html:--ignore_Internet_--lastonly_--showdiffs \
              html:-igd-diffs.html:--ignore_Device_--lastonly_--showdiffs \
              html:-dev-upnpdm.html:--ignore_Internet_--upnpdm \
              html:-dev-upnpdm-diffs.html:--ignore_Internet_--upnpdm_--lastonly_--showdiffs \
              html:-igd-upnpdm.html:--ignore_Device_--upnpdm \
              html:-igd-upnpdm-diffs.html:--ignore_Device_--upnpdm_--lastonly_--showdiffs \
              text:.txt: \
              text:-diffs.txt:--lastonly_--showdiffs \
	      xml:-can.xml:--canonical \
	      xml:-dt.xml \
	      xml:-all.xml \
	      xml:-full.xml \
	      xml:-full-comps.xml:--components \
	      xml:-full-ocomp.xml:--components_--noparameters \
	      xml:-full-pcomp.xml:--components_--noobjects \
	      xml:-full-nop.xml:--noprofiles \
	      xml:-full-nop-comps.xml:--noprofiles_--components \
	      xml:-full-nop-ocomp.xml:--noprofiles_--components_--noparameters \
	      xml:-full-nop-pcomp.xml:--noprofiles_--components_--noobjects \
	      wiki:.wiki \
	      xls:.xls \
	      xsd:.xsd

define REPORT_RULE
TEMP_SPEC := $(subst :, ,$(1))
TEMP_SUFF := $$(word 2,$$(TEMP_SPEC))
%$$(TEMP_SUFF): TEMP_TYPE := $$(word 1,$$(TEMP_SPEC))
%$$(TEMP_SUFF): TEMP_SUFF := $$(word 2,$$(TEMP_SPEC))
%$$(TEMP_SUFF): TEMP_OPTS := $$(subst _, ,$$(word 3,$$(TEMP_SPEC)))
%$$(TEMP_SUFF): %.xml $$(REPORT)
	$$(REPORT) $$(REPORTFLAGS) $$($$*_REPORTFLAGS) $$($$*$$(TEMP_SUFF)_REPORTFLAGS) --report=$$(TEMP_TYPE) $$(TEMP_OPTS) --outfile=$$@ $$*.xml 
REPORTSUFFICES += $(TEMP_SUFF)
endef

REPORTSUFFICES =
$(foreach SPEC,$(REPORTSPECS),$(eval $(call REPORT_RULE,$(SPEC))))

XML = $(wildcard *.xml)
DOCS = $(XML:%.xml=%)

DEFREPS = %.html %-diffs.html

# this is the default target and will be used if there is no target in the
# calling makefile
$(DOCS): %: $(DEFREPS)

$(DOCS:%=%-dev): %: $(DEFREPS)

$(DOCS:%=%-igd): %: $(DEFREPS)

$(DOCS:%=%-both): %-both: %-dev %-igd

.DELETE_ON_ERROR:
