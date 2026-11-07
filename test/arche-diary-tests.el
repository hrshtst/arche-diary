;;; arche-diary-tests.el --- ERT tests for arche-diary  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Hiroshi Atsuta

;; Author: Hiroshi Atsuta <atsuta.hiroshi@gmail.com>
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is NOT part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

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

;; The suite must not depend on exiftool or ImageMagick being installed,
;; so the stripping command is a shell one-liner that rewrites the file
;; it is handed (`sh -c SCRIPT FILE' passes FILE as $0).  It stands in
;; for a real stripper: whatever it rewrites is what a real one would
;; have rewritten, and whatever it leaves alone a real one never saw.
(defconst arche-diary-tests--fake-strip-commands
  '(("sh" "-c" "printf STRIPPED > \"$0\"")))

(defmacro arche-diary-tests--with-dir (backend &rest body)
  "Run BODY with `arche-diary' configured for a fresh temporary directory.
BACKEND is the value bound to `arche-diary-file-creation-system'."
  (declare (indent 1) (debug t))
  `(let* ((tmpdir (make-temp-file "arche-diary-test-" 'directory))
          (arche-diary-directory tmpdir)
          (arche-diary-html-directory (expand-file-name "html" tmpdir))
          (arche-diary-file-creation-system ,backend)
          (arche-diary-html-strip-image-metadata-commands
           arche-diary-tests--fake-strip-commands))
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

(ert-deftest arche-diary-tests/fill-dates-leaves-buffer-and-point ()
  (arche-diary-tests--with-dir 'plain
    (arche-diary-fill-dates "2026-05-10" "2026-05-13")
    (let ((buf (get-file-buffer
                (expand-file-name "2026-05.org" arche-diary-directory))))
      ;; The start month's buffer stays alive and current.
      (should (buffer-live-p buf))
      (should (eq (current-buffer) buf))
      ;; Point sits on the START date's heading.
      (should (looking-at-p "^\\* 2026-05-10")))))

(ert-deftest arche-diary-tests/fill-dates-keep-start-closes-other-months ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-fill-dates-keep-buffers 'start))
      ;; START is in April, so point lands in the April buffer; May was
      ;; opened only as scratch and is saved + closed.
      (arche-diary-fill-dates "2026-04-29" "2026-05-02")
      (should (eq (current-buffer)
                  (get-file-buffer
                   (expand-file-name "2026-04.org" arche-diary-directory))))
      (should (looking-at-p "^\\* 2026-04-29"))
      (should-not (get-file-buffer
                   (expand-file-name "2026-05.org" arche-diary-directory))))))

(ert-deftest arche-diary-tests/fill-dates-keep-all-keeps-every-month ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-fill-dates-keep-buffers 'all))
      (arche-diary-fill-dates "2026-04-29" "2026-05-02")
      (should (buffer-live-p
               (get-file-buffer
                (expand-file-name "2026-04.org" arche-diary-directory))))
      (should (buffer-live-p
               (get-file-buffer
                (expand-file-name "2026-05.org" arche-diary-directory)))))))

