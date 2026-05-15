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
  :straight (:host github :repo "hrshtst/arche-diary")
  :commands (arche-diary-open-month
             arche-diary-add-date
             arche-diary-visit-date
             arche-diary-fill-dates
             arche-diary-export-html))
```

## Commands

| Command                  | What it does |
|--------------------------|--------------|
| `arche-diary-open-month` | Open (or create) the monthly Org file. Optional `MONTH` argument. |
| `arche-diary-add-date`   | Insert a date heading into the current monthly buffer. |
| `arche-diary-visit-date` | Open the appropriate month and put point at a date heading (creating both if missing). |
| `arche-diary-fill-dates` | Insert headings for every day in a range. |
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

## Customization

| Variable | Default | Purpose |
|---|---|---|
| `arche-diary-directory` | `~/diary` | Where Org files live. |
| `arche-diary-html-directory` | `~/diary/html` | Where HTML is written. |
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

If you customize `arche-diary-date-heading-format` you should also update
`arche-diary-date-heading-regexp` so its first group still captures the ISO
date.

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
