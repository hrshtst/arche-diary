# AGENTS.md

Guidance for coding agents working in this repository. Below, `--name` means `arche-diary--name`, and test names are prefixed `arche-diary-tests/`.

## Commands

```sh
make test       # run the ERT suite
make compile    # byte-compile; must finish with no warnings
make clean      # remove *.elc
```

The Makefile expects denote and org under `~/.emacs.d/straight/build/`; override with `DENOTE_DIR=`, `ORG_DIR=` or `EMACS=`. That Org is a development build, so after touching export code also run `make test ORG_DIR=/nonexistent`, which uses the Org built into Emacs.

Any other batch run that loads the package needs `load-prefer-newer`, or a stale `.elc` makes edits appear to pass. To run one test (the selector is a regexp over test names):

```sh
emacs -Q --batch --eval '(setq load-prefer-newer t)' -L . -L test \
  -L ~/.emacs.d/straight/build/denote \
  -L ~/.emacs.d/straight/build/org \
  -l test/arche-diary-tests.el \
  --eval "(ert-run-tests-batch-and-exit '\"parse-month-offsets\")"
```

## Conventions

- Public symbols are `arche-diary-*`, internal ones `arche-diary--*`. Interactive commands carry `;;;###autoload`.
- A code change updates `arche-diary.el`, the tests and this file in one commit. User-visible behaviour also updates `README.md`, and every defcustom has a README entry.
- This file records non-obvious contracts and their reasons, in a line or two each, not a walk through the functions.
- Commit subjects are imperative with no type prefix, under 70 characters. Bodies are prose explaining why, wrapped at about 72.
- Tests that compare mtimes must use `set-file-times`: there is no clock mocking, and two writes in one tick get equal mtimes.
- `Package-Requires` says Emacs 28.1 but there is no CI, and a newer Emacs won't flag newer APIs, so check an API's version before using it.

## Architecture

All code is in `arche-diary.el` and all tests in `test/arche-diary-tests.el`, whose fixture `arche-diary-tests--with-dir` rebinds the customs to a temporary directory.

### Files and parsing

