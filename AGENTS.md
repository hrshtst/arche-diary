# AGENTS.md

This file provides guidance to coding assistant agents when working with code in this repository.

## Commands

```sh
make test       # run the ERT suite (34 tests, ~0.2s)
make compile    # byte-compile arche-diary.el — must finish with no warnings
make clean      # remove *.elc
```

The Makefile expects denote and org under `~/.emacs.d/straight/build/{denote,org}`. Override with `DENOTE_DIR=...` / `ORG_DIR=...` / `EMACS=...` if needed.

Run a single test:

```sh
emacs -Q --batch -L . -L test \
  -L ~/.emacs.d/straight/build/denote \
  -L ~/.emacs.d/straight/build/org \
  -l test/arche-diary-tests.el \
  --eval "(ert-run-tests-batch-and-exit '\"parse-month-offsets\")"
```

The selector is a regexp matched against test names (all named `arche-diary-tests/...`).

## Architecture

Single-file package: all production code lives in `arche-diary.el`, organized top-to-bottom as: customs → time helpers → parsing → file/backend helpers → buffer/heading helpers → public commands → HTML export. Tests are in `test/arche-diary-tests.el` and use a fixture macro (`arche-diary-tests--with-dir`) that rebinds the customs dynamically to a fresh `make-temp-file` directory and cleans up buffers + dir after each test.

Two cross-cutting abstractions matter when editing:

**Backend switch.** `arche-diary-file-creation-system` is `'denote` or `'plain`. Both backends are reached through `arche-diary--month-file` (lookup) and `arche-diary--ensure-monthly-file` (lookup-or-create), which `pcase` on the backend. `arche-diary--find-or-list-month-files` is the canonical listing — it returns `(YEAR MONTH PATH)` triples sorted ascending and is what HTML export, nav, and `--latest-date-globally` consume. For denote, it filters by the *first* element of `arche-diary-denote-keywords` (the others are applied at creation but not used for filtering).

**Argument parsing.** `arche-diary--parse-month` and `arche-diary--parse-date` are the only entry points that accept user-facing arguments. They dispatch on type (nil → today/this-month, symbol, integer, cons/list, string) and the string branch has its own regex cascade. Adding a new accepted format means touching one of these dispatchers *and* the corresponding doc/README; the public commands just pass `month` / `date` straight through. `parse-date` takes `BUFFER-MONTH` to scope bare day strings (`"15"`) and `ALLOW-WEEKDAYS` to enable `'mon..'sun` (allowed in `visit-date` / `fill-dates`, rejected in `add-date`).

**Heading format and regex are paired.** `arche-diary-date-heading-format` controls how a heading is *written*; `arche-diary-date-heading-regexp` controls how every helper *reads* one. If you change the format, the regex's group-1 must still capture an ISO `YYYY-MM-DD`. The whole package — insertion logic, HTML export, fill-dates, latest-date — depends on this contract.

**HTML export does not use `org-html-export-to-html` for the whole file**, because date order and within-day note order must be reversed. Instead, `arche-diary--month-data` walks the Org file with regex matches against the date heading and collects level-2 notes per date in document order, then `arche-diary--month-section-html` reverses both lists and emits HTML. Each note's body is rendered through `arche-diary--org-string-to-html`, which is a thin wrapper around `org-export-string-as ... 'html t` (body-only). This means new Org syntax in notes is rendered correctly, but you must not assume the whole-file Org exporter ran — e.g., `#+OPTIONS` and other file-level keywords are ignored.

**Buffer interactions are careful about leaks.** `arche-diary--latest-date-globally` and `arche-diary-fill-dates` use the `(or (get-file-buffer path) (find-file-noselect path))` pattern and only `kill-buffer` if they were the ones who opened it — preserving the user's existing buffers. Apply this pattern when adding new global-scan operations.

## Conventions

Public symbols are `arche-diary-*`, internal helpers are `arche-diary--*` (double-dash), matching the user's other `arche-*` packages. Interactive commands carry `;;;###autoload`. The package follows the existing `arche-*` style from `~/arche/emacs/arche.el`.

## Repository

Hosted at `git@github.com:hrshtst/arche-diary.git` (public). Main branch is `main`.