(ert-deftest arche-diary-tests/fill-dates-keeps-preexisting-buffers ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-fill-dates-keep-buffers 'start)
          ;; User already has the May buffer open before filling.
          (may (arche-diary-open-month '(2026 5))))
      (arche-diary-fill-dates "2026-04-29" "2026-05-02")
      ;; Even though May is not the start month, it is left alone.
      (should (buffer-live-p may)))))


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
                 (format "<header><h1><a href=\"index.html\">%s</a></h1></header>"
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

(ert-deftest arche-diary-tests/export-nav-lists-only-past-months ()
  (arche-diary-tests--with-dir 'plain
    ;; Create Apr, May, Jun; on the May page the nav lists only April —
    ;; the current month and any future month are excluded.
    (dolist (m '((2026 4) (2026 5) (2026 6)))
      (kill-buffer (arche-diary-open-month m)))
    (arche-diary-export-html '(2026 5))
    (let ((html (with-temp-buffer
                  (insert-file-contents
                   (expand-file-name "2026-05.html"
                                     arche-diary-html-directory))
                  (buffer-string))))
      (should (string-match-p
               "<nav>2026\\.<a href=\"2026-04.html\">04</a></nav>" html))
      ;; current month (self) and future month are not linked in the nav
      (should-not (string-match-p "2026-05\\.html" html))
      (should-not (string-match-p "2026-06\\.html" html)))))

(ert-deftest arche-diary-tests/export-nav-groups-by-year ()
  (arche-diary-tests--with-dir 'plain
    (dolist (m '((2025 11) (2025 12) (2026 1) (2026 2)))
      (kill-buffer (arche-diary-open-month m)))
    ;; Display Feb 2026: past months span two years, grouped compactly.
    (arche-diary-export-html '(2026 2))
    (let ((html (with-temp-buffer
                  (insert-file-contents
                   (expand-file-name "2026-02.html"
                                     arche-diary-html-directory))
                  (buffer-string))))
      (should (string-match-p
               (concat "<nav>"
                       "2025\\.<a href=\"2025-11.html\">11</a>"
                       "/<a href=\"2025-12.html\">12</a>"
                       " "
                       "2026\\.<a href=\"2026-01.html\">01</a>"
                       "</nav>")
               html)))))

(ert-deftest arche-diary-tests/export-index-nav-lists-all-months ()
  (arche-diary-tests--with-dir 'plain
    (dolist (m '((2026 4) (2026 5) (2026 6)))
      (kill-buffer (arche-diary-open-month m)))
    (arche-diary-export-html '(2026 6))   ; also rebuilds index.html
    (let ((html (with-temp-buffer
                  (insert-file-contents
                   (expand-file-name "index.html" arche-diary-html-directory))
                  (buffer-string))))
      ;; The index lists every month, the latest included.
      (should (string-match-p
               (concat "<nav>2026\\."
                       "<a href=\"2026-04.html\">04</a>"
                       "/<a href=\"2026-05.html\">05</a>"
                       "/<a href=\"2026-06.html\">06</a></nav>")
               html)))))

(ert-deftest arche-diary-tests/export-title-links-to-index ()
  (arche-diary-tests--with-dir 'plain
    (kill-buffer (arche-diary-open-month '(2026 5)))
    (arche-diary-export-html '(2026 5))
    (let ((html (with-temp-buffer
                  (insert-file-contents
                   (expand-file-name "2026-05.html"
                                     arche-diary-html-directory))
                  (buffer-string))))
      (should (string-match-p
               (format "<header><h1><a href=\"index.html\">%s</a></h1></header>"
                       (regexp-quote arche-diary-html-page-title))
               html)))))

(ert-deftest arche-diary-tests/export-nil-exports-when-no-html ()
  (arche-diary-tests--with-dir 'plain
    (arche-diary-fill-dates "2026-04-25" "2026-05-02")
    ;; No HTML yet, so a no-arg export should render every stale month.
    (arche-diary-export-html)
    (should (file-exists-p
             (expand-file-name "2026-04.html" arche-diary-html-directory)))
    (should (file-exists-p
             (expand-file-name "2026-05.html" arche-diary-html-directory)))
    (should (file-exists-p
             (expand-file-name "index.html" arche-diary-html-directory)))))

(ert-deftest arche-diary-tests/export-nil-noop-when-current ()
  (arche-diary-tests--with-dir 'plain
    (let ((old (encode-time 0 0 0 1 1 2000))
          (new (encode-time 0 0 0 1 1 2030)))
      (arche-diary-fill-dates "2026-05-10" "2026-05-12")
      (arche-diary-export-html '(2026 5))
      ;; Force the source older than its HTML so nothing is stale.
      (let ((src (expand-file-name "2026-05.org" arche-diary-directory))
            (html (expand-file-name "2026-05.html" arche-diary-html-directory))
            (index (expand-file-name "index.html" arche-diary-html-directory)))
        (set-file-times src old)
        (set-file-times html new)
        (set-file-times index new)
        (arche-diary-export-html)       ; nil -> no-op
        ;; Neither the month page nor the index was rewritten.
        (should (time-equal-p new (file-attribute-modification-time
                                   (file-attributes html))))
        (should (time-equal-p new (file-attribute-modification-time
                                   (file-attributes index))))))))

(ert-deftest arche-diary-tests/export-nil-only-stale-month ()
  (arche-diary-tests--with-dir 'plain
    (let ((old (encode-time 0 0 0 1 1 2000))
          (new (encode-time 0 0 0 1 1 2030)))
      (arche-diary-fill-dates "2026-04-25" "2026-05-02")
      (arche-diary-export-html 'all)
      (let ((apr-src (expand-file-name "2026-04.org" arche-diary-directory))
            (apr-html (expand-file-name "2026-04.html"
                                        arche-diary-html-directory))
            (may-src (expand-file-name "2026-05.org" arche-diary-directory))
            (may-html (expand-file-name "2026-05.html"
                                        arche-diary-html-directory)))
        ;; April: source newer than its HTML -> stale.
        (set-file-times apr-html old)
        (set-file-times apr-src new)
        ;; May: source older than its HTML -> current.
        (set-file-times may-src old)
        (set-file-times may-html new)
        (arche-diary-export-html)
        ;; April was re-rendered; May was left untouched.
        (should-not (time-equal-p old (file-attribute-modification-time
                                       (file-attributes apr-html))))
        (should (time-equal-p new (file-attribute-modification-time
                                   (file-attributes may-html))))))))

(ert-deftest arche-diary-tests/export-nil-exports-new-month ()
  (arche-diary-tests--with-dir 'plain
    (arche-diary-fill-dates "2026-04-25" "2026-04-27")
    (arche-diary-export-html '(2026 4))
    ;; A second month appears with no HTML of its own yet.
    (arche-diary-fill-dates "2026-05-01" "2026-05-02")
    (arche-diary-export-html)
    (should (file-exists-p
             (expand-file-name "2026-05.html" arche-diary-html-directory)))))

;;;; CJK line unfill

(ert-deftest arche-diary-tests/unfill-cjk-joins-cjk-break ()
  (should (equal (arche-diary--unfill-cjk "リハビリ\nがてら日記を書いた。")
                 "リハビリがてら日記を書いた。")))

(ert-deftest arche-diary-tests/unfill-cjk-keeps-ascii-space ()
  ;; A break between two non-CJK words becomes one space, exactly as a
  ;; browser would have rendered the newline.
  (should (equal (arche-diary--unfill-cjk "the quick\nbrown fox")
                 "the quick brown fox")))

(ert-deftest arche-diary-tests/unfill-cjk-drops-space-at-link-boundary ()
  (should (equal (arche-diary--unfill-cjk
                  "話をしたら\n[[http://x][近くのイベント]]で蔵の人が")
                 "話をしたら[[http://x][近くのイベント]]で蔵の人が")))

(ert-deftest arche-diary-tests/unfill-cjk-preserves-paragraph-break ()
  (should (equal (arche-diary--unfill-cjk "あいう\n\nえお")
                 "あいう\n\nえお")))

(ert-deftest arche-diary-tests/unfill-cjk-folds-list-continuation ()
  ;; A wrapped continuation folds onto its bullet; a new bullet does not.
  (should (equal (arche-diary--unfill-cjk
                  "- 起き上がる\n  ことができる\n- 次の項目")
                 "- 起き上がることができる\n- 次の項目")))

(ert-deftest arche-diary-tests/unfill-cjk-leaves-blocks-untouched ()
  (should (equal (arche-diary--unfill-cjk
                  "前置き\n#+begin_src sh\nあ\nい\n#+end_src\n後ろ")
                 "前置き\n#+begin_src sh\nあ\nい\n#+end_src\n後ろ")))

(ert-deftest arche-diary-tests/unfill-cjk-keeps-emphasis-opening-marker ()
  ;; A break before a leading emphasis marker would, if dropped, press the
  ;; marker against a CJK character — which Org will not parse.  A zero-width
  ;; space keeps the markup parseable while leaving no visible gap.
  (should (equal (arche-diary--unfill-cjk "試したら\n~Fuzzel~ が良かった。")
                 (concat "試したら" arche-diary--zero-width-space
                         "~Fuzzel~ が良かった。"))))

(ert-deftest arche-diary-tests/unfill-cjk-keeps-emphasis-closing-marker ()
  ;; The mirror case: a trailing closing marker pressed against the CJK head
  ;; of the next line.
  (should (equal (arche-diary--unfill-cjk "試した ~Fuzzel~\nが良かった。")
                 (concat "試した ~Fuzzel~" arche-diary--zero-width-space
                         "が良かった。"))))

(ert-deftest arche-diary-tests/unfill-cjk-no-zwsp-without-marker ()
  ;; An ordinary CJK fold with no marker at the boundary stays free of the
  ;; zero-width space.
  (should-not (string-match-p arche-diary--zero-width-space
                              (arche-diary--unfill-cjk
                               "リハビリ\nがてら日記を書いた。"))))

(ert-deftest arche-diary-tests/unfill-cjk-keeps-hard-line-break ()
  ;; A line ending in `\\' keeps its newline, whatever the script...
  (dolist (str '("foo\\\\\nbar"
                 "あいう\\\\\nえお"
                 "foo\\\\  \nbar"
                 "\\\\\nbar"))
    (should (equal (arche-diary--unfill-cjk str) str)))
  ;; ...and the line after it can still absorb its own continuation.
  (should (equal (arche-diary--unfill-cjk "あ\\\\\nい\nう") "あ\\\\\nいう"))
  ;; Three backslashes are not a hard break to Org, so that line still folds.
  (should (equal (arche-diary--unfill-cjk "foo\\\\\\\nbar") "foo\\\\\\ bar")))

(ert-deftest arche-diary-tests/export-keeps-hard-line-break ()
  (let ((arche-diary-html-unfill-cjk t))
    (should (string-match-p "foo<br />\\s-*bar"
                            (arche-diary--org-string-to-html "foo\\\\\nbar")))
    (should (string-match-p "あいう<br />\\s-*えお"
                            (arche-diary--org-string-to-html
                             "あいう\\\\\nえお")))))

(ert-deftest arche-diary-tests/unfill-cjk-keeps-planning-and-clock-lines ()
  (dolist (str '("*** sub\nDEADLINE: <2026-01-01 Thu>\nfoo"
                 "*** sub\nSCHEDULED: <2026-01-01 Thu>\nfoo"
                 "*** sub\nCLOSED: [2026-01-01 Thu]\nfoo"
                 "*** sub\nDeadline: tomorrow\nfoo"
                 "CLOCK: [2026-01-01 Thu 10:00]\nfoo"
                 "clock: [2026-01-01 Thu 10:00]\nfoo"
                 "foo\nCLOCK: [2026-01-01 Thu 10:00]"))
    (should (equal (arche-diary--unfill-cjk str) str)))
  ;; Org reads these as ordinary text, so they fold like any other line.
  (should (equal (arche-diary--unfill-cjk "あ\nDeadline: 明日\nい")
                 "あDeadline: 明日い"))
  (should (equal (arche-diary--unfill-cjk "*** sub\nあ\nDEADLINE: 明日\nい")
                 "*** sub\nあDEADLINE: 明日い"))
  (should (equal (arche-diary--unfill-cjk "CLOCK: 正午\nい")
                 "CLOCK: 正午い")))

(ert-deftest arche-diary-tests/unfill-cjk-leaves-latex-environments-untouched ()
  (dolist (str '("foo\n\\begin{equation}\nx=1\ny=2\n\\end{equation}\nbar"
                 ;; The inner closing line must not end the outer environment.
                 "\\begin{a}\n\\begin{b}\nx\ny\n\\end{b}\nz\nw\n\\end{a}\nbar"))
    (should (equal (arche-diary--unfill-cjk str) str)))
  ;; Lines after a closed environment fold as usual, even a one-line one.
  (should (equal (arche-diary--unfill-cjk "\\begin{a}\nx\n\\end{a}\nあ\nい")
                 "\\begin{a}\nx\n\\end{a}\nあい"))
  (should (equal (arche-diary--unfill-cjk "\\begin{a} x \\end{a}\nあ\nい")
                 "\\begin{a} x \\end{a}\nあい")))

(ert-deftest arche-diary-tests/unfill-does-not-change-non-cjk-rendering ()
  ;; Unfilling exists for CJK line breaks.  Org syntax that depends on its
  ;; line structure must come out as it would without it.
  (cl-flet ((render (str unfill)
              (let ((arche-diary-html-unfill-cjk unfill))
                ;; Headings get random ids, so those can't be compared.
                ;; Org 9.7 keeps the space after a timestamp inside its
                ;; span, which looks the same in a browser.
                (replace-regexp-in-string
                 " </span>" "</span>"
                 (replace-regexp-in-string
                  "[ \t\n]+" " "
                  (replace-regexp-in-string
                   "\\(id=\"\\)[^\"]*" "\\1"
                   (arche-diary--org-string-to-html str)))))))
    (dolist (str '("foo\nbar"
                   "foo\\\\\nbar"
                   "foo\\\\\\\nbar"
                   ": one\n: two"
                   "foo\n# hidden\nbar"
                   "foo\n-----\nbar"
                   "foo\n:LOGBOOK:\nsecret\n:END:\nbar"
                   "foo\n\\begin{equation}\nx=1\ny=2\n\\end{equation}\nbar"
                   "\\begin{a}\n\\begin{b}\nx\n\\end{b}\ny\n\\end{a}\nbar"
                   "\\begin{a} x \\end{a}\nfoo"
                   "\\begin{a}\nx \\end{a}\nfoo"
                   "\\begin{a}\nno close\nfoo"
                   "CLOCK: [2026-01-01 Thu 10:00]\nfoo"
                   "clock: [2026-01-01 Thu 10:00]\nfoo"
                   "CLOCK: at noon\nfoo"
                   "foo\nCLOCK: [2026-01-01 Thu 10:00]\nbar"
                   "*** sub\nCLOCK: [2026-01-01 Thu 10:00]\nfoo"
                   "*** sub\nDEADLINE: <2026-01-01 Thu>\nfoo"
                   "*** sub\nSCHEDULED: <2026-01-01 Thu>\nfoo"
                   "*** sub\nCLOSED: [2026-01-01 Thu]\nfoo"
                   "*** sub\nDeadline: tomorrow\nfoo"
                   "*** sub\nfirst\nDEADLINE: <2026-01-01 Thu>\nfoo"
                   "DEADLINE: tomorrow\nfoo"
                   "- item\n  more\n- next"
                   "1. one\n2. two"
                   "| a |\n| b |"
                   "*** sub\nfoo\n*** sub2\nbar"))
      (ert-info (str)
        (should (equal (render str t) (render str nil)))))))

(ert-deftest arche-diary-tests/export-keeps-text-after-planning-line ()
  (let ((html (arche-diary--org-string-to-html
               "*** sub\nDEADLINE: <2026-01-01 Thu>\nfoo")))
    (should (string-match-p "foo" html))
    (should-not (string-match-p "DEADLINE" html))))

(ert-deftest arche-diary-tests/export-unfills-cjk-lines ()
  (arche-diary-tests--with-dir 'plain
    (with-current-buffer (arche-diary-open-month '(2026 5))
      (arche-diary-add-date "15")
      (insert "** メモ\nリハビリ\nがてら日記を書いた。\n")
      (save-buffer))
    (arche-diary-export-html '(2026 5))
    (let ((html (with-temp-buffer
                  (insert-file-contents
                   (expand-file-name "2026-05.html" arche-diary-html-directory))
                  (buffer-string))))
      (should (string-match-p "リハビリがてら日記を書いた。" html))
      (should-not (string-match-p "リハビリ\nがてら" html)))))

(ert-deftest arche-diary-tests/export-unfilled-cjk-keeps-emphasis ()
  ;; An emphasis marker wrapped onto its own line after a CJK character must
  ;; still export as emphasis, not literal `~...~' text.
  (arche-diary-tests--with-dir 'plain
    (with-current-buffer (arche-diary-open-month '(2026 5))
      (arche-diary-add-date "15")
      (insert "** メモ\nクリップボードマネージャーを試したら\n~Fuzzel~ が良かった。\n")
      (save-buffer))
    (arche-diary-export-html '(2026 5))
    (let ((html (with-temp-buffer
                  (insert-file-contents
                   (expand-file-name "2026-05.html" arche-diary-html-directory))
                  (buffer-string))))
      (should (string-match-p "<code>Fuzzel</code>" html))
      (should-not (string-match-p "~Fuzzel~" html)))))

(ert-deftest arche-diary-tests/export-unfill-cjk-can-be-disabled ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-html-unfill-cjk nil))
      (with-current-buffer (arche-diary-open-month '(2026 5))
        (arche-diary-add-date "15")
        (insert "** メモ\nリハビリ\nがてら日記を書いた。\n")
        (save-buffer))
      (arche-diary-export-html '(2026 5))
      (let ((html (with-temp-buffer
                    (insert-file-contents
                     (expand-file-name "2026-05.html" arche-diary-html-directory))
                    (buffer-string))))
        (should (string-match-p "リハビリ\nがてら" html))))))

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

;;;; export-time image metadata stripping

(defun arche-diary-tests--contents (path)
  "Return the contents of PATH as a string."
  (with-temp-buffer
    (insert-file-contents-literally path)
    (buffer-string)))

(defun arche-diary-tests--write-image-note (src &optional no-copy)
  "Add a May 2026 note linking image SRC, and export it.
NO-COPY is passed to `arche-diary-insert-image', so the note links
either the diary's copy of SRC or SRC itself."
  (with-current-buffer (arche-diary-open-month '(2026 5))
    (arche-diary-add-date "15")
    (goto-char (point-max))
    (insert "** photo\n")
    (arche-diary-insert-image src no-copy)
    (save-buffer))
  (arche-diary-export-html '(2026 5)))

(ert-deftest arche-diary-tests/export-strips-image-metadata ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-image-directory
           (expand-file-name "images" arche-diary-directory))
          (arche-diary-html-strip-image-metadata-commands
           arche-diary-tests--fake-strip-commands)
          (src (expand-file-name "exif.jpg" tmpdir)))
      (with-temp-file src (insert "JPEGDATA"))
      (arche-diary-tests--write-image-note src)
      (let ((diary-copy (expand-file-name "images/2026-05-15/exif.jpg"
                                          arche-diary-directory))
            (html-copy (expand-file-name "images/2026-05-15/exif.jpg"
                                         arche-diary-html-directory)))
        ;; Only the published copy is stripped.
        (should (equal (arche-diary-tests--contents html-copy) "STRIPPED"))
        (should (equal (arche-diary-tests--contents diary-copy) "JPEGDATA"))
        (should (equal (arche-diary-tests--contents src) "JPEGDATA"))
        ;; The published copy comes from a 0600 temporary file, but must
        ;; end up with the mode bits a direct copy would have given it.
        (should (= (file-modes html-copy)
                   (logand (file-modes diary-copy) (default-file-modes))))))))

(ert-deftest arche-diary-tests/export-strips-image-linked-in-place ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-image-directory
           (expand-file-name "images" arche-diary-directory))
          (arche-diary-html-strip-image-metadata-commands
           arche-diary-tests--fake-strip-commands)
          (src (expand-file-name "inplace.jpg" tmpdir)))
      (with-temp-file src (insert "JPEGDATA"))
      ;; Inserted with NO-COPY: the note links the original where it
      ;; sits, and the export is the only thing that copies it.
      (arche-diary-tests--write-image-note src t)
      (should (equal (arche-diary-tests--contents
                      (cdr (arche-diary--export-image-dest src)))
                     "STRIPPED"))
      (should (equal (arche-diary-tests--contents src) "JPEGDATA")))))

(ert-deftest arche-diary-tests/export-same-named-images-stay-distinct ()
  (arche-diary-tests--with-dir 'plain
    (let* ((arche-diary-image-directory
            (expand-file-name "images" arche-diary-directory))
           (arche-diary-html-strip-image-metadata nil)
           (a (expand-file-name "a/x.png" tmpdir))
           (b (expand-file-name "b/x.png" tmpdir))
           (dest-a (arche-diary--export-image-dest a))
           (dest-b (arche-diary--export-image-dest b))
           (rewrite (lambda (path)
                      (arche-diary--rewrite-image-links-for-export
                       (format "[[file:%s]]" path)))))
      (dolist (f (list a b))
        (make-directory (file-name-directory f) t))
      (with-temp-file a (insert "AAAA"))
      (with-temp-file b (insert "BBBB"))
      ;; Each link points at its own destination, holding its own bytes.
      (should-not (equal (car dest-a) (car dest-b)))
      (should (equal (funcall rewrite a) (format "[[file:%s]]" (car dest-a))))
      (should (equal (funcall rewrite b) (format "[[file:%s]]" (car dest-b))))
      (should (equal (arche-diary-tests--contents (cdr dest-a)) "AAAA"))
      (should (equal (arche-diary-tests--contents (cdr dest-b)) "BBBB"))
      ;; The destination is stable and stays an image of the same type.
      (should (equal (arche-diary--export-image-dest a) dest-a))
      (should (string-match-p "\\`images/x-[0-9a-f]\\{8\\}\\.png\\'"
                              (car dest-a))))))

(ert-deftest arche-diary-tests/export-image-dest-keeps-image-dir-subtree ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-image-directory
           (expand-file-name "images" arche-diary-directory)))
      (should (equal (car (arche-diary--export-image-dest
                           (expand-file-name "2026-05-15/a.png"
                                             arche-diary-image-directory)))
                     "images/2026-05-15/a.png"))
      (should (equal (car (arche-diary--export-image-dest
                           (expand-file-name "a.png"
                                             arche-diary-image-directory)))
                     "images/a.png")))))

(ert-deftest arche-diary-tests/export-strip-can-be-disabled ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-image-directory
           (expand-file-name "images" arche-diary-directory))
          (arche-diary-html-strip-image-metadata nil)
          (arche-diary-html-strip-image-metadata-commands
           arche-diary-tests--fake-strip-commands)
          (src (expand-file-name "keep.jpg" tmpdir)))
      (with-temp-file src (insert "JPEGDATA"))
      (arche-diary-tests--write-image-note src)
      (should (equal (arche-diary-tests--contents
                      (expand-file-name "images/2026-05-15/keep.jpg"
                                        arche-diary-html-directory))
                     "JPEGDATA")))))

(ert-deftest arche-diary-tests/export-strip-skips-svg ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-image-directory
           (expand-file-name "images" arche-diary-directory))
          (arche-diary-html-strip-image-metadata-commands
           arche-diary-tests--fake-strip-commands)
          (src (expand-file-name "vec.svg" tmpdir)))
      (with-temp-file src (insert "<svg/>"))
      (arche-diary-tests--write-image-note src)
      (should (equal (arche-diary-tests--contents
                      (expand-file-name "images/2026-05-15/vec.svg"
                                        arche-diary-html-directory))
                     "<svg/>")))))

