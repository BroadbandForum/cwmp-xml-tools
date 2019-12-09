SUBDIRS = steve 

all: $(SUBDIRS:%=all-%)
.PHONY: all

all-%:
	make --directory=$* all
.PHONY: all-%

clean: $(SUBDIRS:%=clean-%)
.PHONY: clean

clean-%:
	make --directory=$* clean
.PHONY: clean-%
