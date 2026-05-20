# arche-diary

A small Emacs Lisp package for keeping a **private daily diary** in Org mode,
organized one file per month, with a simple HTML export.

## Conventions

- One Org file per month. The file can be created either as plain Org or
  via [denote](https://github.com/protesilaos/denote).
- Each day is a level-1 heading, e.g. `* 2026-05-15 Friday`. Days are written
  top-to-bottom in chronological order.
- Within a day, level-2 headings are short notes, also written top-to-bottom
  in the order events happened.
- Exported HTML reverses both axes: newest day at the top, newest note within
  each day at the top.

## Requirements

- Emacs 28.1+
- Org 9.5+
- denote 3.0+ (hard dependency — required even when using the plain backend)

## Install

Drop `arche-diary.el` somewhere on your `load-path`, or:

```elisp
(use-package arche-diary
  :straight (:host github :repo "hrshtst/arche-diary"))
```

## Commands

| Command                  | What it does |
|--------------------------|--------------|
| `arche-diary-open-month` | Open (or create) the monthly Org file. Optional `MONTH` argument. |
| `arche-diary-add-date`   | Insert a date heading into the current monthly buffer. |
| `arche-diary-visit-date` | Open the appropriate month and put point at a date heading (creating both if missing). |
| `arche-diary-fill-dates` | Insert headings for every day in a range. |
| `arche-diary-insert-image` | Insert an Org image link at point (copying the file by default). |
| `arche-diary-export-html`| Export one month (or all) to HTML and rebuild `index.html`. |

### Accepted argument formats

`MONTH` may be:

- nil — current month
- a non-positive integer — offset (`-1` = last month, `0` = this month)
- an integer 1..12 — that month, this year
- a list `(MONTH)` or `(YEAR MONTH)` or cons `(YEAR . MONTH)`
- the symbols `last-month`, `this-month`
- strings: `"05"`, `"2026-05"`, `"2026/05"`, `"May 2026"`, `"May"`, `"-1"`, `"+2"`

`DATE` may be:

- nil — today
- the symbols `today`, `yesterday`
- an integer — days from today (`-1` = yesterday)
- a list `(YEAR MONTH DAY)`
- strings: `"15"`, `"-1"`, `"+3"`, `"2026-05-15"`, `"1231"`, `"20261231"`,
  `"May 10"`, `"May 10 2026"`
- in `arche-diary-visit-date` and `arche-diary-fill-dates` only, also
  `mon` / `tue` / … / `sun` — most recent occurrence on or before today

`arche-diary-add-date` rejects a date that does not fall in the buffer's
month.

### Inserting images

`arche-diary-insert-image` prompts for an image file and inserts, at point:

```
#+CAPTION:
#+NAME: fig:filename
#+ATTR_HTML: :width 400 :align left
[[file:images/2026-05-15/filename.png]]
```

By default the file is copied into `arche-diary-image-directory`, under a
subdirectory named by the date heading point is currently under (so point
must be inside a day's section). The link is written relative to
`arche-diary-directory`. A single prefix argument (`C-u`) inverts
`arche-diary-image-copy` for that one call (link the original in place
instead of copying, or vice versa); a double prefix argument (`C-u C-u`)
inserts into a gallery (see below). Point is left on the `#+CAPTION:` line
so you can type the caption.

On HTML export, every referenced image is copied into
`arche-diary-html-directory` (mirroring its subtree under `images/`) and the
`<img>` `src` is rewritten so the exported HTML folder is self-contained.

#### Multiple images in a row (galleries)

Inserted images stack vertically (each is its own block). To lay several
side by side, call `arche-diary-insert-image` with a **double prefix
argument** (`C-u C-u`): the image is wrapped in a `#+begin_gallery` ..
`#+end_gallery` block, which the export renders as a wrapping horizontal
row. Invoking it again with `C-u C-u` while point is still inside that
block appends the next image to the same gallery, so a strip is built up
incrementally:

```org
#+begin_gallery
#+CAPTION: morning
#+NAME: fig:a
#+ATTR_HTML: :width 220
[[file:images/2026-05-18/a.png]]

#+CAPTION: noon
#+NAME: fig:b
#+ATTR_HTML: :width 220
[[file:images/2026-05-18/b.png]]
#+end_gallery
```

Each image keeps its own `#+CAPTION:`, `#+NAME:` and `#+ATTR_HTML: :width`,
and the usual copy-into-HTML-dir and `src` rewrite still apply. Gallery
images default to `arche-diary-image-gallery-width` (220) instead of
`arche-diary-image-width` so a row fits; edit any `:width` afterwards to
taste. You can also write the `#+begin_gallery` / `#+end_gallery` wrapper by
hand around ordinary image blocks — the prefix is just a shortcut.

## Customization

| Variable | Default | Purpose |
|---|---|---|
| `arche-diary-directory` | `~/diary` | Where Org files live. |
| `arche-diary-html-directory` | nil | Where HTML is written. nil → `html/` under `arche-diary-directory`. |
| `arche-diary-file-creation-system` | `denote` | `denote` or `plain`. |
| `arche-diary-title-format` | `"%Y-%m"` | `format-time-string` for the file title. |
| `arche-diary-filename-format` | `"%Y-%m.org"` | Plain-Org filename template. |
| `arche-diary-denote-keywords` | `("diary")` | Keywords applied to denote files. |
| `arche-diary-denote-file-type` | `org` | File type passed to `denote`. |
| `arche-diary-date-heading-format` | `"%Y-%m-%d %A"` | Date heading line format. |
| `arche-diary-date-heading-regexp` | (see source) | Must capture the ISO date in group 1. |
| `arche-diary-html-index-recent-count` | `2` | Months embedded directly in `index.html`. |
| `arche-diary-html-page-title` | `"Diary"` | Base `<title>` for HTML pages. |
| `arche-diary-html-lang` | `"en"` | `<html lang>` value. |
| `arche-diary-html-css` | minimal default | CSS embedded in every page. |
| `arche-diary-after-add-date-hook` | nil | Run after adding a date heading. |
| `arche-diary-after-export-hook` | nil | Run after a successful export. |
| `arche-diary-image-copy` | `t` | Copy inserted images vs. link the original. |
| `arche-diary-image-directory` | nil | Where copied images are stored. nil → `images/` under `arche-diary-directory`. |
| `arche-diary-image-date-subdir` | `t` | Copy into a per-date subdirectory. |
| `arche-diary-image-link-type` | `relative` | `relative` (to the diary dir) or `absolute`. |
| `arche-diary-image-width` | `400` | `#+ATTR_HTML: :width` value. |
| `arche-diary-image-gallery-width` | `220` | `:width` for images inserted into a gallery. |
| `arche-diary-image-align` | `left` | `#+ATTR_HTML: :align` (`none` omits it). |

If you customize `arche-diary-date-heading-format` you should also update
`arche-diary-date-heading-regexp` so its first group still captures the ISO
date.

`arche-diary-html-directory` and `arche-diary-image-directory` default to
nil, meaning the `html/` and `images/` subdirectories of
`arche-diary-directory`. These are resolved at call time, so setting only
`arche-diary-directory` is enough — both follow it, whether you set it
before or after the package loads. To place HTML or images elsewhere, set
the corresponding variable to any absolute directory; the two are fully
independent and may live anywhere (HTML export still produces a
self-contained folder). One caveat: when `arche-diary-image-directory` is
outside `arche-diary-directory` and `arche-diary-image-link-type` is
`relative` (the default), inserted links become `../…` paths — correct, but
ugly in the buffer; such setups may prefer
`(setq arche-diary-image-link-type 'absolute)`.

## Deploying the exported HTML

`arche-diary` deliberately ships no upload code; the export step just
writes a self-contained folder under `arche-diary-html-directory`. To
publish it on every export, hook `arche-diary-after-export-hook` to
whatever transfer tool fits your host.

A working sample lives in [`examples/upload-diary`](examples/upload-diary)
— a small `lftp` script that mirrors the HTML folder to an FTPS host
(credentials in `~/.netrc`, strict TLS verification on). See
[`examples/README.md`](examples/README.md) for the quick-start and notes
on adapting it to rsync-over-SSH or other targets.

## Running tests

The package ships an ERT suite under `test/`. Run it with the included
Makefile:

```sh
make test          # run the full ERT suite
make compile       # byte-compile arche-diary.el
make clean         # remove .elc files
```

The Makefile assumes `denote` and `org` are available under
`~/.emacs.d/straight/build/{denote,org}`. Override these paths if you
install elsewhere:

```sh
make test DENOTE_DIR=/path/to/denote ORG_DIR=/path/to/org
```

You can also use a different Emacs binary via `EMACS`:

```sh
make test EMACS=/usr/local/bin/emacs-29
```

To run the suite by hand without `make`:

```sh
emacs -Q --batch \
  -L . -L test \
  -L ~/.emacs.d/straight/build/denote \
  -L ~/.emacs.d/straight/build/org \
  -l test/arche-diary-tests.el \
  -f ert-run-tests-batch-and-exit
```

You can also load `test/arche-diary-tests.el` in a regular Emacs session
and use `M-x ert RET t RET` to run the suite interactively.

Each test creates its own temporary directory and cleans up after itself,
so the suite never touches your real `arche-diary-directory`.