(ert-deftest arche-diary-tests/export-strip-failure-leaves-image-out ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-image-directory
           (expand-file-name "images" arche-diary-directory))
          (arche-diary-html-strip-image-metadata-commands '(("false")))
          (src (expand-file-name "fail.jpg" tmpdir))
          (warnings nil))
      (with-temp-file src (insert "JPEGDATA"))
      (cl-letf (((symbol-function 'display-warning)
                 (lambda (_type message &rest _) (push message warnings))))
        (arche-diary-tests--write-image-note src))
      ;; The original is not published, and the warning names the image.
      (should-not (file-exists-p
                   (expand-file-name "images/2026-05-15/fail.jpg"
                                     arche-diary-html-directory)))
      (should (string-match-p "fail\\.jpg" (car warnings)))
      ;; The rest of the export still completes.
      (should (file-exists-p (expand-file-name "2026-05.html"
                                               arche-diary-html-directory)))
      (should (file-exists-p (expand-file-name "index.html"
                                               arche-diary-html-directory))))))

(ert-deftest arche-diary-tests/export-stops-without-strip-program ()
  (arche-diary-tests--with-dir 'plain
    (let* ((arche-diary-image-directory
            (expand-file-name "images" arche-diary-directory))
           (hook-ran nil)
           (arche-diary-after-export-hook (list (lambda () (setq hook-ran t))))
           (src (expand-file-name "none.jpg" tmpdir))
           (html-copy (expand-file-name "images/2026-05-15/none.jpg"
                                        arche-diary-html-directory)))
      (with-temp-file src (insert "JPEGDATA"))
      (let ((arche-diary-html-strip-image-metadata-commands
             '(("arche-diary-no-such-strip-program"))))
        (should-error (arche-diary-tests--write-image-note src)
                      :type 'user-error))
      ;; Nothing was published, and the upload hook never ran.
      (should-not (file-exists-p html-copy))
      (should-not (file-exists-p (expand-file-name
                                  "index.html" arche-diary-html-directory)))
      (should-not hook-ran)
      ;; With a stripper available, a plain export picks up where it stopped.
      (arche-diary-export-html)
      (should (equal (arche-diary-tests--contents html-copy) "STRIPPED"))
      (should hook-ran))))

(ert-deftest arche-diary-tests/export-needs-strip-program-only-for-new-images ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-image-directory
           (expand-file-name "images" arche-diary-directory))
          (src (expand-file-name "old.jpg" tmpdir))
          (svg (expand-file-name "vec.svg" tmpdir))
          (page (expand-file-name "2026-05.html" arche-diary-html-directory)))
      (with-temp-file src (insert "JPEGDATA"))
      (with-temp-file svg (insert "<svg/>"))
      (arche-diary-tests--write-image-note src)
      (let ((arche-diary-html-strip-image-metadata-commands
             '(("arche-diary-no-such-strip-program"))))
        ;; A stale month whose image copy is current has nothing to strip...
        (set-file-times page '(20000 0))
        (arche-diary-export-html)
        (should (time-less-p '(20000 0) (file-attribute-modification-time
                                         (file-attributes page))))
        ;; ...and an SVG is never stripped.
        (with-current-buffer (arche-diary-open-month '(2026 5))
          (goto-char (point-max))
          (arche-diary-insert-image svg)
          (save-buffer))
        (set-file-times page '(20000 0))
        (arche-diary-export-html)
        (should (file-exists-p (expand-file-name "images/2026-05-15/vec.svg"
                                                 arche-diary-html-directory)))))))

(ert-deftest arche-diary-tests/default-strip-command-keeps-only-orientation ()
  ;; The rest of the suite stubs the stripper.  This runs the real default
  ;; command where it is installed, since its flags decide what is published.
  (skip-unless (executable-find "exiftool"))
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-html-strip-image-metadata-commands
           (eval (car (get 'arche-diary-html-strip-image-metadata-commands
                           'standard-value))
                 t))
          (src (expand-file-name "shot.jpg" tmpdir))
          (dest (expand-file-name "copy.jpg" tmpdir))
          (tags (lambda (file)
                  (with-temp-buffer
                    (call-process "exiftool" nil t nil "-s" "-G1" file)
                    (buffer-string)))))
      ;; The smallest JPEG exiftool accepts: start, scan and end markers.
      (let ((coding-system-for-write 'binary))
        (write-region (unibyte-string #xFF #xD8 #xFF #xDA #x00 #x02 #xFF #xD9)
                      nil src nil 'silent))
      (should (zerop (call-process "exiftool" nil nil nil "-q" "-q"
                                   "-overwrite_original" "-Orientation#=6"
                                   "-Make=TESTCAM" "-GPSLatitude=35"
                                   "-GPSLatitudeRef=N" src)))
      (should (string-match-p "GPSLatitude" (funcall tags src)))
      (arche-diary--copy-image-for-export src dest)
      (let ((left (funcall tags dest)))
        (should (string-match-p "Orientation +: Rotate 90 CW" left))
        (should-not (string-match-p "GPS\\|TESTCAM" left)))
      (should (string-match-p "TESTCAM" (funcall tags src))))))

(ert-deftest arche-diary-tests/forced-export-recopies-current-image ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-image-directory
           (expand-file-name "images" arche-diary-directory))
          (arche-diary-html-strip-image-metadata-commands
           arche-diary-tests--fake-strip-commands)
          (src (expand-file-name "late.jpg" tmpdir))
          (html-copy (expand-file-name "images/2026-05-15/late.jpg"
                                       arche-diary-html-directory)))
      (with-temp-file src (insert "JPEGDATA"))
      ;; Published without stripping: the copy looks current, but isn't clean.
      (let ((arche-diary-html-strip-image-metadata nil))
        (arche-diary-tests--write-image-note src))
      (should (equal (arche-diary-tests--contents html-copy) "JPEGDATA"))
      ;; A no-arg export has nothing to do, so it can't fix that...
      (arche-diary-export-html)
      (should (equal (arche-diary-tests--contents html-copy) "JPEGDATA"))
      ;; ...but forcing the month writes the image again.
      (arche-diary-export-html '(2026 5))
      (should (equal (arche-diary-tests--contents html-copy) "STRIPPED"))
      ;; So does forcing every month.
      (with-temp-file html-copy (insert "JPEGDATA"))
      (arche-diary-export-html 'all)
      (should (equal (arche-diary-tests--contents html-copy) "STRIPPED")))))

(ert-deftest arche-diary-tests/incremental-export-keeps-current-image ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-image-directory
           (expand-file-name "images" arche-diary-directory))
          (arche-diary-html-strip-image-metadata-commands
           arche-diary-tests--fake-strip-commands)
          (src (expand-file-name "kept.jpg" tmpdir))
          (html-copy (expand-file-name "images/2026-05-15/kept.jpg"
                                       arche-diary-html-directory)))
      (with-temp-file src (insert "JPEGDATA"))
      (let ((arche-diary-html-strip-image-metadata nil))
        (arche-diary-tests--write-image-note src))
      ;; The month is stale and gets rendered, but its image is not touched.
      (set-file-times (expand-file-name "2026-05.html"
                                        arche-diary-html-directory)
                      '(20000 0))
      (arche-diary-export-html)
      (should (equal (arche-diary-tests--contents html-copy) "JPEGDATA")))))

(ert-deftest arche-diary-tests/forced-month-export-leaves-other-months-images ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-image-directory
           (expand-file-name "images" arche-diary-directory))
          (arche-diary-html-strip-image-metadata-commands
           arche-diary-tests--fake-strip-commands)
          (arche-diary-html-index-recent-count 2)
          (src (expand-file-name "both.jpg" tmpdir)))
      (with-temp-file src (insert "JPEGDATA"))
      (let ((arche-diary-html-strip-image-metadata nil))
        (with-current-buffer (arche-diary-open-month '(2026 4))
          (arche-diary-add-date "15")
          (goto-char (point-max))
          (insert "** photo\n")
          (arche-diary-insert-image src)
          (save-buffer))
        (arche-diary-tests--write-image-note src))
      ;; Forcing May also rebuilds index.html, which reads April too.
      (arche-diary-export-html '(2026 5))
      (should (equal (arche-diary-tests--contents
                      (expand-file-name "images/2026-05-15/both.jpg"
                                        arche-diary-html-directory))
                     "STRIPPED"))
      (should (equal (arche-diary-tests--contents
                      (expand-file-name "images/2026-04-15/both.jpg"
                                        arche-diary-html-directory))
                     "JPEGDATA")))))

