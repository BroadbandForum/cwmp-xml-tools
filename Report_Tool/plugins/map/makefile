DIFF = diff

REPORT = ../../report.pl
REPORT_MK = ../../report.mk

REPORTFLAGS += --include=../../../Data_Models/cwmp-trs

MARKDOWN = /usr/local/bin/pandoc
MARKDOWNFLAGS = --ascii --standalone --toc

MAPTEXT = tr98map.txt
MAPXML  = tr98map.xml

MDS = $(wildcard *.md)

#HTML = $(MAPXML:%.xml=%.html) $(MDS:%.md=%.html)
HTML = $(MDS:%.md=%.html)

#all: $(MAPTEXT) $(MAPXML) $(HTML)
all: $(MAPTEXT) $(HTML)

$(MDS:%.md=%.html): %.html: %.md; $(MARKDOWN) $(MARKDOWNFLAGS) $^ >$@

tr98map.txt: map.pm tr98map.ini
	$(REPORT) $(REPORTFLAGS) --plugin map --report=map \
	    --option mode=text --configfile=tr98map.ini \
	    --outfile=tr98map.txt tr-098-1-6.xml tr-181-2-6.xml 

# XXX this is interesting (maybe) but needs more thought re what it
#     really "IS" (so it is not built by default)
tr98map.xml: map.pm tr98map.ini
	$(REPORT) $(REPORTFLAGS) --plugin map --report=map \
	    --option mode=xml --configfile=tr98map.ini \
	    --outfile=tr98map.xml tr-098-1-6.xml tr-181-2-6.xml 

# can override diff tool with DIFF=tool on the command line
diff: tr98map.txt
	$(DIFF) ../tr98map/tr98map.txt tr98map.txt

CLEAN = $(MAPTEXT) $(MAPXML) $(HTML)
clean:
	$(RM) $(CLEAN)

include $(REPORT_MK)

.DELETE_ON_ERROR:
