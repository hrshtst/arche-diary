;;; arche-diary.el --- Private monthly diary in Org mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Hiroshi Atsuta

;; Author: Hiroshi Atsuta <atsuta.hiroshi@gmail.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1") (org "9.5") (denote "3.0"))
;; Optional: htmlize (syntax-highlighted code blocks in HTML export)
;; Keywords: convenience, calendar
;; URL: https://github.com/hrshtst/arche-diary

;; This file is NOT part of GNU Emacs.

;;; Commentary:

;; arche-diary helps you keep a private monthly diary in Org mode and
;; export it to a simple HTML site.  See README.md for usage.

;;; Code:

(require 'cl-lib)
(require 'denote)
(require 'org)
(require 'ox-html)
(require 'parse-time)
(require 'seq)
(require 'subr-x)
(require 'htmlize nil t)


;;; Customization

(defgroup arche-diary nil
  "Private monthly diary in Org mode."
  :group 'applications
  :prefix "arche-diary-"
  :link '(url-link :tag "GitHub" "https://github.com/hrshtst/arche-diary"))

(defcustom arche-diary-directory (expand-file-name "diary" "~")
  "Directory where monthly diary Org files live."
  :group 'arche-diary
  :type 'directory)

(defcustom arche-diary-html-directory nil
  "Directory where exported HTML files are written.
When nil, the `html' subdirectory of `arche-diary-directory' is
used (resolved at call time, so it tracks `arche-diary-directory').
Set it to any absolute directory to write HTML elsewhere."
  :group 'arche-diary
  :type '(choice (const :tag "html/ under the diary directory" nil)
                 directory))

(defcustom arche-diary-file-creation-system 'denote
  "Backend used to create new monthly diary files.
Either the symbol `denote' (use the denote package) or `plain'
\(create plain Org files)."
  :group 'arche-diary
  :type '(choice (const :tag "denote" denote)
                 (const :tag "Plain Org" plain)))

(defcustom arche-diary-title-format "%Y-%m"
  "`format-time-string' template for monthly file titles."
  :group 'arche-diary
  :type 'string)

(defcustom arche-diary-filename-format "%Y-%m.org"
  "`format-time-string' template for plain-Org monthly filenames.
Ignored when `arche-diary-file-creation-system' is `denote'."
  :group 'arche-diary
  :type 'string)

(defcustom arche-diary-denote-keywords '("diary")
  "Keywords applied to monthly files created with denote.
The first element is also used to recognize diary files when
listing existing months."
  :group 'arche-diary
  :type '(repeat string))

(defcustom arche-diary-denote-file-type 'org
  "File type passed to `denote' when creating a monthly file."
  :group 'arche-diary
  :type 'symbol)

(defcustom arche-diary-date-heading-format "%Y-%m-%d %A"
  "`format-time-string' template for the 1st-level date heading."
  :group 'arche-diary
  :type 'string)

(defcustom arche-diary-date-heading-regexp
  "^\\* \\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)\\b"
  "Regexp matching a 1st-level date heading.
Group 1 must capture the ISO date (YYYY-MM-DD)."
  :group 'arche-diary
  :type 'regexp)

(defcustom arche-diary-links-heading "Links"
  "Text of the level-1 heading holding the month's useful links.
Keep this heading at the top of each monthly file, above the date
headings, with the links written as an ordinary Org list beneath
it, e.g.

  * Links
  - [[https://example.com][Some conference]]
  - [[https://journal.example.com/login][Journal login]]

The links are rendered into the page header on HTML export (each
month page shows its own links; `index.html' shows the latest
month's), and the whole subtree is carried over verbatim when a
new monthly file is created.  Because it is not a date heading it
is otherwise ignored by parsing and export.  Set to nil to
disable the feature entirely."
  :group 'arche-diary
  :type '(choice (const :tag "Disabled" nil) string))

(defcustom arche-diary-fill-dates-keep-buffers 'start
  "Which monthly buffers `arche-diary-fill-dates' leaves open.
When a range spans several months the command opens a buffer per
month.  This controls which of those it keeps afterwards:

  `start'  Keep only the START month's buffer (the one point lands
           in); save and kill the other months it opened.
  `all'    Keep every monthly buffer it opened.

Either way, buffers the user already had open are never killed."
  :group 'arche-diary
  :type '(choice (const :tag "Only the start month" start)
                 (const :tag "Every touched month" all)))

(defcustom arche-diary-html-index-recent-count 2
  "Number of recent months embedded directly in `index.html'."
  :group 'arche-diary
  :type 'integer)

(defcustom arche-diary-html-page-title "Diary"
  "Base title of exported HTML pages."
  :group 'arche-diary
  :type 'string)

(defcustom arche-diary-html-lang "en"
  "Value of the `lang' attribute on exported <html> elements."
  :group 'arche-diary
  :type 'string)

(defcustom arche-diary-html-unfill-cjk t
  "When non-nil, join hard-wrapped CJK lines during HTML export.
Diary source kept under a small `fill-column' wraps long CJK
paragraphs across several lines.  Org's HTML export turns each
in-paragraph newline into a space, which is visible and wrong in
scripts such as Japanese or Chinese that have no inter-word
spaces.  With this enabled, a line break is dropped on export
whenever a CJK character sits on either side of it; a break
between two non-CJK words still becomes a single space, and code
blocks are left untouched.  The Org files themselves are never
modified."
  :group 'arche-diary
  :type 'boolean)

(defcustom arche-diary-html-external-links-new-tab t
  "When non-nil, make external links open in a new browser tab.
Every exported `<a>' whose href is an absolute http(s) URL gets
`target=\"_blank\"' and `rel=\"noopener\"' added, covering both the
header link list and links written inside diary notes.  Relative
links — page navigation, the title link, images — are left alone,
so they keep opening in place."
  :group 'arche-diary
  :type 'boolean)

(defcustom arche-diary-html-links-separator " | "
  "String placed between consecutive links in the header link list.
Inserted verbatim between the rendered `<a>' elements, so it can
be any visible divider, e.g. \" | \" or \" / \"."
  :group 'arche-diary
  :type 'string)

(defcustom arche-diary-html-noexport-tags '("noexport")
  "Org heading tags that exclude a heading from HTML export.
A date heading (level 1) or note heading (level 2) carrying any of
these tags as a trailing `:tag:' is omitted entirely from the
exported HTML, along with everything beneath it.  Subheadings
*inside* a note body are handled by Org's own exporter via
`org-export-exclude-tags', so keeping the default \"noexport\"
here makes the same tag work uniformly at every heading level.
Set to nil to disable heading-level exclusion."
  :group 'arche-diary
  :type '(repeat string))

(defcustom arche-diary-html-css "\
:root { --fg:#222; --bg:#fff; --muted:#888; --link:#366; }
body { margin:2rem auto; max-width:40rem; padding:0 1rem;
       font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
       color:var(--fg); background:var(--bg); line-height:1.6; }
h1,h2,h3 { font-weight:600; }
h1 { font-size:1.6rem; margin-top:2rem; }
h2 { font-size:1.2rem; }
h3 { font-size:1.0rem; color:var(--muted); }
a { color:var(--link); text-decoration:none; }
a:hover { text-decoration:underline; }
nav { margin:0 0 1rem 0; font-size:.9rem; color:var(--muted);
      line-height:1.8; word-break:break-all; }
nav.links { margin:0 0 1rem 0; word-break:normal; overflow-wrap:anywhere; }
nav.links a { color:var(--link); }
hr { border:0; border-top:1px solid #ddd; margin:1.5rem 0; }
hr.note-sep { border-top:1px dashed #eee; margin:.25rem 0; }
article.date { margin-bottom:1rem; }
section.note { margin:.25rem 0; }
section.note h3 { margin:.25rem 0; }
section.note p { margin:.5rem 0; }
img { max-width:100%; height:auto; }
.figure { margin:1rem 0; display:flow-root; }
.figure p { margin:.3rem 0; }
.figure-number { color:var(--muted); font-style:italic; }
/* Org maps #+ATTR_HTML :align onto the deprecated `align' attribute,
   which browsers render as a float and makes images overlap the text
   that follows.  Treat it as block alignment instead. */
.figure img, section.note img { float:none; display:block;
  margin:.3rem 0; }
img[align=\"left\"]   { margin-right:auto; }
img[align=\"center\"] { margin-left:auto; margin-right:auto; }
img[align=\"right\"]  { margin-left:auto; }
section.note { display:flow-root; }
.gallery { display:flex; flex-wrap:wrap; gap:1rem;
           align-items:flex-end; margin:1rem 0; }
.gallery .figure { margin:0; }
"
  "CSS embedded in every exported HTML page."
  :group 'arche-diary
  :type 'string)

(defcustom arche-diary-after-add-date-hook nil
  "Hook run after `arche-diary-add-date' inserts a date heading."
  :group 'arche-diary
  :type 'hook)

(defcustom arche-diary-after-export-hook nil
  "Hook run after a successful HTML export."
  :group 'arche-diary
  :type 'hook)

(defcustom arche-diary-image-copy t
  "If non-nil, copy inserted images into `arche-diary-image-directory'.
When nil, `arche-diary-insert-image' links the original file in place.
A prefix argument to `arche-diary-insert-image' inverts this."
  :group 'arche-diary
  :type 'boolean)

(defcustom arche-diary-image-directory nil
  "Directory under which `arche-diary-insert-image' copies images.
When nil, the `images' subdirectory of `arche-diary-directory' is
used (resolved at call time, so it tracks `arche-diary-directory').
Set it to any absolute directory to store images elsewhere."
  :group 'arche-diary
  :type '(choice (const :tag "images/ under the diary directory" nil)
                 directory))

(defcustom arche-diary-image-date-subdir t
  "If non-nil, copy images into a subdirectory named by their date.
The date is taken from the diary date heading point is under."
  :group 'arche-diary
  :type 'boolean)

(defcustom arche-diary-image-link-type 'relative
  "How `arche-diary-insert-image' writes the inserted file link.
Either `relative' (to `arche-diary-directory') or `absolute'."
  :group 'arche-diary
  :type '(choice (const :tag "Relative to diary directory" relative)
                 (const :tag "Absolute" absolute)))

(defcustom arche-diary-image-width 400
  "Default value written as `#+ATTR_HTML: :width' for inserted images."
  :group 'arche-diary
  :type '(choice integer string))

(defcustom arche-diary-image-gallery-width 220
  "Default `#+ATTR_HTML: :width' for images inserted into a gallery.
Used instead of `arche-diary-image-width' when
`arche-diary-insert-image' inserts into a `#+begin_gallery' block,
so several images fit on one row.  Edit per image afterwards."
  :group 'arche-diary
  :type '(choice integer string))

(defcustom arche-diary-image-align 'left
  "Default `#+ATTR_HTML: :align' for inserted images.
The symbol `none' omits the `:align' attribute entirely."
  :group 'arche-diary
  :type '(choice (const left) (const center) (const right) (const none)))


;;; Time helpers

(defun arche-diary--decode (time)
  "Return decoded-time list for TIME."
  (decode-time time))

(defun arche-diary--time-for-day (year month day)
  "Return an encoded time at midnight of YEAR/MONTH/DAY."
  (encode-time (list 0 0 0 day month year nil -1 nil)))

(defun arche-diary--time-to-iso (time)
  "Return ISO YYYY-MM-DD string for TIME."
  (format-time-string "%Y-%m-%d" time))

(defun arche-diary--time-to-month (time)
  "Return (YEAR . MONTH) cons for TIME."
  (let ((dec (arche-diary--decode time)))
    (cons (decoded-time-year dec) (decoded-time-month dec))))

(defun arche-diary--add-months-to (year month delta)
  "Return (YEAR . MONTH) advanced by DELTA whole months."
  (let* ((total (+ (* year 12) (- month 1) delta))
         (ny (/ total 12))
         (nm (1+ (mod total 12))))
    (cons ny nm)))

(defun arche-diary--day-after-iso (iso)
  "Return time value for the day after ISO date string."
  (let* ((parts (split-string iso "-"))
         (y (string-to-number (nth 0 parts)))
         (m (string-to-number (nth 1 parts)))
         (d (string-to-number (nth 2 parts))))
    (encode-time
     (decoded-time-add (list 0 0 0 d m y nil -1 nil)
                       (make-decoded-time :day 1)))))

(defun arche-diary--weekday-symbol-to-time (sym)
  "Return time for the latest day-of-week SYM on or before today."
  (let* ((target (cdr (assq sym '((sun . 0) (mon . 1) (tue . 2) (wed . 3)
                                  (thu . 4) (fri . 5) (sat . 6)))))
         (today (decode-time))
         (today-dow (decoded-time-weekday today))
         (offset (mod (- today-dow target) 7)))
    (unless target
      (user-error "Unknown weekday symbol: %S" sym))
    (encode-time
     (decoded-time-add today (make-decoded-time :day (- offset))))))


;;; Parsing

(defun arche-diary--parse-month (input)
  "Parse INPUT into (YEAR . MONTH).

INPUT may be:
- nil — current month
- a non-positive integer — offset (`-1' = last month, `0' = current)
- an integer 1..12 — that month, this year
- a list `(MONTH)' — that month, this year
- a list `(YEAR MONTH)' or cons `(YEAR . MONTH)' — explicit
- the symbol `last-month' or `this-month'
- a string like \"05\", \"2026-05\", \"2026/05\", \"May 2026\", \"May\",
  \"-1\", \"+2\"."
  (let* ((now (decode-time))
         (cur-y (decoded-time-year now))
         (cur-m (decoded-time-month now)))
    (cond
     ((null input) (cons cur-y cur-m))
     ((eq input 'this-month) (cons cur-y cur-m))
     ((eq input 'last-month)
      (arche-diary--add-months-to cur-y cur-m -1))
     ((integerp input)
      (cond
       ((<= input 0) (arche-diary--add-months-to cur-y cur-m input))
       ((<= 1 input 12) (cons cur-y input))
       (t (user-error "Numeric month must be 1..12 or non-positive: %d" input))))
     ((consp input)
      (pcase input
        (`(,m) (unless (and (integerp m) (<= 1 m 12))
                 (user-error "Month out of range: %S" m))
               (cons cur-y m))
        (`(,y ,m) (cons y m))
        (`(,y . ,m) (cons y m))
        (_ (user-error "Unrecognized month list: %S" input))))
     ((stringp input)
      (arche-diary--parse-month-string input cur-y cur-m))
     (t (user-error "Cannot interpret month %S" input)))))

(defun arche-diary--parse-month-string (input cur-y cur-m)
  "Parse INPUT as a month string; CUR-Y and CUR-M are fallbacks."
  (let ((s (string-trim input)))
    (cond
     ((string-match "\\`[-+][0-9]+\\'" s)
      (arche-diary--add-months-to cur-y cur-m (string-to-number s)))
     ((string-match "\\`\\([0-9]\\{4\\}\\)[-/]\\([0-9]\\{1,2\\}\\)\\'" s)
      (cons (string-to-number (match-string 1 s))
            (string-to-number (match-string 2 s))))
     ((string-match "\\`\\([0-9]\\{1,2\\}\\)\\'" s)
      (let ((m (string-to-number s)))
        (unless (<= 1 m 12)
          (user-error "Month out of range: %d" m))
        (cons cur-y m)))
     ((string-match "\\`\\([A-Za-z]+\\)\\(?:[, ]+\\([0-9]\\{4\\}\\)\\)?\\'" s)
      (let* ((mname (downcase (match-string 1 s)))
             (m (cdr (assoc-string mname parse-time-months t)))
             (y (if (match-string 2 s)
                    (string-to-number (match-string 2 s))
                  cur-y)))
        (unless m (user-error "Unknown month name: %s" mname))
        (cons y m)))
     (t (user-error "Cannot interpret month string %S" s)))))

(defun arche-diary--parse-date (input &optional buffer-month allow-weekdays)
  "Parse INPUT into an encoded time.

When BUFFER-MONTH (a cons (YEAR . MONTH)) is non-nil, day-only
strings (like \"15\") are interpreted in that month.  When
ALLOW-WEEKDAYS is non-nil, weekday symbols (`mon' .. `sun') are
accepted and resolve to the most recent occurrence on or before
today.

Accepted forms include nil (today), the symbols `today' and
`yesterday', integers (offset in days from today), `(YEAR MONTH
DAY)' lists, and strings such as \"2026-05-15\", \"05\", \"-1\",
\"1231\", \"20261231\", \"May 10\", \"May 10 2026\"."
  (let ((today (decode-time)))
    (cond
     ((null input)
      (arche-diary--time-for-day (decoded-time-year today)
                                 (decoded-time-month today)
                                 (decoded-time-day today)))
     ((eq input 'today)
      (arche-diary--time-for-day (decoded-time-year today)
                                 (decoded-time-month today)
                                 (decoded-time-day today)))
     ((eq input 'yesterday)
      (encode-time (decoded-time-add today (make-decoded-time :day -1))))
     ((and allow-weekdays
           (memq input '(mon tue wed thu fri sat sun)))
      (arche-diary--weekday-symbol-to-time input))
     ((symbolp input)
      (user-error "Unrecognized date symbol: %S" input))
     ((integerp input)
      (encode-time (decoded-time-add today (make-decoded-time :day input))))
     ((consp input)
      (pcase input
        (`(,y ,m ,d) (arche-diary--time-for-day y m d))
        (_ (user-error "Unrecognized date list: %S" input))))
     ((stringp input)
      (arche-diary--parse-date-string input buffer-month today))
     (t (user-error "Cannot interpret date %S" input)))))

(defun arche-diary--parse-date-string (input buffer-month today)
  "Parse INPUT (a string) as a date.
BUFFER-MONTH constrains bare day-of-month strings.  TODAY is a
decoded-time list."
  (let ((s (string-trim input)))
    (cond
     ((string-match "\\`\\([-+]?\\)\\([0-9]+\\)\\'" s)
      (let* ((sign (match-string 1 s))
             (digits (match-string 2 s))
             (n (string-to-number s)))
        (cond
         ((not (string-empty-p sign))
          (encode-time (decoded-time-add today (make-decoded-time :day n))))
         ((and (<= 1 n 31) (<= (length digits) 2))
          (let ((ym (or buffer-month
                        (cons (decoded-time-year today)
                              (decoded-time-month today)))))
            (arche-diary--time-for-day (car ym) (cdr ym) n)))
         ((= (length digits) 4)
          (arche-diary--time-for-day (decoded-time-year today)
                                     (string-to-number (substring digits 0 2))
                                     (string-to-number (substring digits 2 4))))
         ((= (length digits) 8)
          (arche-diary--time-for-day (string-to-number (substring digits 0 4))
                                     (string-to-number (substring digits 4 6))
                                     (string-to-number (substring digits 6 8))))
         (t (user-error "Cannot interpret numeric date %S" s)))))
     ((string-match
       "\\`\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)-\\([0-9]\\{2\\}\\)\\'" s)
      (arche-diary--time-for-day (string-to-number (match-string 1 s))
                                 (string-to-number (match-string 2 s))
                                 (string-to-number (match-string 3 s))))
     ((string-match
       "\\`\\([A-Za-z]+\\)[. ]+\\([0-9]+\\)\\(?:[, ]+\\([0-9]\\{4\\}\\)\\)?\\'"
       s)
      (let* ((mname (downcase (match-string 1 s)))
             (m (cdr (assoc-string mname parse-time-months t)))
             (d (string-to-number (match-string 2 s)))
             (y (if (match-string 3 s)
                    (string-to-number (match-string 3 s))
                  (decoded-time-year today))))
        (unless m (user-error "Unknown month name: %s" mname))
        (arche-diary--time-for-day y m d)))
     (t (user-error "Cannot interpret date string %S" s)))))


;;; Buffer / file location helpers

(defun arche-diary--html-directory ()
  "Return the directory exported HTML is written to.
`arche-diary-html-directory' when non-nil, otherwise the `html'
subdirectory of `arche-diary-directory'."
  (or arche-diary-html-directory
      (expand-file-name "html" arche-diary-directory)))

(defun arche-diary--image-directory ()
  "Return the directory `arche-diary-insert-image' copies into.
`arche-diary-image-directory' when non-nil, otherwise the
`images' subdirectory of `arche-diary-directory'."
  (or arche-diary-image-directory
      (expand-file-name "images" arche-diary-directory)))

(defun arche-diary--current-buffer-month ()
  "Return (YEAR . MONTH) inferred from the current buffer's #+title.
Return nil if no recognizable title is present."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (let ((case-fold-search t))
        (when (re-search-forward
               "^#\\+title:[ \t]+\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)\\b"
               nil t)
          (cons (string-to-number (match-string 1))
                (string-to-number (match-string 2))))))))

(defun arche-diary--denote-file-has-keyword-p (path keyword)
  "Return non-nil if PATH (a denote-style filename) has KEYWORD."
  (let ((name (file-name-nondirectory path)))
    (when (string-match "__\\([^/.]+\\)\\." name)
      (member keyword (split-string (match-string 1 name) "_" t)))))

(defvar arche-diary--month-files-cache nil
  "Per-export cache of the monthly file listing.
When non-nil it is a cons (t . ENTRIES) holding the result of
`arche-diary--list-month-files'.  Bound for the dynamic extent of
one export (see `arche-diary--with-export-caches'); nil means scan
the directory afresh.")

(defvar arche-diary--month-data-cache nil
  "Per-export cache mapping a month's Org PATH to its parsed data.
A hash table when active, else nil.  Bound for the dynamic extent
of one export so a month read once (e.g. for its own page) is not
re-parsed and re-exported for `index.html'.")

(defmacro arche-diary--with-export-caches (&rest body)
  "Run BODY with the directory listing and per-month data memoized.
This is sound only because the Org sources are not modified during
an export: a single command may scan the directory and render the
same month several times (its own page plus `index.html'), and
without memoization each scan re-runs `denote-directory-files' and
each render re-exports every note through Org.  Nesting reuses the
outer caches."
  (declare (indent 0) (debug t))
  `(let ((arche-diary--month-files-cache
          (or arche-diary--month-files-cache
              (cons t (arche-diary--list-month-files))))
         (arche-diary--month-data-cache
          (or arche-diary--month-data-cache
              (make-hash-table :test 'equal))))
     ,@body))

(defun arche-diary--find-or-list-month-files ()
  "Return list of (YEAR MONTH PATH) for every monthly diary file.
Sorted in ascending chronological order.  Uses the per-export
cache (`arche-diary--month-files-cache') when one is active."
  (if arche-diary--month-files-cache
      (cdr arche-diary--month-files-cache)
    (arche-diary--list-month-files)))

(defun arche-diary--list-month-files ()
  "Scan the diary directory for monthly files, ascending.
Returns (YEAR MONTH PATH) entries.  Always hits the filesystem;
callers within an export should go through
`arche-diary--find-or-list-month-files' so one scan is shared."
  (let ((entries nil))
    (when (file-directory-p arche-diary-directory)
      (pcase arche-diary-file-creation-system
        ('plain
         (dolist (f (directory-files arche-diary-directory t "\\.org\\'"))
           (when (string-match
                  "\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)\\.org\\'"
                  (file-name-nondirectory f))
             (push (list (string-to-number (match-string 1 (file-name-nondirectory f)))
                         (string-to-number (match-string 2 (file-name-nondirectory f)))
                         f)
                   entries))))
        ('denote
         (let* ((denote-directory arche-diary-directory)
                (keyword (car arche-diary-denote-keywords))
                (files (denote-directory-files
                        "--[0-9]\\{4\\}-[0-9]\\{2\\}__")))
           (dolist (f files)
             (when (and (or (null keyword)
                            (arche-diary--denote-file-has-keyword-p f keyword))
                        (string-match
                         "--\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)__"
                         (file-name-nondirectory f)))
               (push (list (string-to-number
                            (match-string 1 (file-name-nondirectory f)))
                           (string-to-number
                            (match-string 2 (file-name-nondirectory f)))
                           f)
                     entries)))))))
    (sort entries
          (lambda (a b)
            (or (< (nth 0 a) (nth 0 b))
                (and (= (nth 0 a) (nth 0 b))
                     (< (nth 1 a) (nth 1 b))))))))

(defun arche-diary--month-file (year month)
  "Return the path of the existing monthly file for YEAR/MONTH, or nil."
  (pcase arche-diary-file-creation-system
    ('plain
     (let ((path (expand-file-name
                  (format-time-string
                   arche-diary-filename-format
                   (arche-diary--time-for-day year month 1))
                  arche-diary-directory)))
       (and (file-exists-p path) path)))
    ('denote
     (nth 2 (seq-find
             (lambda (e) (and (= (nth 0 e) year) (= (nth 1 e) month)))
             (arche-diary--find-or-list-month-files))))))

(defun arche-diary--create-plain-file (year month)
  "Create a plain Org file for YEAR/MONTH and return its path."
  (unless (file-directory-p arche-diary-directory)
    (make-directory arche-diary-directory t))
  (let* ((time (arche-diary--time-for-day year month 1))
         (path (expand-file-name
                (format-time-string arche-diary-filename-format time)
                arche-diary-directory))
         (title (format-time-string arche-diary-title-format time)))
    (with-temp-file path
      (insert (format "#+title: %s\n\n" title)))
    path))

(defun arche-diary--create-denote-file (year month)
  "Create a denote-managed Org file for YEAR/MONTH and return its path."
  (unless (file-directory-p arche-diary-directory)
    (make-directory arche-diary-directory t))
  (let* ((time (arche-diary--time-for-day year month 1))
         (title (format-time-string arche-diary-title-format time))
         (date-string (format-time-string "%Y-%m-%d %H:%M:%S" time))
         (denote-directory arche-diary-directory)
         (denote-save-buffers t)
         (denote-kill-buffers t)
         (result (denote title
                         arche-diary-denote-keywords
                         arche-diary-denote-file-type
                         arche-diary-directory
                         date-string)))
    (or (and (stringp result) (file-exists-p result) result)
        (arche-diary--month-file year month)
        (error "Failed to create denote file for %04d-%02d" year month))))

(defun arche-diary--links-heading-regexp ()
  "Return a regexp matching the links heading line, or nil when disabled."
  (when (and arche-diary-links-heading
             (not (string-empty-p arche-diary-links-heading)))
    (concat "^\\* " (regexp-quote arche-diary-links-heading) "[ \t]*$")))

(defun arche-diary--links-subtree-bounds ()
  "Return (BEG . END) of the links subtree in the current buffer, or nil.
BEG is the start of the heading line; END is the start of the next
level-1 heading or `point-max'."
  (let ((re (arche-diary--links-heading-regexp)))
    (when re
      (save-excursion
        (goto-char (point-min))
        (when (re-search-forward re nil t)
          (cons (line-beginning-position)
                (save-excursion
                  (forward-line 1)
                  (if (re-search-forward "^\\* " nil t)
                      (line-beginning-position)
                    (point-max)))))))))

(defun arche-diary--links-subtree-string (path)
  "Return the raw text of the links subtree in PATH, or nil.
Heading and body are kept verbatim, trailing whitespace trimmed."
  (when (and path (file-exists-p path))
    (with-temp-buffer
      (insert-file-contents path)
      (let ((bounds (arche-diary--links-subtree-bounds)))
        (when bounds
          (let ((s (string-trim-right
                    (buffer-substring-no-properties (car bounds) (cdr bounds)))))
            (unless (string-empty-p s) s)))))))

(defun arche-diary--month-links (path)
  "Return the (URL . LABEL) links under the links heading in PATH.
The list is in document order; LABEL falls back to URL when the
Org link carries no description."
  (when (and path (file-exists-p path))
    (with-temp-buffer
      (insert-file-contents path)
      (let ((bounds (arche-diary--links-subtree-bounds))
            results)
        (when bounds
          (goto-char (car bounds))
          (while (re-search-forward
                  "\\[\\[\\([^][]+\\)\\]\\(?:\\[\\([^][]*\\)\\]\\)?\\]"
                  (cdr bounds) t)
            (push (cons (match-string-no-properties 1)
                        (or (match-string-no-properties 2)
                            (match-string-no-properties 1)))
                  results)))
        (nreverse results)))))

(defun arche-diary--seed-links (path year month)
  "Seed freshly created PATH with the previous month's links subtree.
Copies the links subtree from the most recent existing month
strictly before YEAR/MONTH, verbatim, just below the front
matter.  No-op when the feature is disabled or no earlier month
carries a links subtree."
  (when (and path (arche-diary--links-heading-regexp))
    (let* ((prior (cl-find-if
                   (lambda (e)
                     (let ((ey (nth 0 e)) (em (nth 1 e)))
                       (or (< ey year) (and (= ey year) (< em month)))))
                   (reverse (arche-diary--find-or-list-month-files))))
           (subtree (and prior (arche-diary--links-subtree-string (nth 2 prior)))))
      (when subtree
        (let* ((existing-buf (get-file-buffer path))
               (buf (or existing-buf (find-file-noselect path))))
          (with-current-buffer buf
            (save-excursion
              (goto-char (point-min))
              ;; Skip the front matter: leading `#+keyword' and blank lines.
              (while (and (not (eobp))
                          (looking-at-p "^\\(#\\+\\|[ \t]*$\\)"))
                (forward-line 1))
              ;; Guarantee a blank line between front matter and the subtree.
              (unless (or (bobp)
                          (save-excursion
                            (forward-line -1)
                            (looking-at-p "^[ \t]*$")))
                (insert "\n"))
              (insert subtree "\n\n"))
            (save-buffer))
          (unless existing-buf (kill-buffer buf)))))))

(defun arche-diary--ensure-monthly-file (year month)
  "Return path of monthly file for YEAR/MONTH, creating it if needed.
A newly created file inherits the previous month's links subtree
\(see `arche-diary-links-heading')."
  (or (arche-diary--month-file year month)
      (let ((path (pcase arche-diary-file-creation-system
                    ('plain (arche-diary--create-plain-file year month))
                    ('denote (arche-diary--create-denote-file year month))
                    (other (user-error
                            "Unknown arche-diary-file-creation-system: %S" other)))))
        (arche-diary--seed-links path year month)
        path)))


;;; Date heading helpers (buffer-local operations)

(defun arche-diary--date-headings-in-buffer ()
  "Return list of (ISO . MARKER) for date headings, in document order."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (let (results)
        (while (re-search-forward arche-diary-date-heading-regexp nil t)
          (push (cons (match-string-no-properties 1)
                      (copy-marker (line-beginning-position)))
                results))
        (nreverse results)))))

(defun arche-diary--goto-date-heading (iso)
  "Move point to the heading for ISO date.  Return non-nil on success."
  (let ((entry (assoc iso (arche-diary--date-headings-in-buffer))))
    (when entry
      (goto-char (cdr entry))
      t)))

(defun arche-diary--last-date-in-buffer ()
  "Return the largest ISO date string present in the current buffer."
  (let ((isos (mapcar #'car (arche-diary--date-headings-in-buffer))))
    (when isos (car (last (sort isos #'string<))))))

(defun arche-diary--insert-date-heading (time)
  "Insert a level-1 date heading for TIME at the correct chronological slot.
If a heading for that date already exists, just move point to it.
Leaves point on the blank line right after the heading."
  (let* ((iso (arche-diary--time-to-iso time))
         (entries (arche-diary--date-headings-in-buffer))
         (existing (assoc iso entries)))
    (if existing
        (progn (goto-char (cdr existing)) (forward-line 1))
      (let* ((heading (format-time-string
                       (concat "* " arche-diary-date-heading-format) time))
             (later (cl-find-if (lambda (e) (string> (car e) iso)) entries))
             (insert-pos (or (and later (marker-position (cdr later)))
                             (point-max))))
        (goto-char insert-pos)
        (unless (or (bobp) (bolp)) (insert "\n"))
        (unless (or (bobp)
                    (save-excursion
                      (forward-line -1)
                      (looking-at-p "^[ \t]*$")))
          (insert "\n"))
        (let ((heading-start (point)))
          (insert heading "\n\n")
          (goto-char heading-start)
          (forward-line 1))))))

(defun arche-diary--latest-date-globally ()
  "Return ISO date string of the latest date heading across all months."
  (let ((entries (reverse (arche-diary--find-or-list-month-files)))
        latest)
    (while (and entries (not latest))
      (let* ((path (nth 2 (car entries)))
             (existing-buf (get-file-buffer path))
             (buf (or existing-buf (find-file-noselect path))))
        (with-current-buffer buf
          (setq latest (arche-diary--last-date-in-buffer)))
        (unless existing-buf (kill-buffer buf)))
      (setq entries (cdr entries)))
    latest))


;;; Image helpers

(defconst arche-diary--image-extensions
  '("png" "jpg" "jpeg" "gif" "svg" "webp" "bmp" "tiff" "tif")
  "Recognized image file extensions (lower-case, no leading dot).")

(defun arche-diary--image-file-p (path)
  "Return non-nil if PATH has a recognized image extension."
  (let ((ext (file-name-extension path)))
    (and ext (member (downcase ext) arche-diary--image-extensions) t)))

(defun arche-diary--files-identical-p (a b)
  "Return non-nil if files A and B exist with byte-identical contents."
  (and (file-readable-p a) (file-readable-p b)
       (= (file-attribute-size (file-attributes a))
          (file-attribute-size (file-attributes b)))
       (with-temp-buffer
         (let ((coding-system-for-read 'no-conversion))
           (insert-file-contents-literally a)
           (let ((ca (buffer-string)))
             (erase-buffer)
             (insert-file-contents-literally b)
             (string= ca (buffer-string)))))))

(defun arche-diary--image-copy-current-p (src dest)
  "Return non-nil if DEST is an up-to-date export copy of SRC.
Compares only existence, byte size and modification time, avoiding
a full read of potentially large image files on every export.
DEST is considered current when it exists, matches SRC in size,
and is not older than SRC — the same mtime-based staleness model
the package uses elsewhere (see `arche-diary--month-html-stale-p').
Because the export copies to a deterministic destination, a
changed source is caught by a size difference or a newer mtime."
  (let ((da (and (file-exists-p dest) (file-attributes dest)))
        (sa (file-attributes src)))
    (and da sa
         (= (file-attribute-size sa) (file-attribute-size da))
         (not (time-less-p (file-attribute-modification-time da)
                           (file-attribute-modification-time sa))))))

(defun arche-diary--enclosing-date-iso ()
  "Return the ISO date of the date heading point is under.
Signal a `user-error' if point is not under any date heading."
  (save-excursion
    (save-restriction
      (widen)
      (end-of-line)
      (if (re-search-backward arche-diary-date-heading-regexp nil t)
          (match-string-no-properties 1)
        (user-error "Point is not under a diary date heading")))))

(defun arche-diary--image-dest-path (source iso)
  "Return the copy destination path for SOURCE.
When ISO is non-nil and `arche-diary-image-date-subdir' is set, a
per-date subdirectory is used.  The destination directory is
created.  An existing, differing file of the same name is avoided
by appending a numeric suffix."
  (let* ((dir (if (and arche-diary-image-date-subdir iso)
                  (expand-file-name iso (arche-diary--image-directory))
                (arche-diary--image-directory)))
         (base (file-name-nondirectory source))
         (stem (file-name-sans-extension base))
         (ext (file-name-extension base))
         (dest (expand-file-name base dir))
         (n 1))
    (make-directory dir t)
    (while (and (file-exists-p dest)
                (not (arche-diary--files-identical-p source dest)))
      (setq n (1+ n)
            dest (expand-file-name
                  (format "%s-%d%s" stem n (if ext (concat "." ext) ""))
                  dir)))
    dest))

(defun arche-diary--image-link-string (target)
  "Return the Org link path for TARGET per `arche-diary-image-link-type'."
  (let ((abs (expand-file-name target)))
    (pcase arche-diary-image-link-type
      ('absolute abs)
      (_ (file-relative-name
          abs (file-name-as-directory
               (expand-file-name arche-diary-directory)))))))

(defun arche-diary--buffer-name-keywords ()
  "Return all `#+NAME:' values in the current buffer."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (let ((case-fold-search t) names)
        (while (re-search-forward "^#\\+name:[ \t]+\\(.+?\\)[ \t]*$" nil t)
          (push (match-string-no-properties 1) names))
        names))))

(defun arche-diary--image-name-keyword (source)
  "Return a unique `fig:'-prefixed NAME derived from SOURCE.
Uniqueness is checked against existing `#+NAME:' keywords in the
current buffer."
  (let* ((stem (file-name-sans-extension (file-name-nondirectory source)))
         (slug (replace-regexp-in-string "[^A-Za-z0-9]+" "-" stem))
         (slug (replace-regexp-in-string "\\`-+\\|-+\\'" "" slug))
         (slug (if (string-empty-p slug) "image" slug))
         (base (concat "fig:" slug))
         (existing (arche-diary--buffer-name-keywords))
         (name base)
         (n 1))
    (while (member name existing)
      (setq n (1+ n) name (format "%s-%d" base n)))
    name))

(defun arche-diary--gallery-end-position ()
  "Return the buffer position of the `#+end_gallery' line point is in.
Point is considered inside a gallery when it lies between a
`#+begin_gallery' line and the next `#+end_gallery' line.  Return
nil when point is not inside such a block."
  (save-excursion
    (save-restriction
      (widen)
      (let ((case-fold-search t)
            (origin (point)))
        (end-of-line)
        (when (re-search-backward "^[ \t]*#\\+begin_gallery\\b" nil t)
          (let ((beg (line-beginning-position)))
            (when (re-search-forward "^[ \t]*#\\+end_gallery\\b" nil t)
              (let ((end (line-beginning-position)))
                (and (<= beg origin) (<= origin end) end)))))))))


;;; Public commands

;;;###autoload
(defun arche-diary-open-month (&optional month)
  "Open the monthly diary file for MONTH, creating it if necessary.

MONTH accepts many formats; see `arche-diary--parse-month'.  With
no argument (or a prefix arg with empty input) the current month
is used.  When called interactively with a prefix argument, the
user is prompted for MONTH."
  (interactive
   (list (when current-prefix-arg
           (let ((s (read-from-minibuffer
                     "Month (e.g. -1, 5, 2026-05, May 2026): ")))
             (and (not (string-empty-p s)) s)))))
  (pcase-let* ((`(,year . ,month-num) (arche-diary--parse-month month))
               (path (arche-diary--ensure-monthly-file year month-num)))
    (find-file path)
    (current-buffer)))

;;;###autoload
(defun arche-diary-add-date (&optional date)
  "Insert a 1st-level date heading for DATE into the current buffer.
DATE defaults to today.  The date must fall in the current buffer's
month; otherwise a `user-error' is signaled.  See
`arche-diary--parse-date' for accepted DATE formats."
  (interactive
   (list (when current-prefix-arg
           (let ((s (read-from-minibuffer
                     "Date (DD, YYYY-MM-DD, -1, ...): ")))
             (and (not (string-empty-p s)) s)))))
  (let ((buffer-month (arche-diary--current-buffer-month)))
    (unless buffer-month
      (user-error "Buffer is not a recognized monthly diary file"))
    (let* ((time (arche-diary--parse-date date buffer-month))
           (date-month (arche-diary--time-to-month time)))
      (unless (equal date-month buffer-month)
        (user-error
         "Date %s is outside this buffer's month (%04d-%02d)"
         (arche-diary--time-to-iso time)
         (car buffer-month) (cdr buffer-month)))
      (arche-diary--insert-date-heading time)
      (run-hooks 'arche-diary-after-add-date-hook))))

;;;###autoload
(defun arche-diary-visit-date (&optional date)
  "Open the monthly file for DATE and point at its heading.
Creates the file and the heading if either is missing.  DATE
defaults to today.  Accepts every form
`arche-diary--parse-date' supports, plus weekday symbols like
`mon' .. `sun' that resolve to the most recent occurrence on or
before today."
  (interactive
   (list (when current-prefix-arg
           (let ((s (read-from-minibuffer "Date: ")))
             (and (not (string-empty-p s)) s)))))
  (let* ((time (arche-diary--parse-date date nil t))
         (year-month (arche-diary--time-to-month time))
         (path (arche-diary--ensure-monthly-file
                (car year-month) (cdr year-month)))
         (iso (arche-diary--time-to-iso time)))
    (find-file path)
    (unless (arche-diary--goto-date-heading iso)
      (arche-diary--insert-date-heading time)
      (arche-diary--goto-date-heading iso))
    (current-buffer)))

;;;###autoload
(defun arche-diary-fill-dates (&optional start end)
  "Insert headings for every day in [START, END].
END defaults to today.  START defaults to the day after the
latest existing date across all months, or END when no dates
exist anywhere.  Creates monthly files as needed.  With a prefix
argument, prompt for both bounds.

Point is moved to the START date's heading and its buffer shown.
`arche-diary-fill-dates-keep-buffers' decides whether the other
months opened along the way are kept or saved and closed; buffers
the user already had open are never closed."
  (interactive
   (when current-prefix-arg
     (list (let ((s (read-from-minibuffer "Start (blank = latest+1): ")))
             (and (not (string-empty-p s)) s))
           (let ((s (read-from-minibuffer "End (blank = today): ")))
             (and (not (string-empty-p s)) s)))))
  (let* ((end-time (arche-diary--parse-date end nil t))
         (start-time
          (cond
           (start (arche-diary--parse-date start nil t))
           (t (let ((latest (arche-diary--latest-date-globally)))
                (if latest
                    (arche-diary--day-after-iso latest)
                  end-time))))))
    (when (time-less-p end-time start-time)
      (user-error "Start date (%s) is after end date (%s)"
                  (arche-diary--time-to-iso start-time)
                  (arche-diary--time-to-iso end-time)))
    (let ((cur start-time)
          (count 0)
          (start-iso (arche-diary--time-to-iso start-time))
          (pre-buffers (cl-remove-if-not #'buffer-file-name (buffer-list)))
          start-buf
          touched)
      (while (not (time-less-p end-time cur))
        (let* ((ym (arche-diary--time-to-month cur))
               (path (arche-diary--ensure-monthly-file (car ym) (cdr ym)))
               (buf (or (get-file-buffer path) (find-file-noselect path))))
          (with-current-buffer buf
            (arche-diary--insert-date-heading cur)
            (save-buffer))
          (cl-pushnew buf touched)
          (unless start-buf (setq start-buf buf)))
        (cl-incf count)
        (setq cur (encode-time
                   (decoded-time-add (decode-time cur)
                                     (make-decoded-time :day 1)))))
      ;; Close the scratch buffers we opened (saved above), keeping the
      ;; start month and anything the user already had open.
      (when (eq arche-diary-fill-dates-keep-buffers 'start)
        (dolist (buf touched)
          (unless (or (eq buf start-buf) (memq buf pre-buffers))
            (kill-buffer buf))))
      (when start-buf
        (pop-to-buffer-same-window start-buf)
        (arche-diary--goto-date-heading start-iso))
      (message "arche-diary: added %d date(s)" count))))

;;;###autoload
(defun arche-diary-insert-image (source &optional no-copy gallery)
  "Insert an Org image link at point for SOURCE.

By default SOURCE is copied into `arche-diary-image-directory'
\(optionally into a per-date subdirectory named by the date
heading point is under) and the copy is linked; with NO-COPY
non-nil the original file is linked in place.

With GALLERY non-nil the image block is placed inside a
`#+begin_gallery' .. `#+end_gallery' wrapper, which the HTML
export lays out as a wrapping horizontal row.  If point is
already inside such a block the image is appended to it;
otherwise a new wrapper is created.  Gallery images use
`arche-diary-image-gallery-width' instead of
`arche-diary-image-width'.

Called interactively, the image file is prompted for; a single
prefix argument (\\[universal-argument]) inverts
`arche-diary-image-copy' for that call, and a double prefix
argument (\\[universal-argument] \\[universal-argument]) inserts
into a gallery.

A `#+CAPTION:' placeholder, a `#+NAME: fig:...' keyword and a
`#+ATTR_HTML:' line are inserted before the link, and point is
left on the caption line."
  (interactive
   (list (read-file-name "Image file: " nil nil t)
         (if (equal current-prefix-arg '(4))
             arche-diary-image-copy
           (not arche-diary-image-copy))
         (equal current-prefix-arg '(16))))
  (setq source (expand-file-name source))
  (unless (file-readable-p source)
    (user-error "Cannot read image file: %s" source))
  (let* ((copy (not no-copy))
         (iso (and copy arche-diary-image-date-subdir
                   (arche-diary--enclosing-date-iso)))
         (target
          (if copy
              (let ((dest (arche-diary--image-dest-path source iso)))
                (unless (and (file-exists-p dest)
                             (arche-diary--files-identical-p source dest))
                  (copy-file source dest t))
                dest)
            source))
         (link (arche-diary--image-link-string target))
         (name (arche-diary--image-name-keyword source))
         (width (if gallery
                    arche-diary-image-gallery-width
                  arche-diary-image-width))
         (attr (concat
                (format "#+ATTR_HTML: :width %s" width)
                (unless (eq arche-diary-image-align 'none)
                  (format " :align %s" arche-diary-image-align))))
         (block (format "#+CAPTION: \n#+NAME: %s\n%s\n[[file:%s]]\n"
                        name attr link))
         (gpos (and gallery (arche-diary--gallery-end-position))))
    (cond
     (gpos
      ;; Append to the gallery point is already inside.
      (goto-char gpos)
      (unless (save-excursion (forward-line -1)
                              (looking-at-p "^[ \t]*$"))
        (insert "\n"))
      (let ((caption-pos (point)))
        (insert block)
        (goto-char caption-pos)
        (end-of-line)))
     (gallery
      ;; Wrap the image in a new gallery block.
      (unless (bolp) (insert "\n"))
      (unless (or (bobp)
                  (save-excursion (forward-line -1)
                                  (looking-at-p "^[ \t]*$")))
        (insert "\n"))
      (insert "#+begin_gallery\n")
      (let ((caption-pos (point)))
        (insert block "#+end_gallery\n")
        (unless (or (eobp) (looking-at-p "^[ \t]*$")) (insert "\n"))
        (goto-char caption-pos)
        (end-of-line)))
     (t
      (unless (bolp) (insert "\n"))
      (unless (or (bobp)
                  (save-excursion (forward-line -1)
                                  (looking-at-p "^[ \t]*$")))
        (insert "\n"))
      (let ((caption-pos (point)))
        (insert block)
        (unless (or (eobp) (looking-at-p "^[ \t]*$")) (insert "\n"))
        (goto-char caption-pos)
        (end-of-line))))))


;;; HTML export

(defun arche-diary--html-escape (s)
  "Return S with HTML-significant characters escaped."
  (let ((s (or s "")))
    (setq s (replace-regexp-in-string "&" "&amp;" s t t))
    (setq s (replace-regexp-in-string "<" "&lt;" s t t))
    (setq s (replace-regexp-in-string ">" "&gt;" s t t))
    s))

(defun arche-diary--export-image-dest (abs-src)
  "Return (RELDEST . ABSDEST) for ABS-SRC in the html image tree.
RELDEST is forward-slashed and relative to
`arche-diary-html-directory'; ABSDEST is its absolute path.
Images under `arche-diary-image-directory' keep their subtree."
  (let* ((image-dir (arche-diary--image-directory))
         (img-root (file-name-as-directory (expand-file-name image-dir)))
         (sub (file-name-as-directory
               (file-name-nondirectory
                (directory-file-name image-dir))))
         (abs (expand-file-name abs-src))
         (rel (if (string-prefix-p img-root abs)
                  (concat sub (substring abs (length img-root)))
                (concat sub (file-name-nondirectory abs)))))
    (cons rel (expand-file-name rel (arche-diary--html-directory)))))

(defun arche-diary--rewrite-image-links-for-export (str)
  "Copy images linked from STR into the html dir.
Return STR with those file links rewritten to paths relative to
`arche-diary-html-directory' so the exported page is
self-contained."
  (replace-regexp-in-string
   "\\[\\[file:\\([^]]+?\\)\\]\\(\\[[^]]*\\]\\)?\\]"
   (lambda (m)
     (let* ((path (match-string 1 m))
            (desc (or (match-string 2 m) ""))
            (abs (expand-file-name path arche-diary-directory)))
       (if (and (arche-diary--image-file-p abs) (file-readable-p abs))
           (let* ((d (arche-diary--export-image-dest abs))
                  (reldest (car d))
                  (absdest (cdr d)))
             (make-directory (file-name-directory absdest) t)
             (unless (arche-diary--image-copy-current-p abs absdest)
               (copy-file abs absdest t))
             (format "[[file:%s]%s]" reldest desc))
         m)))
   str t t))

(defconst arche-diary--cjk-regexp
  "[　-〿぀-ヿ㐀-䶿一-鿿＀-￯]"
  "Regexp matching one CJK character.
Covers CJK symbols and punctuation, hiragana, katakana, the CJK
Unified Ideographs (plus extension A), and halfwidth/fullwidth
forms.")

(defconst arche-diary--unfill-block-begin-re "^[ \t]*#\\+begin_"
  "Regexp matching the opening line of an Org block.")

(defconst arche-diary--unfill-block-end-re "^[ \t]*#\\+end_"
  "Regexp matching the closing line of an Org block.")

(defconst arche-diary--unfill-element-start-re
  (concat "^\\(?:"
          "[ \t]*$"                     ; blank line
          "\\|[ \t]*[-+*][ \t]"         ; unordered list item
          "\\|[ \t]*[0-9]+[.)][ \t]"    ; ordered list item
          "\\|[ \t]*-\\{5,\\}[ \t]*$"   ; horizontal rule
          "\\|[ \t]*#"                  ; keyword / comment / block
          "\\|[ \t]*|"                  ; table row
          "\\|[ \t]*:"                  ; drawer or fixed-width line
          "\\|\\*+[ \t]"                ; heading
          "\\|\\[fn:"                   ; footnote definition
          "\\)")
  "Regexp matching a line that begins a new Org element.
Such a line is never folded onto the preceding one.")

(defconst arche-diary--unfill-non-appendable-re
  (concat "^\\(?:"
          "[ \t]*$"                     ; blank line
          "\\|[ \t]*-\\{5,\\}[ \t]*$"   ; horizontal rule
          "\\|[ \t]*#"                  ; keyword / comment / block
          "\\|[ \t]*|"                  ; table row
          "\\|[ \t]*:"                  ; drawer or fixed-width line
          "\\|\\*+[ \t]"                ; heading
          "\\)")
  "Regexp matching a line that cannot absorb a following continuation.
List items are absent on purpose: their wrapped continuation lines
should fold back onto the bullet.")

(defconst arche-diary--zero-width-space "​"
  "A zero-width space (U+200B).
It renders to nothing in HTML yet counts as whitespace to Org's
emphasis parser, so it can separate a CJK character from an
adjacent emphasis marker without producing a visible gap.")

(defconst arche-diary--emphasis-marker-re "[*/_=~+]"
  "Regexp matching a single Org emphasis marker character.
These are the markers from `org-emphasis-alist': bold, italic,
underline, verbatim, code and strike-through.")

(defun arche-diary--cjk-head-p (s)
  "Return non-nil if the first non-blank character of S is CJK."
  (let ((s (string-trim-left s)))
    (and (> (length s) 0)
         (string-match-p arche-diary--cjk-regexp (substring s 0 1)))))

(defun arche-diary--cjk-tail-p (s)
  "Return non-nil if the last non-blank character of S is CJK."
  (let ((s (string-trim-right s)))
    (and (> (length s) 0)
         (string-match-p arche-diary--cjk-regexp (substring s -1)))))

(defun arche-diary--emphasis-at-boundary-p (prev cont)
  "Return non-nil if PREV ends or CONT begins with an emphasis marker.
PREV and CONT are the two text fragments about to be joined when a
hard-wrapped line is folded.  Org only recognizes an emphasis
marker that borders whitespace or a line edge, so a marker landing
directly against a CJK character at the fold would silently lose
its markup."
  (or (and (> (length prev) 0)
           (string-match-p arche-diary--emphasis-marker-re (substring prev -1)))
      (and (> (length cont) 0)
           (string-match-p arche-diary--emphasis-marker-re (substring cont 0 1)))))

(defun arche-diary--unfill-cjk (str)
  "Join hard-wrapped lines in STR for CJK-friendly HTML export.
Within a paragraph or list item, a line break is dropped entirely
when a CJK character is on either side of it (CJK text has no
inter-word spaces, so the break would otherwise render as a stray
space); a break between two non-CJK words becomes a single space,
matching how a browser would render the newline.  When a dropped
break would press an Org emphasis marker (e.g. `~code~') directly
against a CJK character — which Org refuses to parse as emphasis —
a zero-width space is inserted instead, so the markup survives
without a visible gap.  Blank lines, headings, lists, tables,
keywords and `#+begin_..#+end_' blocks keep their own lines."
  (let ((acc nil)
        (in-block nil))
    (dolist (line (split-string str "\n"))
      (cond
       (in-block
        (push line acc)
        (when (string-match-p arche-diary--unfill-block-end-re line)
          (setq in-block nil)))
       ((string-match-p arche-diary--unfill-block-begin-re line)
        (setq in-block t)
        (push line acc))
       ((and acc
             (not (string-match-p arche-diary--unfill-non-appendable-re
                                  (car acc)))
             (not (string-match-p arche-diary--unfill-element-start-re line)))
        (let* ((prev (string-trim-right (car acc)))
               (cont (string-trim-left line))
               (sep (cond
                     ;; A CJK character on either side: drop the break so it
                     ;; does not render as a stray space.  But if an emphasis
                     ;; marker borders the fold, separate the two with a
                     ;; zero-width space so Org still parses the markup while
                     ;; the page shows no gap.
                     ((or (arche-diary--cjk-tail-p prev)
                          (arche-diary--cjk-head-p cont))
                      (if (arche-diary--emphasis-at-boundary-p prev cont)
                          arche-diary--zero-width-space
                        ""))
                     ;; Two non-CJK words: one space, as a browser would render
                     ;; the newline.
                     (t " "))))
          (setcar acc (concat prev sep cont))))
       (t (push line acc))))
    (mapconcat #'identity (nreverse acc) "\n")))

(defun arche-diary--org-string-to-html (str)
  "Render Org-formatted STR to an HTML fragment (body only).
Hard-wrapped CJK lines are folded (see `arche-diary-html-unfill-cjk'),
and image file links are copied into the html directory and
rewritten so the exported page can resolve them."
  (let* ((org-export-with-toc nil)
         (org-export-with-section-numbers nil)
         (org-export-with-broken-links t)
         (org-export-with-author nil)
         (org-export-with-creator nil)
         (org-export-with-title nil)
         (org-html-htmlize-output-type (if (featurep 'htmlize) 'inline-css nil))
         (str (arche-diary--rewrite-image-links-for-export
               (if arche-diary-html-unfill-cjk
                   (arche-diary--unfill-cjk str)
                 str))))
    (string-trim (or (org-export-string-as str 'html t) ""))))

(defun arche-diary--heading-tags (heading)
  "Return the list of Org tags trailing HEADING, or nil.
HEADING is the heading text after the leading stars and space."
  (when (string-match "[ \t]+\\(:[[:alnum:]_@#%:]+:\\)[ \t]*\\'" heading)
    (split-string (match-string 1 heading) ":" t)))

(defun arche-diary--heading-strip-tags (heading)
  "Return HEADING with any trailing Org tags removed and trimmed."
  (string-trim
   (if (string-match "[ \t]+:[[:alnum:]_@#%:]+:[ \t]*\\'" heading)
       (substring heading 0 (match-beginning 0))
     heading)))

(defun arche-diary--heading-excluded-p (heading)
  "Return non-nil when HEADING carries an export-excluding tag.
The trailing Org tags of HEADING are matched against
`arche-diary-html-noexport-tags'."
  (and arche-diary-html-noexport-tags
       (cl-some (lambda (tag) (member tag arche-diary-html-noexport-tags))
                (arche-diary--heading-tags heading))))

(defun arche-diary--collect-notes-after-point (bound)
  "Collect level-2 notes between point and BOUND, in document order.
Each entry is a cons (TITLE . HTML-BODY).  Notes whose heading
carries a tag in `arche-diary-html-noexport-tags' are skipped."
  (let (results)
    (save-excursion
      (while (re-search-forward "^\\*\\* +\\(.*\\)$" bound t)
        (let ((heading (string-trim (match-string-no-properties 1))))
          (unless (arche-diary--heading-excluded-p heading)
            (let* ((title (arche-diary--heading-strip-tags heading))
                   (body-start (min (1+ (line-end-position)) (point-max)))
                   (body-end (save-excursion
                               (if (re-search-forward "^\\*\\*? " bound t)
                                   (line-beginning-position)
                                 bound)))
                   (body-text (buffer-substring-no-properties body-start body-end))
                   (body-html (arche-diary--org-string-to-html body-text)))
              (push (cons title body-html) results))))))
    (nreverse results)))

(defun arche-diary--month-data (path)
  "Read PATH and return list of (ISO HEADING-DISPLAY NOTES).
NOTES is a list of (TITLE . HTML-BODY) in document order.  The
outer list is also in document order (chronological).  When a
per-export cache is active (`arche-diary--month-data-cache') the
result is memoized by PATH, so a month rendered for its own page
is not re-parsed and re-exported for `index.html'."
  (if arche-diary--month-data-cache
      (let ((hit (gethash path arche-diary--month-data-cache 'miss)))
        (if (eq hit 'miss)
            (puthash path (arche-diary--read-month-data path)
                     arche-diary--month-data-cache)
          hit))
    (arche-diary--read-month-data path)))

(defun arche-diary--read-month-data (path)
  "Parse PATH and return its month data; see `arche-diary--month-data'.
This always reads and exports from disk, bypassing any cache."
  (with-temp-buffer
    (insert-file-contents path)
    (let ((org-inhibit-startup t))
      (delay-mode-hooks (org-mode)))
    (let (results)
      (goto-char (point-min))
      (while (re-search-forward arche-diary-date-heading-regexp nil t)
        (let* ((iso (match-string-no-properties 1))
               (line (buffer-substring-no-properties
                      (line-beginning-position) (line-end-position)))
               (heading (string-trim (substring line (length "* ")))))
          (unless (arche-diary--heading-excluded-p heading)
            (let* ((display (arche-diary--heading-strip-tags heading))
                   (block-end (save-excursion
                                (forward-line 1)
                                (if (re-search-forward "^\\* " nil t)
                                    (line-beginning-position)
                                  (point-max))))
                   (notes (save-excursion
                            (forward-line 1)
                            (arche-diary--collect-notes-after-point block-end))))
              (push (list iso display notes) results)))))
      (nreverse results))))

(defun arche-diary--nav-html (months)
  "Build a <nav> of compact month links from MONTHS.
MONTHS is a list of (YEAR MONTH ...) entries in ascending order.
Each year is rendered as `YYYY.MM/MM/...' with every MM linking
to its page, and the years are separated by spaces.  Returns the
empty string when MONTHS is empty."
  (if (null months)
      ""
    (let (groups)
      ;; Bucket months by year, keeping ascending order within each.
      (dolist (entry months)
        (let ((y (nth 0 entry)) (m (nth 1 entry)))
          (if (and groups (= (caar groups) y))
              (setcdr (car groups) (cons m (cdar groups)))
            (push (cons y (list m)) groups))))
      (setq groups (nreverse groups))
      (concat
       "<nav>"
       (mapconcat
        (lambda (group)
          (let ((y (car group)))
            (concat
             (format "%04d." y)
             (mapconcat
              (lambda (m)
                (format "<a href=\"%04d-%02d.html\">%02d</a>" y m m))
              (nreverse (cdr group))
              "/"))))
        groups
        " ")
       "</nav>"))))

(defun arche-diary--month-section-html (year month data)
  "Render DATA into an HTML fragment for YEAR/MONTH (newest first)."
  (let* ((rev-data (reverse data))
         (date-htmls
          (mapcar
           (lambda (entry)
             (let* ((display (nth 1 entry))
                    (notes (nth 2 entry))
                    (rev-notes (reverse notes))
                    (note-blocks
                     (if rev-notes
                         (mapconcat
                          (lambda (n)
                            (format
                             "<section class=\"note\">\n<h3>%s</h3>\n%s\n</section>"
                             (arche-diary--html-escape (car n))
                             (cdr n)))
                          rev-notes
                          "\n<hr class=\"note-sep\">\n")
                       "")))
               (format "<article class=\"date\">\n<h2>%s</h2>\n%s\n</article>"
                       (arche-diary--html-escape display)
                       note-blocks)))
           rev-data)))
    (concat
     (format "<h1>%04d-%02d</h1>\n" year month)
     (mapconcat #'identity date-htmls "\n<hr class=\"date-sep\">\n"))))

(defun arche-diary--links-html (links)
  "Render LINKS, a list of (URL . LABEL), as a compact link nav.
Consecutive links are divided by `arche-diary-html-links-separator'.
Return the empty string when LINKS is nil."
  (if (null links)
      ""
    (concat
     "<nav class=\"links\">"
     (mapconcat
      (lambda (l)
        (format "<a href=\"%s\">%s</a>"
                (arche-diary--html-escape (car l))
                (arche-diary--html-escape (cdr l))))
      links
      (arche-diary--html-escape arche-diary-html-links-separator))
     "</nav>")))

(defun arche-diary--external-links-new-tab (html)
  "Make external links in HTML open in a new tab.
Add `target=\"_blank\"' and `rel=\"noopener\"' to every `<a>' tag
whose href is an absolute http(s) URL and that does not already
set a target.  Relative links (page nav, the title, images) are
left untouched."
  (replace-regexp-in-string
   "<a\\b[^>]*>"
   (lambda (tag)
     (if (and (string-match-p "href=[\"']https?://" tag)
              (not (string-match-p "\\btarget=" tag)))
         (concat (substring tag 0 -1) " target=\"_blank\" rel=\"noopener\">")
       tag))
   html t t))

(defun arche-diary--html-document (title nav links body)
  "Wrap NAV, LINKS and BODY in a complete HTML document with TITLE.
TITLE is used for the document `<title>' (browser tab).  The
visible page heading is taken from `arche-diary-html-page-title'
and links to `index.html'.  LINKS is the pre-rendered useful-links
nav (see `arche-diary--links-html'); it is placed right below NAV,
the month navigation."
  (let* ((page-title (and arche-diary-html-page-title
                          (not (string-empty-p arche-diary-html-page-title))
                          arche-diary-html-page-title))
         (header (if page-title
                     (format "<header><h1><a href=\"index.html\">%s</a></h1></header>\n"
                             (arche-diary--html-escape page-title))
                   ""))
         (links (or links "")))
    (let ((doc (concat
                "<!DOCTYPE html>\n"
                (format "<html lang=\"%s\">\n"
                        (arche-diary--html-escape arche-diary-html-lang))
                "<head>\n"
                "<meta charset=\"utf-8\">\n"
                "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">\n"
                (format "<title>%s</title>\n" (arche-diary--html-escape title))
                "<style>\n" arche-diary-html-css "\n</style>\n"
                "</head>\n<body>\n"
                header
                nav "\n"
                (if (string-empty-p links) "" (concat links "\n"))
                body "\n"
                "</body>\n</html>\n")))
      (if arche-diary-html-external-links-new-tab
          (arche-diary--external-links-new-tab doc)
        doc))))

(defun arche-diary--month-html-stale-p (year month source-path)
  "Return non-nil if YEAR/MONTH's exported HTML is missing or out of date.
HTML is out of date when it does not exist, or when SOURCE-PATH is
strictly newer than it."
  (let ((html (expand-file-name (format "%04d-%02d.html" year month)
                                (arche-diary--html-directory))))
    (or (not (file-exists-p html))
        (time-less-p
         (file-attribute-modification-time (file-attributes html))
         (file-attribute-modification-time (file-attributes source-path))))))

(defun arche-diary--render-month-html (year month)
  "Render `YYYY-MM.html' for YEAR/MONTH.  Return the output path."
  (let ((path (arche-diary--month-file year month))
        (html-dir (arche-diary--html-directory)))
    (unless path
      (user-error "No diary file for %04d-%02d" year month))
    (unless (file-directory-p html-dir)
      (make-directory html-dir t))
    (let* ((months (arche-diary--find-or-list-month-files))
           (past (cl-remove-if-not
                  (lambda (e)
                    (let ((ey (nth 0 e)) (em (nth 1 e)))
                      (or (< ey year) (and (= ey year) (< em month)))))
                  months))
           (data (arche-diary--month-data path))
           (out (expand-file-name (format "%04d-%02d.html" year month)
                                  html-dir)))
      (with-temp-file out
        (insert (arche-diary--html-document
                 (format "%s — %04d-%02d"
                         arche-diary-html-page-title year month)
                 (arche-diary--nav-html past)
                 (arche-diary--links-html (arche-diary--month-links path))
                 (arche-diary--month-section-html year month data))))
      out)))

(defun arche-diary--render-index-html ()
  "Render `index.html' embedding the most recent months.  Return its path."
  (let ((html-dir (arche-diary--html-directory)))
    (unless (file-directory-p html-dir)
      (make-directory html-dir t))
    (let* ((months (arche-diary--find-or-list-month-files))
           (n (length months))
           (recent-n (min arche-diary-html-index-recent-count n))
           (recent (nthcdr (- n recent-n) months))
           (latest (car (last months)))
           (sections
            (mapconcat
             (lambda (entry)
               (let* ((y (nth 0 entry))
                      (m (nth 1 entry))
                      (data (arche-diary--month-data (nth 2 entry))))
                 (arche-diary--month-section-html y m data)))
             (reverse recent)
             "\n<hr class=\"date-sep\">\n"))
           (out (expand-file-name "index.html" html-dir)))
      (with-temp-file out
        (insert (arche-diary--html-document
                 arche-diary-html-page-title
                 (arche-diary--nav-html months)
                 (arche-diary--links-html
                  (arche-diary--month-links (nth 2 latest)))
                 sections)))
      out)))

;;;###autoload
(defun arche-diary-export-html (&optional month)
  "Export the monthly diary to HTML and rebuild `index.html'.

With no argument, export every month whose HTML is out of date —
missing, or older than its source Org file — and leave the rest
untouched.  When everything is already current this is a no-op:
neither `index.html' nor `arche-diary-after-export-hook' runs.

With a prefix argument, prompt for MONTH and force-export it.
With a double prefix argument \(\\[universal-argument]
\\[universal-argument]) or MONTH = `all', force-export every
month.  Any explicit MONTH (including `all') always rebuilds
`index.html' and runs `arche-diary-after-export-hook'."
  (interactive
   (cond
    ((equal current-prefix-arg '(16)) (list 'all))
    (current-prefix-arg
     (list (let ((s (read-from-minibuffer "Month: ")))
             (and (not (string-empty-p s)) s))))
    (t (list nil))))
  (arche-diary--with-export-caches
    (cl-flet ((finish (&optional count)
                (arche-diary--render-index-html)
                (run-hooks 'arche-diary-after-export-hook)
                (if count
                    (message
                     "arche-diary: exported %d month(s); HTML written to %s"
                     count (arche-diary--html-directory))
                  (message "arche-diary: HTML written to %s"
                           (arche-diary--html-directory)))))
      (cond
       ((eq month 'all)
        (dolist (entry (arche-diary--find-or-list-month-files))
          (arche-diary--render-month-html (nth 0 entry) (nth 1 entry)))
        (finish))
       ((null month)
        (let ((stale (cl-remove-if-not
                      (lambda (e)
                        (arche-diary--month-html-stale-p
                         (nth 0 e) (nth 1 e) (nth 2 e)))
                      (arche-diary--find-or-list-month-files))))
          (if (null stale)
              (message "arche-diary: HTML already up to date")
            (dolist (e stale)
              (arche-diary--render-month-html (nth 0 e) (nth 1 e)))
            (finish (length stale)))))
       (t
        (pcase-let ((`(,y . ,m) (arche-diary--parse-month month)))
          (arche-diary--render-month-html y m))
        (finish))))))


(provide 'arche-diary)

;;; arche-diary.el ends here