- **Month files.** Reach both backends through `--month-file` and `--ensure-monthly-file`. List months with `--find-or-list-month-files`, never `--list-month-files`, so an export shares one scan (denote's takes about 0.3s). Denote filters by the first of `arche-diary-denote-keywords` only.
- **Arguments.** `--parse-month` and `--parse-date` are the only entry points for user-facing arguments. A new format changes the dispatcher and its docs.
- **Headings.** Everything reads headings through `arche-diary-date-heading-regexp`, so its group 1 must capture an ISO date whatever `arche-diary-date-heading-format` writes. `--list-month-files` hard-codes `YYYY-MM.org` and `--YYYY-MM__`, and `--current-buffer-month` hard-codes `#+title: YYYY-MM`, whatever the filename and title options say.
- **Directories.** Read the html and image directories through `--html-directory` and `--image-directory`, never the customs, or they stop following `arche-diary-directory`.
- **Buffers.** Read-only scans use `(or (get-file-buffer path) (find-file-noselect path))` and kill only buffers they opened. `arche-diary-fill-dates` snapshots buffers up front instead, because by day 2 `get-file-buffer` returns the buffer it made on day 1.

### Export

- **Not a whole-file export**, because date and note order are reversed. `--read-month-data` walks the file by regexp and each note body goes through `--org-string-to-html`, so file-level keywords such as `#+OPTIONS` are ignored.
- **Exclusion.** The walker runs before any exporter, so it drops level 1-2 headings tagged from `arche-diary-html-noexport-tags` itself (`--heading-excluded-p`). Levels 3+ rely on Org's `org-export-exclude-tags`.
- **Incremental.** With no argument, `arche-diary-export-html` renders only stale months (`--month-html-stale-p`), and with none stale it does nothing, not even the hook. It compares source mtimes, so check a renderer, CSS or option change with `'all` or an explicit month. This is safe because nav never links forward and `index.html` is rebuilt whenever a month is exported.
- **Caches.** `--with-export-caches` memoizes listings and `--month-data` for one export, which is sound only because sources don't change during it.
- **Links section.** The level-1 `arche-diary-links-heading` subtree is parsed by regexp, not the exporter. Date scans ignore it, so it never renders as a body section. A nil heading disables parse, render and seed.
- **External links.** `--external-links-new-tab` rewrites the assembled page as the last step of `--html-document`. Don't do it per note.
- **Math.** `--html-document` loads MathJax itself, only when `--html-math-regexp` matches, because body-only exports get no Org template. `--escape-math-for-html` is needed because Org passes math through raw and a browser reads `a<b` as a tag. Org doesn't read `$…$` as math before a CJK character; that is documented, not worked around.
- **Unfilling.** `--unfill-cjk` works on the source because a pass over HTML can't see across a tag. A break next to a CJK character is dropped; any other becomes one space.
  - Only continuation lines fold, following Org's own rules: for example, a planning keyword only counts right after a heading, and a line ending in a hard break (`\\`) never folds.
  - Where a dropped break would press an emphasis marker against CJK, the separator is `--zero-width-space`, a raw invisible character that looks like `""`. Don't retype it.
  - Add any new line-based syntax to `unfill-does-not-change-non-cjk-rendering`.

### Images

- **Copies.** One relative path can't resolve from both the diary and the html directory, so `--rewrite-image-links-for-export` copies each image and rewrites its link. Any new export path must go through it.
- **Staleness.** `--image-copy-current-p` compares mtime only: a stripped copy differs in size, so a size test would re-strip every image on every export. Images outside the image directory get `--hashed-image-name`, or same-named images would all publish as the first one.
- **Stripping happens at export, never at insertion.** `--copy-image-for-export` is the one path every published image takes, including NO-COPY and hand-written links, and the diary keeps its own metadata as an archive.
- **Originals stay safe.** Only run a stripper on a temporary copy, never on the source. An original must never reach the html directory, because the hook may upload it straight away: a missing program stops the export with a `user-error` before the hook, and a failing one leaves that image out with a `display-warning`.
- **What stays.** The exiftool default keeps only the ICC profile and the orientation tag; ImageMagick can't keep the tag, so its entries use `-auto-orient`. `default-strip-command-keeps-only-orientation` runs the real exiftool. Elsewhere the fixture stubs the stripper, because real ones refuse the suite's fake images. On TIFF, exiftool can't delete IFD0, so make and model survive.
- **Forcing.** `--force-image-copy` is bound only around the requested months' renders, because the index rebuild reads other months too.
- **Galleries.** `--marked-images-in-dired-windows` checks for marks itself, because `dired-get-marked-files` answers with the file at point. The feature spans the inserter, Org's special-block export and the `.gallery` rule in `arche-diary-html-css`.

### Uploads

An export publishes immediately through `arche-diary-after-export-hook`. Exporting never removes files, so `examples/upload-diary` treats a planned deletion as a sign the local folder lost something: it dry-runs first and refuses unless `DIARY_ALLOW_DELETE=1`. Otherwise a single-month export from an empty folder would wipe the site. Its tests use a `file://` fake server.

### Several diaries

- `--in-current-diary`, an `:around` advice, binds the current diary's settings for each command's interactive form and body. **A new command must be added to its list**, or it will write to the wrong diary; `every-command-runs-in-its-diary` fails if it isn't.
- The outermost command decides, through `--active-diary`, because exports run in temporary buffers that belong to no diary. That is why `arche-diary-link-export` isn't advised, and why `.dir-locals.el` can't replace this.
- `--call-in-diary` binds the html and image directories to nil unless the diary sets them, or an export could overwrite and upload another diary's pages.

### Entry links

- `--link-target` finds entries through `--month-entries`, the same reader that renders pages, so links and pages agree on what is published and what an anchor is called.
- `--note-anchors` numbers repeated slugs in document order, so adding a note moves no existing anchor.
- A link with no published target becomes plain text with a warning. `--link-plain-text` never uses the title in the path, which could be a `:noexport:` note's.
- The link type is registered by an autoloaded `with-eval-after-load 'ol` so links work before the package loads, which is why `arche-diary-link-follow` and `arche-diary-link-export` are public and autoloaded. `package-lint` warns about that form; the warning is accepted.
