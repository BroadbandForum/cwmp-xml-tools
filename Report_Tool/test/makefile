DIRS = $(shell for d in * ; do [ -d $$d -a -f $$d/makefile ] && echo $$d ; done)

all: $(DIRS:%=all-%)

all-%:
	make --directory=$* all

snapshot: $(DIRS:%=snapshot-%)

snapshot-%:
	make --directory=$* snapshot

clean: $(DIRS:%=clean-%)

clean-%:
	make --directory=$* clean

.PHONY: all all-% snapshot snapshot-% clean clean-%
