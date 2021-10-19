DIRS := $(shell for d in * ; do [ -d $$d -a -f $$d/makefile ] && echo $$d ; done)

DIRS := $(filter-out steve, $(DIRS))

DIRSWT := $(filter WT-%, $(DIRS))

all: $(DIRS:%=all-%)

wt: $(DIRSWT:%=wt-%)

all-% wt-%:
	@echo $*:
	@-make --directory=$* all

snapshot: $(DIRS:%=snapshot-%)

snapshot-%:
	make --directory=$* snapshot

clean: $(DIRS:%=clean-%)

clean-%:
	make --directory=$* clean

.PHONY: all all-% wt wt-% snapshot snapshot-% clean clean-%
