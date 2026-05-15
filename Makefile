EMACS ?= emacs
DENOTE_DIR ?= $(HOME)/.emacs.d/straight/build/denote
ORG_DIR   ?= $(HOME)/.emacs.d/straight/build/org

LOAD_PATH = -L . -L test
ifneq ($(wildcard $(DENOTE_DIR)/.),)
  LOAD_PATH += -L $(DENOTE_DIR)
endif
ifneq ($(wildcard $(ORG_DIR)/.),)
  LOAD_PATH += -L $(ORG_DIR)
endif

.PHONY: all test compile clean

all: compile

test:
	$(EMACS) -Q --batch $(LOAD_PATH) \
		-l test/arche-diary-tests.el \
		-f ert-run-tests-batch-and-exit

compile:
	$(EMACS) -Q --batch $(LOAD_PATH) \
		-f batch-byte-compile arche-diary.el

clean:
	rm -f *.elc test/*.elc
