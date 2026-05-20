;;; arche-diary-tests.el --- ERT tests for arche-diary  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Hiroshi Atsuta

;; Author: Hiroshi Atsuta <atsuta.hiroshi@gmail.com>

;; This file is NOT part of GNU Emacs.

;;; Commentary:

;; Run the tests with `make test', or directly:
;;
;;   emacs -Q --batch \
;;     -L . -L test -L /path/to/denote \
;;     -l test/arche-diary-tests.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'arche-diary)

;;;; Fixture

(defmacro arche-diary-tests--with-dir (backend &rest body)
  "Run BODY with `arche-diary' configured for a fresh temporary directory.
BACKEND is the value bound to `arche-diary-file-creation-system'."
  (declare (indent 1) (debug t))
  `(let* ((tmpdir (make-temp-file "arche-diary-test-" 'directory))
          (arche-diary-directory tmpdir)
          (arche-diary-html-directory (expand-file-name "html" tmpdir))
          (arche-diary-file-creation-system ,backend))
     (unwind-protect
         (progn ,@body)
       (dolist (b (buffer-list))
         (when (and (buffer-file-name b)
                    (file-in-directory-p (buffer-file-name b) tmpdir))
           (with-current-buffer b (set-buffer-modified-p nil))
           (kill-buffer b)))
       (when (file-directory-p tmpdir)
         (delete-directory tmpdir 'recursive)))))


;;;; Pure parsing helpers

(ert-deftest arche-diary-tests/parse-month-nil-is-current ()
  (let ((now (decode-time)))
    (should (equal (arche-diary--parse-month nil)
                   (cons (decoded-time-year now)
                         (decoded-time-month now))))))

(ert-deftest arche-diary-tests/parse-month-offsets ()
  (let* ((now (decode-time))
         (cur-y (decoded-time-year now))
         (cur-m (decoded-time-month now)))
    (should (equal (arche-diary--parse-month -1)
                   (arche-diary--add-months-to cur-y cur-m -1)))
    (should (equal (arche-diary--parse-month -2)
                   (arche-diary--add-months-to cur-y cur-m -2)))
    (should (equal (arche-diary--parse-month 'last-month)
                   (arche-diary--parse-month -1)))
    (should (equal (arche-diary--parse-month "-1")
                   (arche-diary--parse-month -1)))
    (should (equal (arche-diary--parse-month "+2")
                   (arche-diary--add-months-to cur-y cur-m 2)))))

(ert-deftest arche-diary-tests/parse-month-bare-numbers ()
  (let ((year (decoded-time-year (decode-time))))
    (should (equal (arche-diary--parse-month 5) (cons year 5)))
    (should (equal (arche-diary--parse-month "05") (cons year 5)))
    (should (equal (arche-diary--parse-month '(5)) (cons year 5)))))

(ert-deftest arche-diary-tests/parse-month-explicit ()
  (should (equal (arche-diary--parse-month '(2026 7)) (cons 2026 7)))
  (should (equal (arche-diary--parse-month '(2026 . 7)) (cons 2026 7)))
  (should (equal (arche-diary--parse-month "2026-07") (cons 2026 7)))
  (should (equal (arche-diary--parse-month "2026/07") (cons 2026 7)))
  (should (equal (arche-diary--parse-month "May 2024") (cons 2024 5)))
  (should (equal (arche-diary--parse-month "may 2024") (cons 2024 5))))

(ert-deftest arche-diary-tests/parse-month-errors ()
  (should-error (arche-diary--parse-month 13) :type 'user-error)
  (should-error (arche-diary--parse-month "13") :type 'user-error)
  (should-error (arche-diary--parse-month "foobar") :type 'user-error))

(ert-deftest arche-diary-tests/add-months-to ()
  (should (equal (arche-diary--add-months-to 2026 5 0) (cons 2026 5)))
  (should (equal (arche-diary--add-months-to 2026 5 -5) (cons 2025 12)))
  (should (equal (arche-diary--add-months-to 2026 1 -1) (cons 2025 12)))
  (should (equal (arche-diary--add-months-to 2025 12 1) (cons 2026 1)))
  (should (equal (arche-diary--add-months-to 2026 5 13) (cons 2027 6))))

(ert-deftest arche-diary-tests/parse-date-today-equivalents ()
  (let ((today (arche-diary--time-to-iso (arche-diary--parse-date nil))))
    (should (string-match-p
             "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\'" today))
    (should (equal today
                   (arche-diary--time-to-iso
                    (arche-diary--parse-date 'today))))))

(ert-deftest arche-diary-tests/parse-date-relative-offsets ()
  (let ((today (arche-diary--time-to-iso (arche-diary--parse-date 'today)))
        (y1 (arche-diary--time-to-iso (arche-diary--parse-date 'yesterday)))
        (y2 (arche-diary--time-to-iso (arche-diary--parse-date -1)))
        (y3 (arche-diary--time-to-iso (arche-diary--parse-date "-1"))))
    (should (equal y1 y2))
    (should (equal y1 y3))
    (should (equal today
                   (arche-diary--time-to-iso
                    (arche-diary--day-after-iso y1))))))

(ert-deftest arche-diary-tests/parse-date-strings ()
  (should (equal (arche-diary--time-to-iso
                  (arche-diary--parse-date "2026-05-15"))
                 "2026-05-15"))
  (should (equal (arche-diary--time-to-iso
                  (arche-diary--parse-date "20261231"))
                 "2026-12-31"))
  (should (equal (arche-diary--time-to-iso
                  (arche-diary--parse-date "May 10 2024"))
                 "2024-05-10"))
  (should (equal (arche-diary--time-to-iso
                  (arche-diary--parse-date '(2024 12 31)))
                 "2024-12-31")))

(ert-deftest arche-diary-tests/parse-date-day-in-buffer-month ()
  (should (equal (arche-diary--time-to-iso
                  (arche-diary--parse-date "15" (cons 2026 7)))
                 "2026-07-15"))
  (should (equal (arche-diary--time-to-iso
                  (arche-diary--parse-date "01" (cons 2026 7)))
                 "2026-07-01")))

(ert-deftest arche-diary-tests/parse-date-mmdd-current-year ()
  (let ((year (decoded-time-year (decode-time))))
    (should (equal (arche-diary--time-to-iso
                    (arche-diary--parse-date "1231"))
                   (format "%04d-12-31" year)))))

(ert-deftest arche-diary-tests/parse-date-weekday-symbol ()
  (should-error (arche-diary--parse-date 'mon) :type 'user-error)
  (let* ((time (arche-diary--parse-date 'mon nil t))
         (dec (decode-time time))
         (today (arche-diary--parse-date 'today)))
    (should (= 1 (decoded-time-weekday dec)))
    (should (not (time-less-p today time)))
    (should (time-less-p
             (encode-time
              (decoded-time-add (decode-time today)
                                (make-decoded-time :day -7)))
             time))))


;;;; Backend — denote

(ert-deftest arche-diary-tests/open-month-denote-creates-file ()
  (arche-diary-tests--with-dir 'denote
    (let ((buf (arche-diary-open-month)))
      (should (bufferp buf))
      (should (buffer-file-name buf))
      (should (string-match-p "__diary\\.org\\'" (buffer-file-name buf)))
      (should (file-exists-p (buffer-file-name buf))))))

(ert-deftest arche-diary-tests/open-month-denote-idempotent ()
  (arche-diary-tests--with-dir 'denote
    (kill-buffer (arche-diary-open-month))
    (kill-buffer (arche-diary-open-month))
    (should (= 1 (length (arche-diary--find-or-list-month-files))))))

(ert-deftest arche-diary-tests/list-month-files-skips-non-diary ()
  (arche-diary-tests--with-dir 'denote
    (kill-buffer (arche-diary-open-month))
    (with-temp-file (expand-file-name
                     "20260101T000000--2026-01__journal.org"
                     arche-diary-directory)
      (insert "#+title:      2026-01\n"
              "#+date:       [2026-01-01 Thu 00:00]\n"
              "#+filetags:   :journal:\n"
              "#+identifier: 20260101T000000\n"))
    (let ((entries (arche-diary--find-or-list-month-files)))
      (should (= 1 (length entries)))
      (should (string-match-p "__diary\\." (nth 2 (car entries)))))))

(ert-deftest arche-diary-tests/open-month-various-formats-denote ()
  (arche-diary-tests--with-dir 'denote
    (dolist (arg '(-1 "+1" "2026-02" "May 2024" 7))
      (kill-buffer (arche-diary-open-month arg)))
    (should (>= (length (arche-diary--find-or-list-month-files)) 4))))


;;;; Backend — plain

(ert-deftest arche-diary-tests/open-month-plain-filename ()
  (arche-diary-tests--with-dir 'plain
    (let ((buf (arche-diary-open-month '(2026 5))))
      (should (equal (file-name-nondirectory (buffer-file-name buf))
                     "2026-05.org")))))

(ert-deftest arche-diary-tests/list-month-files-plain ()
  (arche-diary-tests--with-dir 'plain
    (kill-buffer (arche-diary-open-month '(2025 1)))
    (kill-buffer (arche-diary-open-month '(2026 5)))
    (let ((entries (arche-diary--find-or-list-month-files)))
      (should (equal (mapcar (lambda (e) (list (nth 0 e) (nth 1 e))) entries)
                     '((2025 1) (2026 5)))))))


;;;; add-date

(ert-deftest arche-diary-tests/add-date-today-inserts-heading ()
  (arche-diary-tests--with-dir 'plain
    (let ((buf (arche-diary-open-month)))
      (with-current-buffer buf
        (arche-diary-add-date)
        (goto-char (point-min))
        (should (re-search-forward arche-diary-date-heading-regexp nil t))
        (should (equal (match-string 1)
                       (arche-diary--time-to-iso (current-time))))))))

(ert-deftest arche-diary-tests/add-date-chronological-ordering ()
  (arche-diary-tests--with-dir 'plain
    (let ((buf (arche-diary-open-month '(2026 5))))
      (with-current-buffer buf
        (arche-diary-add-date "15")
        (arche-diary-add-date "10")
        (arche-diary-add-date "20")
        (arche-diary-add-date "12")
        (let ((isos (mapcar #'car (arche-diary--date-headings-in-buffer))))
          (should (equal isos
                         '("2026-05-10" "2026-05-12"
                           "2026-05-15" "2026-05-20"))))))))

(ert-deftest arche-diary-tests/add-date-rejects-out-of-month ()
  (arche-diary-tests--with-dir 'plain
    (let ((buf (arche-diary-open-month '(2026 5))))
      (with-current-buffer buf
        (should-error (arche-diary-add-date "2026-06-01")
                      :type 'user-error)
        (should-error (arche-diary-add-date '(2026 4 30))
                      :type 'user-error)))))

(ert-deftest arche-diary-tests/add-date-existing-is-noop ()
  (arche-diary-tests--with-dir 'plain
    (let ((buf (arche-diary-open-month '(2026 5))))
      (with-current-buffer buf
        (arche-diary-add-date "15")
        (arche-diary-add-date "15")
        (should (= 1 (length (arche-diary--date-headings-in-buffer))))))))

(ert-deftest arche-diary-tests/add-date-leaves-point-after-heading ()
  (arche-diary-tests--with-dir 'plain
    (let ((buf (arche-diary-open-month '(2026 5))))
      (with-current-buffer buf
        (arche-diary-add-date "15")
        ;; Point should be on a blank line directly under the heading
        (should (looking-at-p "^[ \t]*$"))
        (forward-line -1)
        (should (looking-at-p "^\\* 2026-05-15"))))))


;;;; visit-date / fill-dates

(ert-deftest arche-diary-tests/visit-date-creates-heading ()
  (arche-diary-tests--with-dir 'plain
    (arche-diary-visit-date "2026-05-15")
    (let ((path (expand-file-name "2026-05.org" arche-diary-directory)))
      (should (file-exists-p path)))
    (save-excursion
      (goto-char (point-min))
      (should (re-search-forward "^\\* 2026-05-15" nil t)))))

(ert-deftest arche-diary-tests/visit-date-existing-heading ()
  (arche-diary-tests--with-dir 'plain
    (arche-diary-visit-date "2026-05-15")
    (save-buffer)
    (kill-buffer (current-buffer))
    (arche-diary-visit-date "2026-05-15")
    ;; Should not have duplicated the heading
    (should (= 1 (length (arche-diary--date-headings-in-buffer))))))

(ert-deftest arche-diary-tests/fill-dates-range ()
  (arche-diary-tests--with-dir 'plain
    (arche-diary-fill-dates "2026-05-10" "2026-05-13")
    (let* ((buf (arche-diary-open-month '(2026 5)))
           (isos (with-current-buffer buf
                   (mapcar #'car (arche-diary--date-headings-in-buffer)))))
      (should (equal isos
                     '("2026-05-10" "2026-05-11"
                       "2026-05-12" "2026-05-13"))))))

(ert-deftest arche-diary-tests/fill-dates-spans-months ()
  (arche-diary-tests--with-dir 'plain
    (arche-diary-fill-dates "2026-04-29" "2026-05-02")
    (let ((apr (with-current-buffer (arche-diary-open-month '(2026 4))
                 (mapcar #'car (arche-diary--date-headings-in-buffer))))
          (may (with-current-buffer (arche-diary-open-month '(2026 5))
                 (mapcar #'car (arche-diary--date-headings-in-buffer)))))
      (should (equal apr '("2026-04-29" "2026-04-30")))
      (should (equal may '("2026-05-01" "2026-05-02"))))))

(ert-deftest arche-diary-tests/fill-dates-start-after-end-errors ()
  (arche-diary-tests--with-dir 'plain
    (should-error (arche-diary-fill-dates "2026-05-15" "2026-05-10")
                  :type 'user-error)))

(ert-deftest arche-diary-tests/fill-dates-default-start ()
  (arche-diary-tests--with-dir 'plain
    ;; Seed with a single date; expect fill to start the next day
    (with-current-buffer (arche-diary-open-month '(2026 5))
      (arche-diary-add-date "10")
      (save-buffer)
      (kill-buffer (current-buffer)))
    (arche-diary-fill-dates nil "2026-05-13")
    (let ((isos (with-current-buffer (arche-diary-open-month '(2026 5))
                  (mapcar #'car (arche-diary--date-headings-in-buffer)))))
      (should (equal isos
                     '("2026-05-10" "2026-05-11"
                       "2026-05-12" "2026-05-13"))))))


;;;; HTML export

(ert-deftest arche-diary-tests/export-writes-files ()
  (arche-diary-tests--with-dir 'plain
    (arche-diary-fill-dates "2026-05-10" "2026-05-12")
    (arche-diary-export-html '(2026 5))
    (should (file-exists-p
             (expand-file-name "2026-05.html" arche-diary-html-directory)))
    (should (file-exists-p
             (expand-file-name "index.html" arche-diary-html-directory)))))

(ert-deftest arche-diary-tests/export-reverses-date-order ()
  (arche-diary-tests--with-dir 'plain
    (let ((buf (arche-diary-open-month '(2026 5))))
      (with-current-buffer buf
        (arche-diary-add-date "10")
        (insert "** A note\nbody A.\n")
        (arche-diary-add-date "15")
        (insert "** B note\nbody B.\n")
        (save-buffer)))
    (arche-diary-export-html '(2026 5))
    (let ((html (with-temp-buffer
                  (insert-file-contents
                   (expand-file-name "2026-05.html"
                                     arche-diary-html-directory))
                  (buffer-string))))
      (should (string-match-p "<h2>2026-05-15" html))
      (should (< (string-match "2026-05-15" html)
                 (string-match "2026-05-10" html))))))

(ert-deftest arche-diary-tests/export-reverses-notes-within-day ()
  (arche-diary-tests--with-dir 'plain
    (let ((buf (arche-diary-open-month '(2026 5))))
      (with-current-buffer buf
        (arche-diary-add-date "15")
        (insert "** First\nFirst body.\n")
        (insert "** Second\nSecond body.\n")
        (save-buffer)))
    (arche-diary-export-html '(2026 5))
    (let ((html (with-temp-buffer
                  (insert-file-contents
                   (expand-file-name "2026-05.html"
                                     arche-diary-html-directory))
                  (buffer-string))))
      (should (string-match-p "<h3>First" html))
      (should (string-match-p "<h3>Second" html))
      (should (< (string-match "<h3>Second" html)
                 (string-match "<h3>First" html))))))

(ert-deftest arche-diary-tests/export-shows-page-title-on-body ()
  (arche-diary-tests--with-dir 'plain
    (arche-diary-fill-dates "2026-05-10" "2026-05-11")
    (arche-diary-export-html '(2026 5))
    (dolist (f '("2026-05.html" "index.html"))
      (let ((html (with-temp-buffer
                    (insert-file-contents
                     (expand-file-name f arche-diary-html-directory))
                    (buffer-string))))
        (should (string-match-p
                 (format "<header><h1>%s</h1></header>"
                         (regexp-quote arche-diary-html-page-title))
                 html))))))

(ert-deftest arche-diary-tests/export-all-writes-every-month ()
  (arche-diary-tests--with-dir 'plain
    (arche-diary-fill-dates "2026-04-25" "2026-05-02")
    (arche-diary-export-html 'all)
    (should (file-exists-p
             (expand-file-name "2026-04.html" arche-diary-html-directory)))
    (should (file-exists-p
             (expand-file-name "2026-05.html" arche-diary-html-directory)))
    (should (file-exists-p
             (expand-file-name "index.html" arche-diary-html-directory)))))

(ert-deftest arche-diary-tests/export-nav-omits-future-months ()
  (arche-diary-tests--with-dir 'plain
    ;; Create files for Apr, May, Jun; export May only and check nav doesn't list Jun
    (kill-buffer (arche-diary-open-month '(2026 4)))
    (kill-buffer (arche-diary-open-month '(2026 5)))
    (kill-buffer (arche-diary-open-month '(2026 6)))
    (arche-diary-export-html '(2026 5))
    (let ((html (with-temp-buffer
                  (insert-file-contents
                   (expand-file-name "2026-05.html"
                                     arche-diary-html-directory))
                  (buffer-string))))
      (should (string-match-p "2026-04\\.html" html))
      (should-not (string-match-p "2026-06\\.html" html)))))

;;;; insert-image

(ert-deftest arche-diary-tests/insert-image-copies-and-links ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-image-directory
           (expand-file-name "images" arche-diary-directory))
          (src (expand-file-name "shot.png" tmpdir)))
      (with-temp-file src (insert "PNGDATA"))
      (with-current-buffer (arche-diary-open-month '(2026 5))
        (arche-diary-add-date "15")
        (arche-diary-insert-image src)
        (let ((s (buffer-string)))
          (should (string-match-p "#\\+CAPTION: " s))
          (should (string-match-p "#\\+NAME: fig:shot\n" s))
          (should (string-match-p
                   "#\\+ATTR_HTML: :width 400 :align left\n" s))
          (should (string-match-p
                   "\\[\\[file:images/2026-05-15/shot\\.png\\]\\]" s)))
        (should (file-exists-p
                 (expand-file-name "images/2026-05-15/shot.png"
                                   arche-diary-directory)))))))

(ert-deftest arche-diary-tests/insert-image-no-copy-links-source ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-image-directory
           (expand-file-name "images" arche-diary-directory))
          (src (expand-file-name "pic.png" tmpdir)))
      (with-temp-file src (insert "DATA"))
      (with-current-buffer (arche-diary-open-month '(2026 5))
        (arche-diary-add-date "15")
        (arche-diary-insert-image src t)
        (should (string-match-p
                 (regexp-quote
                  (format "[[file:%s]]"
                          (file-relative-name src arche-diary-directory)))
                 (buffer-string)))
        (should-not (file-directory-p arche-diary-image-directory))))))

(ert-deftest arche-diary-tests/insert-image-absolute-link ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-image-directory
           (expand-file-name "images" arche-diary-directory))
          (arche-diary-image-link-type 'absolute)
          (src (expand-file-name "a.png" tmpdir)))
      (with-temp-file src (insert "X"))
      (with-current-buffer (arche-diary-open-month '(2026 5))
        (arche-diary-add-date "15")
        (arche-diary-insert-image src)
        (should (string-match-p
                 (regexp-quote
                  (format "[[file:%s]]"
                          (expand-file-name "images/2026-05-15/a.png"
                                            arche-diary-directory)))
                 (buffer-string)))))))

(ert-deftest arche-diary-tests/insert-image-no-date-subdir ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-image-directory
           (expand-file-name "images" arche-diary-directory))
          (arche-diary-image-date-subdir nil)
          (src (expand-file-name "b.png" tmpdir)))
      (with-temp-file src (insert "X"))
      (with-current-buffer (arche-diary-open-month '(2026 5))
        (arche-diary-add-date "15")
        (arche-diary-insert-image src)
        (should (file-exists-p
                 (expand-file-name "images/b.png" arche-diary-directory)))
        (should (string-match-p "\\[\\[file:images/b\\.png\\]\\]"
                                (buffer-string)))))))

(ert-deftest arche-diary-tests/insert-image-requires-date-heading ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-image-directory
           (expand-file-name "images" arche-diary-directory))
          (src (expand-file-name "c.png" tmpdir)))
      (with-temp-file src (insert "X"))
      (with-current-buffer (arche-diary-open-month '(2026 5))
        (goto-char (point-max))
        (should-error (arche-diary-insert-image src) :type 'user-error)))))

(ert-deftest arche-diary-tests/insert-image-name-uniquified ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-image-directory
           (expand-file-name "images" arche-diary-directory))
          (src (expand-file-name "dup.png" tmpdir)))
      (with-temp-file src (insert "X"))
      (with-current-buffer (arche-diary-open-month '(2026 5))
        (arche-diary-add-date "15")
        (arche-diary-insert-image src)
        (goto-char (point-max))
        (arche-diary-insert-image src)
        (let ((s (buffer-string)))
          (should (string-match-p "#\\+NAME: fig:dup\n" s))
          (should (string-match-p "#\\+NAME: fig:dup-2\n" s)))))))

(ert-deftest arche-diary-tests/directories-default-under-diary-dir ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-html-directory nil)
          (arche-diary-image-directory nil)
          (src (expand-file-name "z.png" tmpdir)))
      (should (equal (arche-diary--html-directory)
                     (expand-file-name "html" arche-diary-directory)))
      (should (equal (arche-diary--image-directory)
                     (expand-file-name "images" arche-diary-directory)))
      (with-temp-file src (insert "Z"))
      (with-current-buffer (arche-diary-open-month '(2026 5))
        (arche-diary-add-date "15")
        (insert "** Pic\n")
        (arche-diary-insert-image src)
        (save-buffer))
      (arche-diary-export-html '(2026 5))
      (should (file-exists-p
               (expand-file-name "html/2026-05.html" arche-diary-directory)))
      (should (file-exists-p
               (expand-file-name "images/2026-05-15/z.png"
                                 arche-diary-directory)))
      (should (file-exists-p
               (expand-file-name "html/images/2026-05-15/z.png"
                                 arche-diary-directory))))))

(ert-deftest arche-diary-tests/directories-explicit-override ()
  (arche-diary-tests--with-dir 'plain
    (let* ((alt (expand-file-name "alt-img" tmpdir))
           (arche-diary-image-directory alt)
           (src (expand-file-name "w.png" tmpdir)))
      (should (equal (arche-diary--image-directory) alt))
      (with-temp-file src (insert "W"))
      (with-current-buffer (arche-diary-open-month '(2026 5))
        (arche-diary-add-date "15")
        (arche-diary-insert-image src)
        (should (file-exists-p
                 (expand-file-name "2026-05-15/w.png" alt)))
        (should (string-match-p
                 (regexp-quote
                  (format "[[file:%s]]"
                          (file-relative-name
                           (expand-file-name "2026-05-15/w.png" alt)
                           arche-diary-directory)))
                 (buffer-string)))))))

(defun arche-diary-tests--count (re s)
  "Return the number of non-overlapping matches of RE in S."
  (let ((n 0) (start 0))
    (while (string-match re s start)
      (setq n (1+ n) start (match-end 0)))
    n))

(ert-deftest arche-diary-tests/insert-image-gallery-wraps ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-image-directory
           (expand-file-name "images" arche-diary-directory))
          (src (expand-file-name "g.png" tmpdir)))
      (with-temp-file src (insert "X"))
      (with-current-buffer (arche-diary-open-month '(2026 5))
        (arche-diary-add-date "15")
        (arche-diary-insert-image src nil t)
        (let ((s (buffer-string)))
          (should (string-match-p "#\\+begin_gallery\n" s))
          (should (string-match-p "#\\+end_gallery\n" s))
          (should (string-match-p "#\\+ATTR_HTML: :width 220" s))
          (should (string-match-p
                   "\\[\\[file:images/2026-05-15/g\\.png\\]\\]" s))
          ;; link sits between the begin and end markers
          (should (< (string-match "#\\+begin_gallery" s)
                     (string-match "\\[\\[file:" s)
                     (string-match "#\\+end_gallery" s))))))))

(ert-deftest arche-diary-tests/insert-image-gallery-extends ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-image-directory
           (expand-file-name "images" arche-diary-directory))
          (a (expand-file-name "p1.png" tmpdir))
          (b (expand-file-name "p2.png" tmpdir)))
      (with-temp-file a (insert "A"))
      (with-temp-file b (insert "B"))
      (with-current-buffer (arche-diary-open-month '(2026 5))
        (arche-diary-add-date "15")
        (arche-diary-insert-image a nil t)
        (arche-diary-insert-image b nil t)
        (let ((s (buffer-string)))
          ;; Still a single wrapper holding both images.
          (should (= 1 (arche-diary-tests--count "#\\+begin_gallery" s)))
          (should (= 1 (arche-diary-tests--count "#\\+end_gallery" s)))
          (should (= 2 (arche-diary-tests--count "#\\+NAME: fig:" s)))
          (should (string-match-p
                   "\\[\\[file:images/2026-05-15/p1\\.png\\]\\]" s))
          (should (string-match-p
                   "\\[\\[file:images/2026-05-15/p2\\.png\\]\\]" s))
          (should (< (string-match "#\\+begin_gallery" s)
                     (string-match "p1\\.png" s)
                     (string-match "p2\\.png" s)
                     (string-match "#\\+end_gallery" s))))))))

(ert-deftest arche-diary-tests/export-renders-gallery ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-image-directory
           (expand-file-name "images" arche-diary-directory))
          (a (expand-file-name "x1.png" tmpdir))
          (b (expand-file-name "x2.png" tmpdir)))
      (with-temp-file a (insert "A"))
      (with-temp-file b (insert "B"))
      (with-current-buffer (arche-diary-open-month '(2026 5))
        (arche-diary-add-date "15")
        (insert "** Trip\n")
        (arche-diary-insert-image a nil t)
        (arche-diary-insert-image b nil t)
        (save-buffer))
      (arche-diary-export-html '(2026 5))
      (let ((html (with-temp-buffer
                    (insert-file-contents
                     (expand-file-name "2026-05.html"
                                       arche-diary-html-directory))
                    (buffer-string))))
        (should (string-match-p "<div class=\"gallery\"" html))
        (should (string-match-p "src=\"images/2026-05-15/x1\\.png\"" html))
        (should (string-match-p "src=\"images/2026-05-15/x2\\.png\"" html))
        (should (file-exists-p
                 (expand-file-name "images/2026-05-15/x2.png"
                                   arche-diary-html-directory)))))))

(ert-deftest arche-diary-tests/export-renders-image ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-image-directory
           (expand-file-name "images" arche-diary-directory))
          (src (expand-file-name "e.png" tmpdir)))
      (with-temp-file src (insert "PNG"))
      (with-current-buffer (arche-diary-open-month '(2026 5))
        (arche-diary-add-date "15")
        (insert "** Photo\n")
        (arche-diary-insert-image src)
        (save-buffer))
      (arche-diary-export-html '(2026 5))
      (let ((html (with-temp-buffer
                    (insert-file-contents
                     (expand-file-name "2026-05.html"
                                       arche-diary-html-directory))
                    (buffer-string))))
        (should (string-match-p
                 "<img[^>]*src=\"images/2026-05-15/e\\.png\"" html))
        (should (file-exists-p
                 (expand-file-name "images/2026-05-15/e.png"
                                   arche-diary-html-directory)))))))


(provide 'arche-diary-tests)

;;; arche-diary-tests.el ends here