(ert-deftest arche-diary-tests/forced-export-keeps-copy-when-strip-fails ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-image-directory
           (expand-file-name "images" arche-diary-directory))
          (arche-diary-html-strip-image-metadata-commands
           arche-diary-tests--fake-strip-commands)
          (src (expand-file-name "clean.jpg" tmpdir))
          (html-copy (expand-file-name "images/2026-05-15/clean.jpg"
                                       arche-diary-html-directory)))
      (with-temp-file src (insert "JPEGDATA"))
      (arche-diary-tests--write-image-note src)
      (should (equal (arche-diary-tests--contents html-copy) "STRIPPED"))
      ;; Without a working stripper, the original must not replace the
      ;; clean copy: that would publish the metadata it was stripped of.
      (let ((arche-diary-html-strip-image-metadata-commands '(("false"))))
        (arche-diary-export-html '(2026 5))
        (should (equal (arche-diary-tests--contents html-copy) "STRIPPED")))
      (let ((arche-diary-html-strip-image-metadata-commands
             '(("arche-diary-no-such-strip-program"))))
        (should-error (arche-diary-export-html '(2026 5)) :type 'user-error)
        (should (equal (arche-diary-tests--contents html-copy) "STRIPPED")))
      ;; Not even when the copy is out of date.
      (set-file-times html-copy '(20000 0))
      (let ((arche-diary-html-strip-image-metadata-commands '(("false"))))
        (arche-diary-export-html '(2026 5))
        (should (equal (arche-diary-tests--contents html-copy) "STRIPPED"))))))

;;;; multi-image galleries

(defun arche-diary-tests--make-files (dir &rest names)
  "Create files NAMES in DIR and return their absolute paths."
  (make-directory dir t)
  (mapcar (lambda (name)
            (let ((path (expand-file-name name dir)))
              (with-temp-file path (insert "IMAGEDATA"))
              path))
          names))

(defun arche-diary-tests--count (regexp string)
  "Return how many times REGEXP matches in STRING."
  (with-temp-buffer
    (insert string)
    (goto-char (point-min))
    (how-many regexp)))

(ert-deftest arche-diary-tests/insert-gallery-puts-all-in-one-block ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-image-directory
           (expand-file-name "images" arche-diary-directory))
          (sources (arche-diary-tests--make-files
                    (expand-file-name "pics" tmpdir) "a.png" "b.png" "c.png")))
      (with-current-buffer (arche-diary-open-month '(2026 5))
        (arche-diary-add-date "15")
        (goto-char (point-max))
        (insert "** trip\n")
        (arche-diary-insert-gallery sources)
        (let ((text (buffer-string)))
          (should (= 1 (arche-diary-tests--count "^#\\+begin_gallery$" text)))
          (should (= 1 (arche-diary-tests--count "^#\\+end_gallery$" text)))
          (should (= 3 (arche-diary-tests--count "^#\\+CAPTION: $" text)))
          (should (= 3 (arche-diary-tests--count
                        (format ":width %s" arche-diary-image-gallery-width)
                        text)))
          (should (string-match-p
                   "a\\.png\\(?:.\\|\n\\)*b\\.png\\(?:.\\|\n\\)*c\\.png" text)))
        ;; Point waits on the first caption, the first one to type.
        (should (equal (arche-diary-tests--line-at-point) "#+CAPTION: "))
        (should (eolp))
        (save-excursion
          (forward-line 1)
          (should (looking-at-p "#\\+NAME: fig:a")))
        (save-buffer))
      (arche-diary-export-html '(2026 5))
      (let ((page (arche-diary-tests--page "2026-05.html")))
        (should (= 1 (arche-diary-tests--count "class=\"gallery\"" page)))
        (should (= 3 (arche-diary-tests--count "class=\"figure\"" page))))
      (should (equal (arche-diary-tests--contents
                      (expand-file-name "images/2026-05-15/c.png"
                                        arche-diary-html-directory))
                     "STRIPPED")))))

(ert-deftest arche-diary-tests/insert-gallery-appends-to-the-gallery-at-point ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-image-directory
           (expand-file-name "images" arche-diary-directory))
          (sources (arche-diary-tests--make-files
                    (expand-file-name "pics" tmpdir) "a.png" "b.png" "c.png")))
      (with-current-buffer (arche-diary-open-month '(2026 5))
        (arche-diary-add-date "15")
        (goto-char (point-max))
        (arche-diary-insert-image (car sources) nil t)
        (arche-diary-insert-gallery (cdr sources))
        (should (= 1 (arche-diary-tests--count "^#\\+begin_gallery$"
                                               (buffer-string))))
        (should (= 3 (arche-diary-tests--count "^#\\+CAPTION: $"
                                               (buffer-string))))
        ;; Point waits on the first new caption, not the old one.
        (save-excursion
          (forward-line 1)
          (should (looking-at-p "#\\+NAME: fig:b")))))))

(ert-deftest arche-diary-tests/insert-gallery-can-link-in-place ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-image-directory
           (expand-file-name "images" arche-diary-directory))
          (sources (arche-diary-tests--make-files
                    (expand-file-name "pics" tmpdir) "a.png" "b.png")))
      (with-current-buffer (arche-diary-open-month '(2026 5))
        (arche-diary-add-date "15")
        (goto-char (point-max))
        (arche-diary-insert-gallery sources t)
        (should (string-match-p "pics/a\\.png" (buffer-string))))
      (should-not (file-exists-p arche-diary-image-directory)))))

(ert-deftest arche-diary-tests/insert-gallery-changes-nothing-on-a-bad-file ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-image-directory
           (expand-file-name "images" arche-diary-directory))
          (sources (arche-diary-tests--make-files
                    (expand-file-name "pics" tmpdir) "a.png")))
      (with-current-buffer (arche-diary-open-month '(2026 5))
        (arche-diary-add-date "15")
        (goto-char (point-max))
        (let ((before (buffer-string)))
          (should-error (arche-diary-insert-gallery
                         (append sources
                                 (list (expand-file-name "missing.png" tmpdir))))
                        :type 'user-error)
          (should-error (arche-diary-insert-gallery nil) :type 'user-error)
          (should (equal (buffer-string) before))))
      (should-not (file-exists-p arche-diary-image-directory)))))

