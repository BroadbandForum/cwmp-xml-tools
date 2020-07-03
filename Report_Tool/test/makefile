DIRS := $(shell for d in * ; do [ -d $$d -a -f $$d/makefile ] && echo $$d ; done)

DIRS := $(filter-out steve, $(DIRS))

all: $(DIRS:%=all-%)

all-%:
	@echo $*:
	@-make --directory=$* all

snapshot: $(DIRS:%=snapshot-%)

snapshot-%:
	make --directory=$* snapshot

clean: $(DIRS:%=clean-%)

clean-%:
	make --directory=$* clean

.PHONY: all all-% snapshot snapshot-% clean clean-%
