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

`arche-diary-export-html` dispatches on its `MONTH` arg: an explicit month or `'all` force-renders, but **no arg is incremental** — it renders only months where `arche-diary--month-html-stale-p` is true (HTML missing, or source mtime strictly newer than the HTML), and is a true no-op (no `index.html` rebuild, no `arche-diary-after-export-hook`) when nothing is stale. Re-rendering only stale months is safe because nav (`arche-diary--nav-html`, fed `eligible` = months ≤ the page's own month) never links *forward*, so a newer or changed month never invalidates an older page's HTML; a brand-new month is caught as "HTML missing". `index.html` is the only cross-month artifact and derives from the same sources, so "rebuild index iff ≥1 month exported" is complete. The index rebuild + hook + message tail is factored into a `finish` `cl-flet` so every exporting path runs it exactly once and the no-op path bypasses it.

**Image handling spans insertion and export.** `arche-diary-insert-image` copies the source into `arche-diary-image-directory` (under a per-date subdirectory keyed off the date heading point is under, via `arche-diary--enclosing-date-iso`) and inserts a `#+CAPTION:` / `#+NAME: fig:...` / `#+ATTR_HTML:` block plus a `[[file:...]]` link written relative to `arche-diary-directory`. Because Org files live in `arche-diary-directory` but HTML is written to `arche-diary-html-directory`, a single relative path can't resolve from both. The bridge is `arche-diary--rewrite-image-links-for-export`, called from inside `arche-diary--org-string-to-html` (the one chokepoint every exported note body passes through): it copies each referenced image into the html dir mirroring its `images/` subtree and rewrites the link to an html-dir-relative path, keeping the exported folder self-contained. If you add another export path, route image-bearing Org through that same helper. A double prefix to `arche-diary-insert-image` wraps the block in a `#+begin_gallery`/`#+end_gallery` special block (or appends to the one point is inside, located via `arche-diary--gallery-end-position`); Org exports that to `<div class="gallery">`, which the `.gallery` flexbox rule in `arche-diary-html-css` lays out as a wrapping row — so the gallery contract is split between the inserter, plain Org special-block export, and that CSS class. `arche-diary-html-directory` and `arche-diary-image-directory` default to nil and are resolved at call time through the accessors `arche-diary--html-directory` / `arche-diary--image-directory` (nil → the `html/` / `images/` subdir of `arche-diary-directory`). Always read those directories through the accessors, never the customs directly, or the "set only `arche-diary-directory` and the rest follow" contract breaks.

**Buffer interactions are careful about leaks.** `arche-diary--latest-date-globally` uses the `(or (get-file-buffer path) (find-file-noselect path))` pattern and only `kill-buffer`s files it opened itself — preserving the user's existing buffers. Apply this pattern when adding new *read-only* global-scan operations. `arche-diary-fill-dates` is the write-and-show counterpart: it snapshots the user's file buffers up front (`pre-buffers`), opens each month the same way, collects them in `touched`, then `pop-to-buffer-same-window`s the START month with point on its heading. Cleanup is governed by `arche-diary-fill-dates-keep-buffers` — `'all` keeps every touched buffer, `'start` (default) kills the months it opened *except* the start buffer and anything in `pre-buffers`. The `pre-buffers` snapshot (not a per-iteration `get-file-buffer` check) is what makes "did the user already own this?" reliable, because by day 2 of a month `get-file-buffer` returns the buffer we created on day 1. The command's *visible result* — the start buffer — is the one buffer it is allowed to add to the buffer list.

## Conventions

Public symbols are `arche-diary-*`, internal helpers are `arche-diary--*` (double-dash), matching the user's other `arche-*` packages. Interactive commands carry `;;;###autoload`. The package follows the existing `arche-*` style from `~/arche/emacs/arche.el`.

## Repository

Hosted at `git@github.com:hrshtst/arche-diary.git` (public). Main branch is `main`.