(ert-deftest arche-diary-tests/insert-gallery-uses-marks-in-a-visible-dired ()
  (arche-diary-tests--with-dir 'plain
    (let* ((arche-diary-image-directory
            (expand-file-name "images" arche-diary-directory))
           (pics (expand-file-name "pics" tmpdir))
           (dired-buffer nil))
      (arche-diary-tests--make-files pics "a.png" "b.jpg" "c.png" "notes.txt")
      (unwind-protect
          (save-window-excursion
            (setq dired-buffer (dired-noselect pics))
            (with-current-buffer dired-buffer
              (dired-mark-files-regexp "\\`\\(a\\.png\\|c\\.png\\|notes\\.txt\\)\\'"))
            (with-current-buffer (arche-diary-open-month '(2026 5))
              (arche-diary-add-date "15")
              (goto-char (point-max))
              (delete-other-windows)
              (set-window-buffer (split-window) dired-buffer)
              ;; No prompt: the marks are the answer, images only, in order.
              (cl-letf (((symbol-function 'read-directory-name)
                         (lambda (&rest _) (error "Should not prompt"))))
                (call-interactively #'arche-diary-insert-gallery))
              (let ((text (buffer-string)))
                (should (= 2 (arche-diary-tests--count "^#\\+CAPTION: $" text)))
                (should (string-match-p "a\\.png\\(?:.\\|\n\\)*c\\.png" text))
                (should-not (string-match-p "b\\.jpg\\|notes\\.txt" text)))))
        (when dired-buffer (kill-buffer dired-buffer))))))

(ert-deftest arche-diary-tests/insert-gallery-prompts-without-marks ()
  (arche-diary-tests--with-dir 'plain
    (let* ((arche-diary-image-directory
            (expand-file-name "images" arche-diary-directory))
           (pics (expand-file-name "pics" tmpdir))
           (dired-buffer nil)
           (offered nil))
      (pcase-let ((`(,old ,new ,_) (arche-diary-tests--make-files
                                    pics "old.png" "new.jpg" "notes.txt")))
        (set-file-times old '(20000 0))
        (set-file-times new '(30000 0)))
      (unwind-protect
          (save-window-excursion
            ;; An open Dired with nothing marked doesn't count.
            (setq dired-buffer (dired-noselect pics))
            (with-current-buffer (arche-diary-open-month '(2026 5))
              (arche-diary-add-date "15")
              (goto-char (point-max))
              (delete-other-windows)
              (set-window-buffer (split-window) dired-buffer)
              (cl-letf (((symbol-function 'read-directory-name)
                         (lambda (&rest _) pics))
                        ((symbol-function 'completing-read-multiple)
                         (lambda (_prompt table &rest _)
                           (setq offered (all-completions "" table))
                           (should (eq (alist-get 'display-sort-function
                                                  (cdr (funcall table "" nil 'metadata)))
                                       'identity))
                           '("old.png" "new.jpg"))))
                (call-interactively #'arche-diary-insert-gallery))
              ;; Images only, newest first; inserted in the order picked.
              (should (equal offered '("new.jpg" "old.png")))
              (should (string-match-p "old\\.png\\(?:.\\|\n\\)*new\\.jpg"
                                      (buffer-string)))))
        (when dired-buffer (kill-buffer dired-buffer))))))

(ert-deftest arche-diary-tests/insert-gallery-prompt-needs-an-image ()
  (arche-diary-tests--with-dir 'plain
    (let ((pics (expand-file-name "pics" tmpdir)))
      (arche-diary-tests--make-files pics "notes.txt")
      (cl-letf (((symbol-function 'read-directory-name)
                 (lambda (&rest _) pics)))
        (should-error (arche-diary--read-images-from-directory)
                      :type 'user-error)))))

(ert-deftest arche-diary-tests/insert-gallery-prefix-inverts-copying ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-image-directory
           (expand-file-name "images" arche-diary-directory))
          (arche-diary-image-copy t)
          (sources (arche-diary-tests--make-files
                    (expand-file-name "pics" tmpdir) "a.png")))
      (cl-letf (((symbol-function 'arche-diary--read-images-from-directory)
                 (lambda () sources)))
        (with-current-buffer (arche-diary-open-month '(2026 5))
          (arche-diary-add-date "15")
          (goto-char (point-max))
          (let ((current-prefix-arg '(4)))
            (call-interactively #'arche-diary-insert-gallery))
          (should (string-match-p "pics/a\\.png" (buffer-string)))
          (should-not (file-exists-p arche-diary-image-directory))
          (let ((current-prefix-arg nil))
            (call-interactively #'arche-diary-insert-gallery))
          (should (string-match-p "images/2026-05-15/a\\.png" (buffer-string))))))))

;;;; entry links

(defun arche-diary-tests--write-month (month text)
  "Append TEXT to the Org file of 2026's MONTH."
  (with-current-buffer (arche-diary-open-month (list 2026 month))
    (goto-char (point-max))
    (insert text)
    (save-buffer)))

(defun arche-diary-tests--page (name)
  "Return exported page NAME, decoded so that Japanese can be matched."
  (with-temp-buffer
    (insert-file-contents (expand-file-name name arche-diary-html-directory))
    (buffer-string)))

(defun arche-diary-tests--line-at-point ()
  "Return the current line."
  (buffer-substring-no-properties (line-beginning-position) (line-end-position)))

(ert-deftest arche-diary-tests/export-gives-entries-anchors ()
  (arche-diary-tests--with-dir 'plain
    (arche-diary-tests--write-month
     5 (concat "* 2026-05-15 Friday\n"
               "** 富士山 ハイク\nFIRST\n"
               "** 富士山 ハイク\nSECOND\n"
               "** hidden :noexport:\nnot published\n"
               "** a/b <c> & d?\nsymbols\n"
               "** ???\nonly symbols\n"))
    (arche-diary-export-html '(2026 5))
    (let ((page (arche-diary-tests--page "2026-05.html")))
      (should (string-match-p "<article class=\"date\" id=\"2026-05-15\">" page))
      ;; The plain anchor stays with the first in document order, so adding a
      ;; note later doesn't move anything that already has a link to it.
      (should (string-match-p
               "<section class=\"note\" id=\"2026-05-15-富士山-ハイク\">\n<h3>[^<]*</h3>\n<p>\nFIRST"
               page))
      (should (string-match-p
               "<section class=\"note\" id=\"2026-05-15-富士山-ハイク-2\">\n<h3>[^<]*</h3>\n<p>\nSECOND"
               page))
      (should (string-match-p "id=\"2026-05-15-a-b-c-d\"" page))
      (should (string-match-p "id=\"2026-05-15-note\"" page))
      (should-not (string-match-p "hidden" page)))))

(ert-deftest arche-diary-tests/diary-link-exports-to-its-entry ()
  (arche-diary-tests--with-dir 'plain
    (arche-diary-tests--write-month
     4 "* 2026-04-10 Friday\n** 花見\nbody\n")
    (cl-flet ((html (str) (arche-diary--org-string-to-html str)))
      (should (string-match-p
               (regexp-quote "<a href=\"2026-04.html#2026-04-10\">the day</a>")
               (html "[[arche-diary:2026-04-10][the day]]")))
      (should (string-match-p
               (regexp-quote "<a href=\"2026-04.html#2026-04-10-花見\">a note</a>")
               (html "[[arche-diary:2026-04-10::花見][a note]]")))
      ;; Without a description, the heading is the text.
      (should (string-match-p (regexp-quote ">2026-04-10 Friday</a>")
                              (html "[[arche-diary:2026-04-10]]")))
      (should (string-match-p (regexp-quote ">花見</a>")
                              (html "[[arche-diary:2026-04-10::花見]]")))
      ;; A description keeps its markup, and folds into Japanese text.
      (should (string-match-p (regexp-quote "><b>the</b> day</a>")
                              (html "[[arche-diary:2026-04-10][*the* day]]")))
      (should (string-match-p
               (regexp-quote "以前は<a href=\"2026-04.html#2026-04-10\">こちら</a>を参照")
               (html "以前は\n[[arche-diary:2026-04-10][こちら]]\nを参照"))))))

(ert-deftest arche-diary-tests/diary-link-lands-on-an-anchor-across-months ()
  (arche-diary-tests--with-dir 'plain
    (arche-diary-tests--write-month
     4 "* 2026-04-10 Friday\n** 花見\nbody\n** a/b c\nbody\n")
    (arche-diary-tests--write-month
     5 (concat "* 2026-05-15 Friday\n** back\n"
               "[[arche-diary:2026-04-10]] [[arche-diary:2026-04-10::花見]] "
               "[[arche-diary:2026-04-10::a/b c]]\n"))
    (arche-diary-export-html 'all)
    (let ((may (arche-diary-tests--page "2026-05.html"))
          (april (arche-diary-tests--page "2026-04.html"))
          (start 0)
          (found 0))
      (while (string-match "href=\"2026-04\\.html#\\([^\"]+\\)\"" may start)
        (setq start (match-end 0)
              found (1+ found))
        (should (string-match-p (format "id=\"%s\"" (match-string 1 may)) april)))
      (should (= found 3)))))

(ert-deftest arche-diary-tests/diary-link-without-a-published-target-is-plain-text ()
  (arche-diary-tests--with-dir 'plain
    (arche-diary-tests--write-month
     4 (concat "* 2026-04-10 Friday\n** public\nx\n"
               "** 秘密のメモ :noexport:\ny\n"
               "* 2026-04-11 Saturday :noexport:\n** 別の秘密\nz\n"))
    (let ((warnings nil))
      (cl-letf (((symbol-function 'display-warning)
                 (lambda (_type message &rest _) (push message warnings))))
        (dolist (path '("2026-04-10::秘密のメモ" ; a :noexport: note
                        "2026-04-11::別の秘密"   ; under a :noexport: date
                        "2026-04-11"            ; a :noexport: date
                        "2026-04-10::renamed"   ; a heading that changed
                        "2026-04-12"            ; a date that isn't there
                        "2026-09-01"            ; a month that isn't there
                        "not-a-date"))
          (let ((html (arche-diary--org-string-to-html
                       (format "[[arche-diary:%s]]" path))))
            (should-not (string-match-p "<a " html))
            ;; A title in a URL or as the text would publish a hidden note's.
            (should-not (string-match-p "秘密" html))))
        (should (= (length warnings) 7))
        (should (string-match-p "not-a-date" (car warnings)))
        ;; Its own description is still the author's text to show.
        (should (string-match-p
                 "see it"
                 (arche-diary--org-string-to-html "[[arche-diary:2026-04-12][see it]]")))))))

(ert-deftest arche-diary-tests/diary-link-follow-opens-its-entry ()
  (arche-diary-tests--with-dir 'plain
    (arche-diary-tests--write-month
     4 (concat "* 2026-04-10 Friday\n** first\nx\n** 花見 :tag:\ny\n"
               "* 2026-04-11 Saturday\n** 花見\nz\n"))
    (let ((file (arche-diary--month-file 2026 4)))
      (cl-flet ((opened (path)
                  (arche-diary-link-follow path)
                  (with-current-buffer (get-file-buffer file)
                    (arche-diary-tests--line-at-point))))
        (should (equal (opened "2026-04-10") "* 2026-04-10 Friday"))
        (should (equal (opened "2026-04-10::花見") "** 花見 :tag:"))
        ;; The same title under another date is another note.
        (should (equal (opened "2026-04-11::花見") "** 花見"))
        (with-current-buffer (get-file-buffer file)
          (should (string-match-p "2026-04-11"
                                  (save-excursion
                                    (re-search-backward "^\\* ")
                                    (arche-diary-tests--line-at-point)))))
        ;; A renamed note still gets you to its date.
        (should (equal (opened "2026-04-10::gone") "* 2026-04-10 Friday")))
      (dolist (path '("2026-04-20" "2026-09-01" "not-a-date"))
        (should-error (arche-diary-link-follow path) :type 'user-error))
      ;; And Org itself reaches it from a link in a buffer.
      (with-temp-buffer
        (org-mode)
        (insert "[[arche-diary:2026-04-11]]")
        (goto-char 3)
        (org-open-at-point))
      (with-current-buffer (get-file-buffer file)
        (should (equal (arche-diary-tests--line-at-point)
                       "* 2026-04-11 Saturday"))))))

(ert-deftest arche-diary-tests/entry-candidates-are-published-and-newest-first ()
  (arche-diary-tests--with-dir 'plain
    (arche-diary-tests--write-month
     4 "* 2026-04-10 Friday\n** old\nx\n** hidden :noexport:\ny\n")
    (arche-diary-tests--write-month
     5 (concat "* 2026-05-01 Friday\n** a\nx\n** b\ny\n"
               "* 2026-05-02 Saturday :noexport:\n** gone\nz\n"
               "* 2026-05-03 Sunday\n"))
    (should (equal (mapcar #'car (arche-diary--entry-candidates))
                   '("2026-05-03 Sunday"
                     "2026-05-01 Friday"
                     "2026-05-01 Friday / a"
                     "2026-05-01 Friday / b"
                     "2026-04-10 Friday"
                     "2026-04-10 Friday / old")))))

(ert-deftest arche-diary-tests/insert-entry-link-writes-a-working-link ()
  (arche-diary-tests--with-dir 'plain
    (arche-diary-tests--write-month
     4 "* 2026-04-10 Friday\n** 花見 [1]\nx\n")
    (cl-letf (((symbol-function 'completing-read)
               (lambda (_prompt table &rest _)
                 ;; The picker keeps its newest-first order.
                 (should (eq (alist-get 'display-sort-function
                                        (cdr (funcall table "" nil 'metadata)))
                             'identity))
                 "2026-04-10 Friday / 花見 [1]")))
      (with-temp-buffer
        (org-mode)
        (insert "see ")
        (call-interactively #'arche-diary-insert-entry-link)
        (should (string-prefix-p "see [[arche-diary:" (buffer-string)))
        ;; Org follows a closing bracket in a description with a zero-width
        ;; space, so as not to end the link early; that part isn't ours.
        (should (string-match-p
                 (regexp-quote "<a href=\"2026-04.html#2026-04-10-花見-1\">花見 [1]")
                 (arche-diary--org-string-to-html (buffer-string))))))
    ;; With text selected, that text is what becomes the link.
    (cl-letf (((symbol-function 'completing-read)
               (lambda (&rest _) "2026-04-10 Friday")))
      (with-temp-buffer
        (org-mode)
        (insert "see word now")
        (let ((transient-mark-mode t))
          (goto-char 5)
          (push-mark 9 t t)
          (call-interactively #'arche-diary-insert-entry-link))
        (should (equal (buffer-string)
                       "see [[arche-diary:2026-04-10][word]] now"))))))

(ert-deftest arche-diary-tests/insert-entry-link-needs-an-entry ()
  (arche-diary-tests--with-dir 'plain
    (with-temp-buffer
      (org-mode)
      (should-error (call-interactively #'arche-diary-insert-entry-link)
                    :type 'user-error))))

(ert-deftest arche-diary-tests/export-reads-a-linked-month-once ()
  (arche-diary-tests--with-dir 'plain
    (arche-diary-tests--write-month
     4 "* 2026-04-10 Friday\n** a\nx\n** b\ny\n")
    (arche-diary-tests--write-month
     5 "* 2026-05-15 Friday\n** n\n[[arche-diary:2026-04-10]] [[arche-diary:2026-04-10::a]] [[arche-diary:2026-04-10::b]]\n")
    (let ((reads 0)
          (original (symbol-function 'arche-diary--read-month-data)))
      (cl-letf (((symbol-function 'arche-diary--read-month-data)
                 (lambda (path &optional titles-only)
                   (when titles-only (setq reads (1+ reads)))
                   (funcall original path titles-only))))
        (arche-diary-export-html '(2026 5)))
      (should (= reads 1)))))

;;;; several diaries

(defmacro arche-diary-tests--with-two-diaries (&rest body)
  "Run BODY with the diaries \"first\" and \"second\" configured.
The fixture's own directories stay bound as the global settings, as they
would be in a config that used a single diary before adding a second."
  (declare (indent 0) (debug t))
  `(arche-diary-tests--with-dir 'plain
     (let* ((first-dir (expand-file-name "notes/first" tmpdir))
            (second-dir (expand-file-name "notes/second" tmpdir))
            (first-html (expand-file-name "www/first" tmpdir))
            (second-html (expand-file-name "www/second" tmpdir))
            (arche-diary--selected-diary nil)
            (arche-diary-diaries
             (list (list "first"
                         (cons 'arche-diary-directory first-dir)
                         (cons 'arche-diary-html-directory first-html)
                         (cons 'arche-diary-html-page-title "FIRST-TITLE"))
                   (list "second"
                         (cons 'arche-diary-directory second-dir)
                         (cons 'arche-diary-html-directory second-html)
                         (cons 'arche-diary-html-page-title "SECOND-TITLE")))))
       (make-directory first-dir t)
       (make-directory second-dir t)
       ,@body)))

(defun arche-diary-tests--read-file (path)
  "Return the contents of PATH, decoded."
  (with-temp-buffer
    (insert-file-contents path)
    (buffer-string)))

(defun arche-diary-tests--diary-buffer (dir month text)
  "Return a buffer visiting 2026's MONTH in diary DIR, holding TEXT."
  (let ((path (expand-file-name (format "2026-%02d.org" month) dir)))
    (with-temp-file path
      (insert (format "#+title: 2026-%02d\n\n" month) text))
    (find-file-noselect path)))

(ert-deftest arche-diary-tests/no-diaries-means-the-global-settings ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-diaries nil))
      (should-not (arche-diary-current-diary))
      (with-temp-buffer
        (arche-diary-open-month '(2026 5)))
      (should (file-exists-p (expand-file-name "2026-05.org" tmpdir))))))

(ert-deftest arche-diary-tests/diaries-keep-their-files-and-pages-apart ()
  (arche-diary-tests--with-two-diaries
    (with-temp-buffer
      ;; With nothing selected, the first one is current.
      (should (equal (arche-diary-current-diary) "first"))
      (arche-diary-tests--write-month 5 "* 2026-05-15 Friday\n** FIRST-NOTE\nx\n")
      (arche-diary-export-html 'all))
    (with-temp-buffer
      (arche-diary-select-diary "second")
      (with-temp-buffer
        (should (equal (arche-diary-current-diary) "second"))
        (arche-diary-tests--write-month 5 "* 2026-05-15 Friday\n** SECOND-NOTE\nx\n")
        (arche-diary-export-html 'all)))
    (let ((first-page (arche-diary-tests--read-file
                       (expand-file-name "2026-05.html" first-html)))
          (second-page (arche-diary-tests--read-file
                        (expand-file-name "2026-05.html" second-html))))
      (should (string-match-p "FIRST-NOTE" first-page))
      (should (string-match-p "FIRST-TITLE" first-page))
      (should-not (string-match-p "SECOND" first-page))
      (should (string-match-p "SECOND-NOTE" second-page))
      (should (string-match-p "SECOND-TITLE" second-page))
      (should-not (string-match-p "FIRST" second-page)))
    ;; The global directories, shared by nothing here, stay untouched.
    (should-not (file-exists-p arche-diary-html-directory))
    (should-not (file-exists-p (expand-file-name "2026-05.org" tmpdir)))))

(ert-deftest arche-diary-tests/diaries-commands-follow-the-current-buffer ()
  (arche-diary-tests--with-two-diaries
    (let ((src (car (arche-diary-tests--make-files
                     (expand-file-name "pics" tmpdir) "shot.png")))
          (first-buffer (arche-diary-tests--diary-buffer
                         first-dir 5 "* 2026-05-15 Friday\n** FIRST-NOTE\nx\n"))
          (second-buffer (arche-diary-tests--diary-buffer
                          second-dir 5 "* 2026-05-15 Friday\n** SECOND-NOTE\nx\n")))
      ;; The first diary is selected, but this buffer is in the second.
      (should (equal (with-current-buffer first-buffer
                       (arche-diary-current-diary))
                     "first"))
      (with-current-buffer second-buffer
        (should (equal (arche-diary-current-diary) "second"))
        (arche-diary-add-date "16")
        (goto-char (point-max))
        (insert "** photo\n")
        (arche-diary-insert-image src)
        (save-buffer)
        (should (file-exists-p
                 (expand-file-name "images/2026-05-16/shot.png" second-dir)))
        (should-not (file-exists-p (expand-file-name "images" first-dir)))
        ;; Exporting from here writes the second diary's page.
        (arche-diary-export-html '(2026 5))
        (should (file-exists-p (expand-file-name "2026-05.html" second-html)))
        (should (file-exists-p
                 (expand-file-name "images/2026-05-16/shot.png" second-html)))
        (should-not (file-exists-p first-html))
        ;; Filling dates writes here, and leaves the first diary alone.
        (arche-diary-fill-dates "2026-05-20" "2026-05-20")
        (should (string-match-p
                 "2026-05-20"
                 (arche-diary-tests--read-file
                  (expand-file-name "2026-05.org" second-dir))))
        (should-not (string-match-p
                     "2026-05-20"
                     (arche-diary-tests--read-file
                      (expand-file-name "2026-05.org" first-dir)))))
      ;; Visiting a date and following a link stay in the diary too.
      (with-current-buffer second-buffer
        (should (file-in-directory-p
                 (buffer-file-name (arche-diary-visit-date "2026-05-15"))
                 second-dir))
        (arche-diary-link-follow "2026-05-15")
        (should (file-in-directory-p (buffer-file-name (window-buffer))
                                     second-dir))))))

(ert-deftest arche-diary-tests/diaries-resolve-links-within-themselves ()
  (arche-diary-tests--with-two-diaries
    (arche-diary-tests--diary-buffer
     first-dir 4 "* 2026-04-10 Friday\n** only in first\nx\n")
    (arche-diary-tests--diary-buffer
     second-dir 4 "* 2026-04-10 Friday\n** only in second\nx\n")
    (let ((buffer (arche-diary-tests--diary-buffer
                   second-dir 5
                   (concat "* 2026-05-15 Friday\n** n\n"
                           "[[arche-diary:2026-04-10::only in second]] "
                           "[[arche-diary:2026-04-10::only in first]]\n")))
          (warnings nil))
      ;; The first diary is selected, and a note exports in a temporary
      ;; buffer, which belongs to neither.  The diary doesn't change.
      (with-current-buffer buffer
        (cl-letf (((symbol-function 'display-warning)
                   (lambda (_type message &rest _) (push message warnings))))
          (arche-diary-export-html '(2026 5))))
      (let ((page (arche-diary-tests--read-file
                   (expand-file-name "2026-05.html" second-html))))
        (should (string-match-p "href=\"2026-04.html#2026-04-10-only-in-second\"" page))
        (should-not (string-match-p "only-in-first" page)))
      (should (= (length warnings) 1))
      ;; The picker offers this diary's entries only.
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt table &rest _)
                   (let ((offered (all-completions "" table)))
                     (should (member "2026-04-10 Friday / only in second" offered))
                     (should-not (member "2026-04-10 Friday / only in first" offered)))
                   "2026-04-10 Friday")))
        (with-current-buffer buffer
          (goto-char (point-max))
          (call-interactively #'arche-diary-insert-entry-link))))))

(ert-deftest arche-diary-tests/diary-without-output-settings-stays-in-its-directory ()
  ;; Falling back to the global html directory would overwrite another
  ;; diary's pages, and its upload hook would publish them.
  (arche-diary-tests--with-dir 'plain
    (let* ((bare (expand-file-name "notes/bare" tmpdir))
           (arche-diary--selected-diary nil)
           (arche-diary-image-directory (expand-file-name "global-images" tmpdir))
           (arche-diary-diaries (list (list "bare" (cons 'arche-diary-directory bare))))
           (src (car (arche-diary-tests--make-files
                      (expand-file-name "pics" tmpdir) "shot.png"))))
      (make-directory bare t)
      (with-current-buffer (arche-diary-tests--diary-buffer
                            bare 5 "* 2026-05-15 Friday\n** note\n")
        (goto-char (point-max))
        (arche-diary-insert-image src)
        (save-buffer)
        (arche-diary-export-html '(2026 5)))
      (should (file-exists-p (expand-file-name "html/2026-05.html" bare)))
      (should (file-exists-p (expand-file-name "images/2026-05-15/shot.png" bare)))
      (should (file-exists-p (expand-file-name "html/images/2026-05-15/shot.png" bare)))
      (should-not (file-exists-p arche-diary-html-directory))
      (should-not (file-exists-p arche-diary-image-directory)))))

(ert-deftest arche-diary-tests/diary-must-set-its-directory ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary--selected-diary nil)
          (arche-diary-diaries (list (list "oops" (cons 'arche-diary-html-page-title "x")))))
      (with-temp-buffer
        (should-error (arche-diary-open-month '(2026 5)) :type 'user-error))
      (should-not (file-exists-p (expand-file-name "2026-05.org" tmpdir))))))

(ert-deftest arche-diary-tests/select-diary-opens-that-diary-from-anywhere ()
  (arche-diary-tests--with-two-diaries
    (with-current-buffer (arche-diary-tests--diary-buffer first-dir 5 "")
      ;; The current buffer can't decide here: this is how you get across.
      (let ((buffer (arche-diary-select-diary "second")))
        (should (file-in-directory-p (buffer-file-name buffer) second-dir))))
    (with-temp-buffer
      (should (equal (arche-diary-current-diary) "second")))
    (should-error (arche-diary-select-diary "nope") :type 'user-error)
    ;; Interactively, the choice comes from the configured names.
    (cl-letf (((symbol-function 'completing-read)
               (lambda (_prompt names &rest _)
                 (should (equal names '("first" "second")))
                 "first")))
      (call-interactively #'arche-diary-select-diary)
      (with-temp-buffer
        (should (equal (arche-diary-current-diary) "first")))))
  (let ((arche-diary-diaries nil))
    (should-error (call-interactively #'arche-diary-select-diary)
                  :type 'user-error)))

(ert-deftest arche-diary-tests/export-hook-sees-its-diary ()
  (arche-diary-tests--with-two-diaries
    (let* ((seen nil)
           (arche-diary-after-export-hook
            (list (lambda ()
                    (setq seen (list (arche-diary-current-diary)
                                     arche-diary-html-directory))))))
      (with-current-buffer (arche-diary-tests--diary-buffer second-dir 5 "")
        (arche-diary-export-html '(2026 5)))
      (should (equal seen (list "second" second-html))))))

(ert-deftest arche-diary-tests/diary-settings-reach-a-command-s-prompts ()
  (arche-diary-tests--with-two-diaries
    ;; Whether to copy is worked out in the command's interactive form.
    (setcdr (assoc "second" arche-diary-diaries)
            (cons (cons 'arche-diary-image-copy nil)
                  (cdr (assoc "second" arche-diary-diaries))))
    (let ((src (car (arche-diary-tests--make-files
                     (expand-file-name "pics" tmpdir) "shot.png"))))
      (cl-letf (((symbol-function 'read-file-name) (lambda (&rest _) src)))
        (with-current-buffer (arche-diary-tests--diary-buffer
                              second-dir 5 "* 2026-05-15 Friday\n")
          (goto-char (point-max))
          (call-interactively #'arche-diary-insert-image)
          (should (string-match-p "pics/shot\\.png" (buffer-string))))
        (with-current-buffer (arche-diary-tests--diary-buffer
                              first-dir 5 "* 2026-05-15 Friday\n")
          (goto-char (point-max))
          (call-interactively #'arche-diary-insert-image)
          (should (string-match-p "images/2026-05-15/shot\\.png"
                                  (buffer-string))))))))

(ert-deftest arche-diary-tests/diary-is-found-through-a-symlink ()
  (arche-diary-tests--with-dir 'plain
    (let* ((real (expand-file-name "dropbox/invest" tmpdir))
           (link (expand-file-name "invest-link" tmpdir))
           (arche-diary--selected-diary nil)
           (arche-diary-diaries
            (list (list "other" (cons 'arche-diary-directory
                                      (expand-file-name "other" tmpdir)))
                  (list "invest" (cons 'arche-diary-directory link)))))
      (make-directory real t)
      (make-symbolic-link real link)
      (with-current-buffer (arche-diary-tests--diary-buffer real 5 "")
        (should (equal (arche-diary-current-diary) "invest"))))))

(ert-deftest arche-diary-tests/diary-can-use-the-denote-backend ()
  (arche-diary-tests--with-two-diaries
    (setcdr (assoc "second" arche-diary-diaries)
            (cons (cons 'arche-diary-file-creation-system 'denote)
                  (cdr (assoc "second" arche-diary-diaries))))
    (arche-diary-select-diary "second")
    (with-temp-buffer
      (let ((buffer (arche-diary-open-month '(2026 5))))
        (should (file-in-directory-p (buffer-file-name buffer) second-dir))
        (should (string-match-p "--2026-05__" (buffer-file-name buffer)))
        (with-current-buffer buffer
          (goto-char (point-max))
          (insert "* 2026-05-15 Friday\n** denote note\nx\n")
          (save-buffer)
          (arche-diary-export-html '(2026 5))))
      (should (string-match-p "denote note"
                              (arche-diary-tests--read-file
                               (expand-file-name "2026-05.html" second-html)))))))

(ert-deftest arche-diary-tests/every-command-runs-in-its-diary ()
  ;; A new command left out of this would use the global settings, and
  ;; write to the wrong diary.
  (let ((missing nil))
    (mapatoms
     (lambda (symbol)
       (let ((name (symbol-name symbol)))
         (when (and (commandp symbol)
                    (string-prefix-p "arche-diary-" name)
                    (not (string-prefix-p "arche-diary--" name))
                    (not (string-prefix-p "arche-diary-tests" name))
                    (not (eq symbol 'arche-diary-select-diary))
                    (not (advice-member-p #'arche-diary--in-current-diary symbol)))
           (push symbol missing)))))
    (should-not missing))
  (should (advice-member-p #'arche-diary--in-current-diary
                           'arche-diary-link-follow)))

;;;; math

(ert-deftest arche-diary-tests/export-escapes-math-for-html ()
  (let ((html (arche-diary--org-string-to-html
               (concat "inline \\(a<b\\), dollar $c<d$ here\n\n"
                       "\\[e<f\\]\n\n"
                       "\\begin{align}\ng &= h \\\\\ni &< j\n\\end{align}\n\n"
                       "~k<l~"))))
    ;; The browser would read `<b' as the start of a tag.
    (should (string-match-p (regexp-quote "\\(a&lt;b\\)") html))
    (should (string-match-p (regexp-quote "\\(c&lt;d\\)") html))
    (should (string-match-p (regexp-quote "\\[e&lt;f\\]") html))
    (should (string-match-p (regexp-quote "g &amp;= h") html))
    (should (string-match-p (regexp-quote "i &amp;&lt; j") html))
    ;; Everything else was escaped by Org already, and only once.
    (should (string-match-p (regexp-quote "<code>k&lt;l</code>") html))
    (should-not (string-match-p "&amp;lt;" html))))

(ert-deftest arche-diary-tests/export-math-ignores-org-latex-setting ()
  ;; An image renderer would write files the export knows nothing about,
  ;; and escaping would corrupt the <img> tag it returns.
  (let ((org-html-with-latex 'dvipng))
    (should (string-match-p (regexp-quote "\\(a&lt;b\\)")
                            (arche-diary--org-string-to-html "\\(a<b\\)")))))

(ert-deftest arche-diary-tests/html-document-loads-mathjax-only-with-math ()
  (cl-flet ((doc (body) (arche-diary--html-document "t" "" "" body)))
    (let ((arche-diary-html-mathjax-url "https://example.com/mj.js?a=1&b=2"))
      (dolist (body '("<p>\\(x\\)</p>"
                      "<p>\\[x\\]</p>"
                      "\\begin{equation}\nx\n\\end{equation}"))
        (should (string-match-p
                 (regexp-quote
                  "<script async src=\"https://example.com/mj.js?a=1&amp;b=2\"></script>\n</head>")
                 (doc body))))
      (should-not (string-match-p "<script" (doc "<p>$5 and C:\\dir (x)</p>"))))
    (let ((arche-diary-html-mathjax-url nil))
      (should-not (string-match-p "<script" (doc "<p>\\(x\\)</p>"))))))

(ert-deftest arche-diary-tests/export-loads-mathjax-on-pages-with-math ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-html-index-recent-count 1))
      (with-current-buffer (arche-diary-open-month '(2026 4))
        (arche-diary-add-date "15")
        (goto-char (point-max))
        (insert "** plain\nno math here\n")
        (save-buffer))
      (with-current-buffer (arche-diary-open-month '(2026 5))
        (arche-diary-add-date "15")
        (goto-char (point-max))
        (insert "** study\nsee \\(a<b\\) here\n")
        (save-buffer))
      (arche-diary-export-html 'all)
      (cl-flet ((page (name) (arche-diary-tests--contents
                              (expand-file-name name
                                                arche-diary-html-directory))))
        (should-not (string-match-p "<script" (page "2026-04.html")))
        (should (string-match-p "<script" (page "2026-05.html")))
        ;; The index embeds May, so it needs the script too.
        (should (string-match-p "<script" (page "index.html")))))))

;;;; examples/upload-diary

(defconst arche-diary-tests--upload-script
  (expand-file-name "../examples/upload-diary"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "The sample deploy script, tested against a `file://' fake server.")

(defun arche-diary-tests--run-upload (local remote &rest env)
  "Run the upload script from LOCAL to REMOTE with extra ENV strings.
Return (EXIT-STATUS . OUTPUT)."
  (let ((process-environment
         (append (list "DIARY_FTP_HOST=file:///"
                       (concat "DIARY_FTP_REMOTE=" remote)
                       (concat "ARCHE_DIARY_HTML_DIR=" local))
                 env
                 process-environment)))
    (with-temp-buffer
      (let ((status (call-process "sh" nil t nil
                                  arche-diary-tests--upload-script)))
        (cons status (buffer-string))))))

(defun arche-diary-tests--write-site (dir mtime &rest files)
  "Create DIR holding FILES, each containing MTIME's number, dated MTIME."
  (make-directory dir t)
  (dolist (f files)
    (let ((path (expand-file-name f dir)))
      (with-temp-file path (insert (format "%S" mtime)))
      (set-file-times path mtime))))

(ert-deftest arche-diary-tests/upload-refuses-to-delete-by-default ()
  (skip-unless (executable-find "lftp"))
  (arche-diary-tests--with-dir 'plain
    (let ((local (expand-file-name "local" tmpdir))
          (remote (expand-file-name "remote" tmpdir)))
      ;; A partial local folder: what a single-month export leaves on a
      ;; machine whose html directory was empty.
      (arche-diary-tests--write-site remote '(20000 0)
                                     "2026-05.html" "2026-10.html" "index.html")
      (arche-diary-tests--write-site local '(20001 0)
                                     "2026-10.html" "index.html")
      ;; Refused, naming what it would delete, with nothing transferred.
      (let ((result (arche-diary-tests--run-upload local remote)))
        (should-not (zerop (car result)))
        (should (string-match-p "2026-05\\.html" (cdr result))))
      (should (file-exists-p (expand-file-name "2026-05.html" remote)))
      (should (equal (arche-diary-tests--contents
                      (expand-file-name "index.html" remote))
                     "(20000 0)"))
      ;; A dry run is always allowed: it deletes nothing.
      (let ((result (arche-diary-tests--run-upload
                     local remote
                     "DIARY_MIRROR_FLAGS=--dry-run --reverse --delete")))
        (should (zerop (car result))))
      (should (file-exists-p (expand-file-name "2026-05.html" remote)))
      ;; Asked for explicitly, the deletion goes ahead.
      (let ((result (arche-diary-tests--run-upload
                     local remote "DIARY_ALLOW_DELETE=1")))
        (should (zerop (car result))))
      (should-not (file-exists-p (expand-file-name "2026-05.html" remote)))
      (should (equal (arche-diary-tests--contents
                      (expand-file-name "index.html" remote))
                     "(20001 0)")))))

(ert-deftest arche-diary-tests/upload-proceeds-when-nothing-would-be-deleted ()
  (skip-unless (executable-find "lftp"))
  (arche-diary-tests--with-dir 'plain
    (let ((local (expand-file-name "local" tmpdir))
          (remote (expand-file-name "remote" tmpdir)))
      (arche-diary-tests--write-site remote '(20000 0) "2026-10.html")
      (arche-diary-tests--write-site local '(20001 0)
                                     "2026-10.html" "index.html")
      (should (zerop (car (arche-diary-tests--run-upload local remote))))
      (should (equal (arche-diary-tests--contents
                      (expand-file-name "2026-10.html" remote))
                     "(20001 0)"))
      (should (file-exists-p (expand-file-name "index.html" remote))))))

(ert-deftest arche-diary-tests/image-copy-current-p-ignores-size ()
  (arche-diary-tests--with-dir 'plain
    (let ((src (expand-file-name "src.jpg" tmpdir))
          (dest (expand-file-name "dest.jpg" tmpdir)))
      (with-temp-file src (insert "JPEGDATA-WITH-METADATA"))
      ;; A stripped copy is smaller than its source; as long as it is not
      ;; older it is current, or every export would strip it again.
      (with-temp-file dest (insert "JPEGDATA"))
      (set-file-times src '(20000 0))
      (set-file-times dest '(20001 0))
      (should (arche-diary--image-copy-current-p src dest))
      ;; An older copy is still stale.
      (set-file-times dest '(19999 0))
      (should-not (arche-diary--image-copy-current-p src dest)))))

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

(ert-deftest arche-diary-tests/export-omits-noexport-note ()
  (arche-diary-tests--with-dir 'plain
    (with-current-buffer (arche-diary-open-month '(2026 5))
      (arche-diary-add-date "15")
      (insert "** Public note\nshown body.\n")
      (insert "** Secret note    :noexport:\nhidden body.\n")
      (save-buffer))
    (arche-diary-export-html '(2026 5))
    (let ((html (with-temp-buffer
                  (insert-file-contents
                   (expand-file-name "2026-05.html"
                                     arche-diary-html-directory))
                  (buffer-string))))
      (should (string-match-p "<h3>Public note</h3>" html))
      (should (string-match-p "shown body" html))
      (should-not (string-match-p "Secret note" html))
      (should-not (string-match-p "hidden body" html))
      ;; The tag itself must never leak into the output.
      (should-not (string-match-p "noexport" html)))))

(ert-deftest arche-diary-tests/export-omits-noexport-date ()
  (arche-diary-tests--with-dir 'plain
    (with-current-buffer (arche-diary-open-month '(2026 5))
      (arche-diary-add-date "15")
      (insert "** Visible\nshown body.\n")
      (arche-diary-add-date "16")
      ;; Tag the whole day; the date heading keeps its ISO prefix so it
      ;; still matches `arche-diary-date-heading-regexp'.
      (save-excursion
        (goto-char (point-min))
        (when (re-search-forward "^\\* 2026-05-16.*$" nil t)
          (replace-match (concat (match-string 0) "    :noexport:") t t)))
      (goto-char (point-max))
      (insert "** Confidential\nhidden body.\n")
      (save-buffer))
    (arche-diary-export-html '(2026 5))
    (let ((html (with-temp-buffer
                  (insert-file-contents
                   (expand-file-name "2026-05.html"
                                     arche-diary-html-directory))
                  (buffer-string))))
      (should (string-match-p "2026-05-15" html))
      (should (string-match-p "shown body" html))
      (should-not (string-match-p "2026-05-16" html))
      (should-not (string-match-p "Confidential" html))
      (should-not (string-match-p "hidden body" html)))))

(ert-deftest arche-diary-tests/export-omits-noexport-subheading ()
  (arche-diary-tests--with-dir 'plain
    (with-current-buffer (arche-diary-open-month '(2026 5))
      (arche-diary-add-date "15")
      (insert "** Mixed note\nintro text.\n*** Secret part    :noexport:\nhidden detail.\n")
      (save-buffer))
    (arche-diary-export-html '(2026 5))
    (let ((html (with-temp-buffer
                  (insert-file-contents
                   (expand-file-name "2026-05.html"
                                     arche-diary-html-directory))
                  (buffer-string))))
      (should (string-match-p "intro text" html))
      (should-not (string-match-p "Secret part" html))
      (should-not (string-match-p "hidden detail" html)))))

(ert-deftest arche-diary-tests/export-renders-links ()
  (arche-diary-tests--with-dir 'plain
    ;; Assert the bare link markup; new-tab rewriting has its own tests.
    (let ((arche-diary-html-external-links-new-tab nil))
      (with-current-buffer (arche-diary-open-month '(2026 5))
        (goto-char (point-max))
        (insert "* Links\n"
                "- [[https://conf.example.com][ConfX]]\n"
                "- [[https://journal.example.com/login][Journal login]]\n")
        (arche-diary-add-date "15")
        (insert "** Note\nbody.\n")
        (save-buffer))
      ;; A later month gives the page a month nav to position against; it
      ;; inherits May's links on creation.
      (with-current-buffer (arche-diary-open-month '(2026 6))
        (arche-diary-add-date "3")
        (insert "** N\nb.\n")
        (save-buffer))
      (arche-diary-export-html 'all)
      (let ((html (with-temp-buffer
                    (insert-file-contents
                     (expand-file-name "2026-06.html"
                                       arche-diary-html-directory))
                    (buffer-string))))
        (should (string-match-p "<nav class=\"links\">" html))
        (should (string-match-p
                 "<a href=\"https://conf.example.com\">ConfX</a>" html))
        (should (string-match-p
                 "<a href=\"https://journal.example.com/login\">Journal login</a>"
                 html))
        ;; Links are divided by the separator, not by whitespace alone.
        (should (string-match-p
                 "</a> | <a href=\"https://journal.example.com/login\">" html))
        ;; ConfX comes before Journal login (document order).
        (should (< (string-match "ConfX" html)
                   (string-match "Journal login" html)))
        ;; The links list sits below the month navigation.
        (should (< (string-match "<nav>" html)
                   (string-match "<nav class=\"links\">" html)))
        ;; The links heading is not exported as a date section.
        (should-not (string-match-p "<h2>Links" html))))))

(ert-deftest arche-diary-tests/links-html-uses-separator ()
  (let ((links '(("https://a.example" . "A") ("https://b.example" . "B"))))
    (let ((arche-diary-html-links-separator " | "))
      (should (string-match-p "</a> | <a " (arche-diary--links-html links))))
    (let ((arche-diary-html-links-separator " / "))
      (should (string-match-p "</a> / <a " (arche-diary--links-html links))))
    (should (equal "" (arche-diary--links-html nil)))))

(ert-deftest arche-diary-tests/index-shows-latest-month-links ()
  (arche-diary-tests--with-dir 'plain
    (with-current-buffer (arche-diary-open-month '(2026 5))
      (goto-char (point-max))
      (insert "* Links\n- [[https://may.example.com][MayLink]]\n")
      (arche-diary-add-date "15")
      (insert "** N\nb.\n")
      (save-buffer))
    (with-current-buffer (arche-diary-open-month '(2026 6))
      ;; June inherits May's links on creation; give it its own instead.
      (goto-char (point-min))
      (while (re-search-forward "[Mm]ay" nil t)
        (replace-match (if (equal (match-string 0) "May") "June" "june") t t))
      (arche-diary-add-date "3")
      (insert "** N\nb.\n")
      (save-buffer))
    (let ((arche-diary-html-external-links-new-tab nil))
      (arche-diary-export-html 'all)
      (let ((html (with-temp-buffer
                    (insert-file-contents
                     (expand-file-name "index.html" arche-diary-html-directory))
                    (buffer-string))))
        (should (string-match-p
                 "<a href=\"https://june.example.com\">JuneLink</a>" html))
        (should-not (string-match-p "MayLink" html))
        (should-not (string-match-p "may.example.com" html))))))

(ert-deftest arche-diary-tests/new-month-inherits-links ()
  (arche-diary-tests--with-dir 'plain
    (with-current-buffer (arche-diary-open-month '(2026 5))
      (goto-char (point-max))
      (insert "* Links\n"
              "- [[https://conf.example.com][ConfX]]\n"
              "- [[https://journal.example.com/login][Journal login]]\n")
      (save-buffer))
    (let* ((june (arche-diary--ensure-monthly-file 2026 6))
           (content (with-temp-buffer
                      (insert-file-contents june)
                      (buffer-string))))
      (should (string-match-p "^\\* Links$" content))
      (should (string-match-p
               "\\[\\[https://conf.example.com\\]\\[ConfX\\]\\]" content))
      (should (string-match-p "Journal login" content))
      ;; The inherited subtree sits above any date heading.
      (should (or (null (string-match arche-diary-date-heading-regexp content))
                  (< (string-match "^\\* Links$" content)
                     (string-match arche-diary-date-heading-regexp content)))))))

(ert-deftest arche-diary-tests/links-disabled-no-inherit-no-render ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-links-heading nil))
      (with-current-buffer (arche-diary-open-month '(2026 5))
        (goto-char (point-max))
        (insert "* Links\n- [[https://conf.example.com][ConfX]]\n")
        (arche-diary-add-date "15")
        (insert "** N\nb.\n")
        (save-buffer))
      (let ((june (arche-diary--ensure-monthly-file 2026 6)))
        (should-not (string-match-p
                     "Links"
                     (with-temp-buffer (insert-file-contents june)
                                       (buffer-string)))))
      (arche-diary-export-html '(2026 5))
      (let ((html (with-temp-buffer
                    (insert-file-contents
                     (expand-file-name "2026-05.html"
                                       arche-diary-html-directory))
                    (buffer-string))))
        (should-not (string-match-p "nav class=\"links\"" html))))))

(ert-deftest arche-diary-tests/external-links-open-new-tab ()
  (arche-diary-tests--with-dir 'plain
    (with-current-buffer (arche-diary-open-month '(2026 5))
      (goto-char (point-max))
      (insert "* Links\n- [[https://conf.example.com][ConfX]]\n")
      (arche-diary-add-date "15")
      (insert "** Note\n"
              "See [[https://external.example.org/p][paper]] "
              "and [[file:images/x.png][local]].\n")
      (save-buffer))
    (arche-diary-export-html '(2026 5))
    (let ((html (with-temp-buffer
                  (insert-file-contents
                   (expand-file-name "2026-05.html"
                                     arche-diary-html-directory))
                  (buffer-string))))
      ;; Header link (external) opens in a new tab.
      (should (string-match-p
               "<a href=\"https://conf.example.com\" target=\"_blank\" rel=\"noopener\">"
               html))
      ;; Note-body link (external) opens in a new tab.
      (should (string-match-p
               "<a href=\"https://external.example.org/p\" target=\"_blank\" rel=\"noopener\">"
               html))
      ;; The relative title link is left in place.
      (should (string-match-p "<a href=\"index.html\">" html))
      (should-not (string-match-p "index.html\" target=" html))
      ;; The relative image-file link is left in place.
      (should-not (string-match-p "images/x.png\" target=" html)))))

(ert-deftest arche-diary-tests/external-links-new-tab-can-be-disabled ()
  (arche-diary-tests--with-dir 'plain
    (let ((arche-diary-html-external-links-new-tab nil))
      (with-current-buffer (arche-diary-open-month '(2026 5))
        (goto-char (point-max))
        (insert "* Links\n- [[https://conf.example.com][ConfX]]\n")
        (arche-diary-add-date "15")
        (insert "** N\nb.\n")
        (save-buffer))
      (arche-diary-export-html '(2026 5))
      (let ((html (with-temp-buffer
                    (insert-file-contents
                     (expand-file-name "2026-05.html"
                                       arche-diary-html-directory))
                    (buffer-string))))
        (should (string-match-p "<a href=\"https://conf.example.com\">" html))
        (should-not (string-match-p "target=\"_blank\"" html))))))

;;;; Export performance caches

(ert-deftest arche-diary-tests/image-copy-current-p ()
  (let* ((dir (make-temp-file "arche-img-" 'directory))
         (src (expand-file-name "a.png" dir))
         (dest (expand-file-name "b.png" dir)))
    (unwind-protect
        (progn
          ;; Missing destination is never current.
          (with-temp-file src (insert "PNG-CONTENT"))
          (should-not (arche-diary--image-copy-current-p src dest))
          ;; A copy that is not older than its source is current, so equal
          ;; mtimes count.  Each mtime is set: writes made in the same clock
          ;; tick would get equal ones.
          (copy-file src dest t)
          (set-file-times src '(100 0))
          (set-file-times dest '(200 0))
          (should (arche-diary--image-copy-current-p src dest))
          (set-file-times src '(200 0))
          (should (arche-diary--image-copy-current-p src dest))
          ;; An edited source, newer than the copy, makes it stale.
          (with-temp-file src (insert "PNG-CONTENT-EDITED"))
          (set-file-times src '(300 0))
          (should-not (arche-diary--image-copy-current-p src dest))
          ;; Copying it again restores currency.
          (copy-file src dest t)
          (should (arche-diary--image-copy-current-p src dest)))
      (delete-directory dir 'recursive))))

(ert-deftest arche-diary-tests/export-caches-suppress-org-modules ()
  ;; The export scope pins `org-modules-loaded' so the first export in a
  ;; session does not pay `org-load-modules-maybe' (loading Gnus/EWW/etc.),
  ;; and it must not leak: the user's value is restored on exit.
  (let ((org-modules-loaded nil))
    (arche-diary--with-export-caches
      (should (eq org-modules-loaded t)))
    (should (eq org-modules-loaded nil))))

(ert-deftest arche-diary-tests/month-files-cache-shares-one-scan ()
  ;; Within the cache scope, the listing is frozen: a file created after
  ;; the scope opens is not seen until the scope is rebuilt.
  (arche-diary-tests--with-dir 'plain
    (arche-diary--ensure-monthly-file 2026 5)
    (arche-diary--with-export-caches
      (should (= 1 (length (arche-diary--find-or-list-month-files))))
      (arche-diary--ensure-monthly-file 2026 6)
      ;; Still 1: served from the cache, not re-scanned.
      (should (= 1 (length (arche-diary--find-or-list-month-files)))))
    ;; Outside the scope the fresh file is visible.
    (should (= 2 (length (arche-diary--find-or-list-month-files))))))

(ert-deftest arche-diary-tests/month-data-cache-memoizes-by-path ()
  ;; Within the cache scope, a month parsed once is not re-read: editing
  ;; the file on disk does not change the cached result.
  (arche-diary-tests--with-dir 'plain
    (let ((path (arche-diary--ensure-monthly-file 2026 5)))
      (with-current-buffer (arche-diary-open-month '(2026 5))
        (arche-diary-add-date "15")
        (insert "** N\nfirst.\n")
        (save-buffer))
      (arche-diary--with-export-caches
        (let ((first (arche-diary--month-data path)))
          ;; Mutate the source on disk behind the cache's back.
          (with-temp-file path
            (insert-file-contents path)
            (goto-char (point-max))
            (insert "* 2026-06-16 Tuesday\n** M\nsecond.\n"))
          (should (equal first (arche-diary--month-data path)))))
      ;; A fresh scope reflects the new content.
      (arche-diary--with-export-caches
        (should (= 2 (length (arche-diary--month-data path))))))))

;;; arche-diary-tests.el ends here
