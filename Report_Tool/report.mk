# Copyright (C) 2011, 2012  Pace Plc
# Copyright (C) 2012, 2013  Cisco Systems
# All Rights Reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# - Redistributions of source code must retain the above copyright notice,
#   this list of conditions and the following disclaimer.
# - Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# - Neither the names of the copyright holders nor the names of their
#   contributors may be used to endorse or promote products derived from this
#   software without specific prior written permission.
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

# find report.pl in PATH
# XXX not perfect, e.g. won't find it in a directory whose name includes
#     whitespace, and would find report.pl* too, but good enough
ifndef REPORT
  REPORT = $(firstword $(wildcard \
	     $(patsubst %,%/report.pl,$(subst :, ,$(PATH)))))
endif
ifeq "$(REPORT)" ""
  $(error can\'t find report.pl in PATH)
endif

# REPORTFLAGS can be set in main makefile or passed on command line

# REPORTDIR is the source and destination directory
ifdef REPORTDIR
  REPORTDIR := $(REPORTDIR)/
  REPORTDIR := $(REPORTDIR://=/)
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
              html:-diffs.html:--diffs \
              html:-nop.html:--noprofiles \
              html:-nop-nol.html:--noprofiles_--nolinks \
              html:-upnpdm.html:--upnpdm \
              html:-upnpdm-nol.html:--upnpdm_--nolinks \
              html:-dev-diffs.html:--ignore_Internet_--diffs \
              html:-igd-diffs.html:--ignore_Device_--diffs \
              html:-dev-upnpdm.html:--ignore_Internet_--upnpdm \
              html:-dev-upnpdm-diffs.html:--ignore_Internet_--upnpdm_--diffs \
              html:-igd-upnpdm.html:--ignore_Device_--upnpdm \
              html:-igd-upnpdm-diffs.html:--ignore_Device_--upnpdm_--diffs \
              text:.txt: \
              text:-diffs.txt:--diffs \
	      xml:-can.xml:--canonical \
	      xml:-dt.xml \
	      xml:-dtauto.xml \
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
	      xsd:.xsd \
	      $(REPORTSPECS_EXTRA)

define REPORT_RULE
TEMP_SPEC := $(subst :, ,$(1))
TEMP_SUFF := $$(word 2,$$(TEMP_SPEC))
$(REPORTDIR)%$$(TEMP_SUFF): TEMP_TYPE := $$(word 1,$$(TEMP_SPEC))
$(REPORTDIR)%$$(TEMP_SUFF): TEMP_SUFF := $$(word 2,$$(TEMP_SPEC))
$(REPORTDIR)%$$(TEMP_SUFF): TEMP_OPTS := $$(subst _, ,$$(word 3,$$(TEMP_SPEC)))
$(REPORTDIR)%$$(TEMP_SUFF): $(REPORTDIR)%.xml
	$$(REPORT) $$(REPORTFLAGS) $$($$*_REPORTFLAGS) $$($$*$$(TEMP_SUFF)_REPORTFLAGS) --report=$$(TEMP_TYPE) $$(TEMP_OPTS) --outfile=$$@ $$^ 
REPORTSUFFICES += $(TEMP_SUFF)
endef

REPORTSUFFICES =
$(foreach SPEC,$(REPORTSPECS),$(eval $(call REPORT_RULE,$(SPEC))))

REPORTXML = $(wildcard *.xml)
REPORTDOCS = $(REPORTXML:%.xml=%)

REPORTDEFREPS = %.html %-diffs.html

# this is the default target and will be used if there is no target in the
# calling makefile
$(REPORTDOCS): %: $(REPORTDEFREPS)

.DELETE_ON_ERROR:
