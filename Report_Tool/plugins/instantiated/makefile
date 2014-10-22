MODELDIR = instantiated-data-models
MODELS = $(basename $(notdir \
	            $(wildcard $(MODELDIR)/*.json $(MODELDIR)/*.yaml)))
ERRS = $(MODELS:%=%.err)
TREES = $(MODELS:%=%.tree)
PNGS = $(MODELS:%=%.png)

TR181 = tr-181-2-7-0-php-full.xml
TR135 = tr-135-1-3-0-full.xml
TR140 = tr-140-1-2-0-full.xml
TRS   = $(TR181) $(TR135) $(TR140)

VPATH = $(MODELDIR)

REPORT = ../../report.pl
REPORTFLAGS += --include=../../../data-models/bbf-published
REPORTFLAGS += --include=../../../data-models/cisco-php
REPORTFLAGS += --include=instantiated-data-models
REPORTFLAGS += --plugin=instantiated --report=instantiated
REPORTFLAGS += --quiet

MARKDOWN = /usr/local/bin/pandoc
MARKDOWNFLAGS = --ascii --standalone --toc

MDS = $(wildcard *.md)

HTML = $(MDS:%.md=%.html)

all: $(ERRS) $(TREES) $(PNGS) $(HTML)

ERRRULE = $(REPORT) $(REPORTFLAGS) --configfile=$< --outfile=$@ $(TRS) 
%.err: %.json instantiated.pm; $(ERRRULE)
%.err: %.yaml instantiated.pm; $(ERRRULE)

TREERULE = $(REPORT) $(REPORTFLAGS) --configfile=$< --option dump=tree \
		--outfile=$@ $(TRS) 
%.tree: %.json instantiated.pm; $(TREERULE)
%.tree: %.yaml instantiated.pm; $(TREERULE)

PNGRULE = $(REPORT) $(REPORTFLAGS) --configfile=$< --option dump=ifstack \
		$(TRS) | dot -Tpng >$@
%.png: %.json instantiated.pm; $(PNGRULE)
%.png: %.yaml instantiated.pm; $(PNGRULE)

$(MDS:%.md=%.html): %.html: %.md; $(MARKDOWN) $(MARKDOWNFLAGS) $^ >$@

clean:
	$(RM) $(ERRS) $(TREES) $(PNGS) $(HTML)
