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
nav ul { list-style:none; padding:0; margin:0 0 1rem 0;
         font-size:.9rem; color:var(--muted); }
nav li { display:inline-block; margin-right:.5rem; }
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

(defun arche-diary--find-or-list-month-files ()
  "Return list of (YEAR MONTH PATH) for every monthly diary file.
Sorted in ascending chronological order."
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

(defun arche-diary--ensure-monthly-file (year month)
  "Return path of monthly file for YEAR/MONTH, creating it if needed."
  (or (arche-diary--month-file year month)
      (pcase arche-diary-file-creation-system
        ('plain (arche-diary--create-plain-file year month))
        ('denote (arche-diary--create-denote-file year month))
        (other (user-error
                "Unknown arche-diary-file-creation-system: %S" other)))))


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
             (unless (and (file-exists-p absdest)
                          (arche-diary--files-identical-p abs absdest))
               (copy-file abs absdest t))
             (format "[[file:%s]%s]" reldest desc))
         m)))
   str t t))

(defun arche-diary--org-string-to-html (str)
  "Render Org-formatted STR to an HTML fragment (body only).
Image file links are copied into the html directory and
rewritten so the exported page can resolve them."
  (let* ((org-export-with-toc nil)
         (org-export-with-section-numbers nil)
         (org-export-with-broken-links t)
         (org-export-with-author nil)
         (org-export-with-creator nil)
         (org-export-with-title nil)
         (org-html-htmlize-output-type (if (featurep 'htmlize) 'inline-css nil))
         (str (arche-diary--rewrite-image-links-for-export str)))
    (string-trim (or (org-export-string-as str 'html t) ""))))

(defun arche-diary--collect-notes-after-point (bound)
  "Collect level-2 notes between point and BOUND, in document order.
Each entry is a cons (TITLE . HTML-BODY)."
  (let (results)
    (save-excursion
      (while (re-search-forward "^\\*\\* +\\(.*\\)$" bound t)
        (let* ((title (string-trim (match-string-no-properties 1)))
               (body-start (min (1+ (line-end-position)) (point-max)))
               (body-end (save-excursion
                           (if (re-search-forward "^\\*\\*? " bound t)
                               (line-beginning-position)
                             bound)))
               (body-text (buffer-substring-no-properties body-start body-end))
               (body-html (arche-diary--org-string-to-html body-text)))
          (push (cons title body-html) results))))
    (nreverse results)))

(defun arche-diary--month-data (path)
  "Read PATH and return list of (ISO HEADING-DISPLAY NOTES).
NOTES is a list of (TITLE . HTML-BODY) in document order.  The
outer list is also in document order (chronological)."
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
               (display (string-trim (substring line (length "* "))))
               (block-end (save-excursion
                            (forward-line 1)
                            (if (re-search-forward "^\\* " nil t)
                                (line-beginning-position)
                              (point-max))))
               (notes (save-excursion
                        (forward-line 1)
                        (arche-diary--collect-notes-after-point block-end))))
          (push (list iso display notes) results)))
      (nreverse results))))

(defun arche-diary--nav-html (months &optional current)
  "Build a <nav> with links to MONTHS (a list of (Y M PATH)).
CURRENT, if non-nil, is a (Y . M) cons rendered as plain text."
  (let ((items
         (mapconcat
          (lambda (entry)
            (let* ((y (nth 0 entry))
                   (m (nth 1 entry))
                   (label (format "%04d-%02d" y m))
                   (href (format "%04d-%02d.html" y m)))
              (if (equal (cons y m) current)
                  (format "<li><strong>%s</strong></li>" label)
                (format "<li><a href=\"%s\">%s</a></li>" href label))))
          months
          "\n")))
    (concat "<nav><ul>\n"
            "<li><a href=\"index.html\">index</a></li>\n"
            items
            "\n</ul></nav>")))

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

(defun arche-diary--html-document (title nav body)
  "Wrap NAV and BODY in a complete HTML document with TITLE.
TITLE is used for the document `<title>' (browser tab).  The
visible page heading at the top of the body is taken from
`arche-diary-html-page-title' and emitted only when that is
non-empty."
  (concat
   "<!DOCTYPE html>\n"
   (format "<html lang=\"%s\">\n"
           (arche-diary--html-escape arche-diary-html-lang))
   "<head>\n"
   "<meta charset=\"utf-8\">\n"
   "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">\n"
   (format "<title>%s</title>\n" (arche-diary--html-escape title))
   "<style>\n" arche-diary-html-css "\n</style>\n"
   "</head>\n<body>\n"
   (if (and arche-diary-html-page-title
            (not (string-empty-p arche-diary-html-page-title)))
       (format "<header><h1>%s</h1></header>\n"
               (arche-diary--html-escape arche-diary-html-page-title))
     "")
   nav "\n"
   body "\n"
   "</body>\n</html>\n"))

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
           (current (cons year month))
           (eligible (cl-remove-if
                      (lambda (e)
                        (let ((ey (nth 0 e)) (em (nth 1 e)))
                          (or (> ey year) (and (= ey year) (> em month)))))
                      months))
           (data (arche-diary--month-data path))
           (out (expand-file-name (format "%04d-%02d.html" year month)
                                  html-dir)))
      (with-temp-file out
        (insert (arche-diary--html-document
                 (format "%s — %04d-%02d"
                         arche-diary-html-page-title year month)
                 (arche-diary--nav-html eligible current)
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
           (older (butlast months recent-n))
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
                 (arche-diary--nav-html older nil)
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
      (finish)))))


(provide 'arche-diary)

;;; arche-diary.el ends here
