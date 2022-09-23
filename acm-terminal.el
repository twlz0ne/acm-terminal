;;; acm-terminal.el --- Patch for LSP bridge acm on Terminal -*- lexical-binding: t; -*-

;; Copyright (C) 2022 Gong Qijian <gongqijian@gmail.com>

;; Author: Gong Qijian <gongqijian@gmail.com>
;; Created: 2022/07/07
;; Version: 0.1.0
;; Last-Updated: 2022-09-23 09:01:25 +0800
;;           By: Gong Qijian
;; Package-Requires: ((emacs "26.1") (acm "0.1") (popon "0.3"))
;; URL: https://github.com/twlz0ne/acm-terminal
;; Keywords: 

;; This program is free software; you can redistribute it and/or modify
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

;; Patch for LSP bridge acm on Terminal.

;; ## Requirements

;; - [lsp-bridge](https://github.com/manateelazycat/lsp-bridge) ddf03f3(2022-08-22) or newer
;; - [popon](https://codeberg.org/akib/emacs-popon)

;; ## Installation

;; Clone or download this repository (path of the folder is the `<path-to-acm-terminal>` used below).

;; ## Configuration

;; ```emacs-lisp
;; (require 'yasnippet)
;; (yas-global-mode 1)

;; (require 'lsp-bridge)
;; (global-lsp-bridge-mode)

;; (unless (display-graphic-p)
;;   (add-to-list 'load-path "<path-to-acm-terminal>")
;;   (with-eval-after-load 'acm
;;     (require 'acm-terminal)))
;; ```

;;; Code:

(require 'acm)
(require 'popon)

(defvar acm-terminal-min-width 45
  "The minimum width of the candidate menu in characters.")

(defvar acm-terminal-max-width 100
  "The maximum width of the candidate menu in characters.")

(defvar acm-terminal-doc-continuation-string "\\"
  "The string showing at the end of wrapped lines.")

(defvar acm-terminal-doc-min-width 40
  "The minimum width of the candidate doc in characters.")

(defvar acm-terminal-doc-max-width 80
  "The maximum width of the candidate doc in characters.")

(defvar-local acm-terminal-candidate-doc nil
  "Latest docstring.")

(defvar-local acm-terminal-current-input nil
  "Curent input.")

(defface acm-terminal-default-face
  '((((background dark))  :background "black")
    (((background light)) :background "white"))
  "Default face for Terminal.")

(defun acm-teminal-line-number-display-width ()
  "Return width of line number bar."
  (if (bound-and-true-p display-line-numbers-mode)
      (+ (line-number-display-width) 2)
    0))

(defun acm-terminal-nsplit-string (string width &optional cont)
  "Split STRING into substrings of length WIDTH.

If CONT non-nil, append it to each substring except the last, also, keep the
substring lenght, e.g.:

  (fn \"foobarbazq\" 3 \"↩\") => (\"fo↩\" \"ob↩\" \"ar↩\" \"q\")
  (fn \"foobarbazq\" 3)     => (\"foo\" \"bar\" \"q\") "
  (let* ((len (length string))
         (from 0)
         (step (- width (length cont)))
         (to step)
         lines)
    (if (>= to len)
        (list string)
      (while (< from len)
        (push (concat (substring string from (min to len)) cont) lines)
        (setq from to)
        (setq to (+ to step)))
      (when cont
        (setf (car lines) (substring (car lines) 0 (- (length cont)))))
      (reverse lines))))

(defun acm-terminal-init-colors (&optional force)
  (let* ((is-dark-mode (string-equal (acm-get-theme-mode) "dark"))
         (blend-background (if is-dark-mode "#000000" "#AAAAAA"))
         (default-background (let ((background (face-attribute 'default :background)))
                               (if (member background '("unspecified-bg" "unspecified"))
                                   (face-attribute 'acm-terminal-default-face :background)
                                 background))))
    ;; Make sure font size of frame same as Emacs.
    (set-face-attribute 'acm-buffer-size-face nil :height (face-attribute 'default :height))

    ;; Make sure menu follow the theme of Emacs.
    (when (or force (equal (face-attribute 'acm-default-face :background) 'unspecified))
      (set-face-background 'acm-default-face (acm-color-blend default-background blend-background (if is-dark-mode 0.8 0.9))))
    (when (or force (equal (face-attribute 'acm-select-face :background) 'unspecified))
      (set-face-background 'acm-select-face (acm-color-blend default-background blend-background 0.6)))
    (when (or force (equal (face-attribute 'acm-select-face :foreground) 'unspecified))
      (set-face-foreground 'acm-select-face (face-attribute 'font-lock-function-name-face :foreground)))))

(defun acm-terminal-get-popup-position ()
  "Return postion of menu."
  ;; The existing overlay will cause `popon-x-y-at-pos' and `posn-x-y' to get
  ;; the wrong position.
  (if acm-frame
      (let ((pos (popon-position acm-frame))
            (direction (plist-get (cdr acm-frame) :direction))
            (size (popon-size acm-frame)))
        (cons (car pos)
              (if (eq 'top direction)
                  (+ (cdr pos) (cdr size))
                (1- (cdr pos)))))
    (let ((pos (popon-x-y-at-pos acm-frame-popup-point)))
      (cons (car pos) (1+ (cdr pos))))))

(defun acm-terminal-popon-visible-p (popon)
  (when (popon-live-p popon)
    (plist-get (cdr popon) :visible)))

(defun acm-terminal-make-popon (text pos &optional window buffer priority)
  "Create an invisible popon with TEXT at POS of WINDOW.
See `popon-create' for more information."
  (cl-letf (((symbol-function 'popon-update) #'ignore))
    (popon-create text pos window buffer priority)))

(defun acm-terminal-make-frame (_)
  "Advice override `acm-make-frame' to make an invisible popon."
  (let* ((width (if (> (window-width) acm-terminal-min-width)
                    (min (window-width) acm-terminal-max-width)
                  acm-terminal-min-width))
         (pos (acm-terminal-get-popup-position)))
    (acm-terminal-make-popon (cons "" width) pos)))

(cl-defmacro acm-terminal-create-frame-if-not-exist (frame _frame-buffer _frame-name &optional _internal-border)
  `(unless (popon-live-p ,frame)
     (setq ,frame (acm-terminal-make-frame nil))))

(defun acm-terminal-menu-render-items (items menu-index)
  (let* ((item-index 0)
         (annotation-not-exits (cl-every (lambda (item) (string-empty-p (plist-get item :annotation))) items)))
    (dolist (v items)
      (let* ((icon (cdr (assoc (downcase (plist-get v :icon)) acm-icon-alist)))
             (candidate (plist-get v :display-label))
             (candidate-length (funcall acm-string-width-function candidate))
             (annotation (plist-get v :annotation))
             (annotation-text (if annotation annotation ""))
             (annotation-length (funcall acm-string-width-function annotation-text))
             (max-length (cond ((< acm-menu-max-length-cache acm-terminal-min-width)
                                acm-terminal-min-width)
                               ((< acm-terminal-max-width acm-menu-max-length-cache)
                                acm-terminal-max-width)
                               (t acm-menu-max-length-cache)))
             (padding-length (- max-length (+ candidate-length annotation-length)))
             (icon-text (if icon (acm-icon-build (nth 0 icon) (nth 1 icon) (nth 2 icon)) ""))
             (quick-access-key (nth item-index acm-quick-access-keys))
             candidate-line)

        ;; Render deprecated candidate.
        (when (plist-get v :deprecated)
          (add-face-text-property 0 (length candidate) 'acm-deprecated-face 'append candidate))

        ;; Build candidate line.
        (setq candidate-line
              (concat
               ;; icon-text
               (when acm-enable-quick-access
                 (if quick-access-key (concat quick-access-key ". ") "   "))
               (if (zerop padding-length)
                   candidate
                 (if (> padding-length 0)
                     (concat candidate (make-string padding-length ?\s))
                   (truncate-string-to-width candidate max-length 0 ?\s)))
               (propertize (format "%s \n" (capitalize annotation-text))
                           'face
                           (if (equal item-index menu-index) 'acm-select-face 'font-lock-doc-face))))

        ;; Render current candidate.
        (if (equal item-index menu-index)
            (progn
              (add-face-text-property 0 (length candidate-line) 'acm-select-face 'append candidate-line)

              ;; Hide doc frame if some backend not support fetch candidate documentation.
              (when (and
                     (not (member (plist-get v :backend) '("lsp" "elisp" "yas")))
                     (acm-frame-visible-p acm-doc-frame))
                (acm-doc-hide)))
          (add-face-text-property 0 (length candidate-line) 'acm-default-face 'append candidate-line))

        ;; Insert candidate line.
        (insert candidate-line)

        ;; Delete the last extra return line.
        (when (equal item-index (1- (length items)))
          (delete-char -1))

        ;; Update item index.
        (setq item-index (1+ item-index))))))

(defun acm-terminal-doc-render (doc &optional width)
  "Render DOC string."
  (let ((width (or width (1- acm-terminal-doc-max-width)))
        lines)
    (dolist (nline (split-string doc "\n") lines)
      (dolist (mline (acm-terminal-nsplit-string
                      nline width acm-terminal-doc-continuation-string) lines)
        (setq mline (string-pad mline width))
        (add-face-text-property 0 (length mline) 'acm-default-face 'append mline)
        (push mline lines)))
    (reverse lines)))

(defun acm-terminal-menu-render (menu-old-cache)
  (let* ((items acm-menu-candidates)
         (menu-old-max-length (car menu-old-cache))
         (menu-old-number (cdr menu-old-cache))
         (menu-new-max-length (acm-menu-max-length))
         (menu-new-number (length items))
         (menu-index acm-menu-index))
    ;; Record newest cache.
    (setq acm-menu-max-length-cache menu-new-max-length)
    (setq acm-menu-number-cache menu-new-number)

    ;; Insert menu candidates.
    (when acm-frame
      (let ((lines (split-string
                    (with-temp-buffer
                      (acm-menu-render-items items menu-index)
                      (buffer-string))
                    "\n")))
        ;; Adjust menu frame position.
        (acm-terminal-menu-adjust-pos lines))

      (popon-redisplay)
      (plist-put (cdr acm-frame) :visible t))

    ;; Not adjust menu frame size if not necessary,
    ;; such as select candidate just change index,
    ;; or menu width not change when switch to next page.
    (when (or (not (equal menu-old-max-length menu-new-max-length))
              (not (equal menu-old-number menu-new-number)))
      ;; Adjust doc frame with menu frame position.
      (when (acm-terminal-popon-visible-p acm-doc-frame)
        (acm-terminal-doc-adjust-pos acm-terminal-candidate-doc)))

    ;; Fetch `documentation' and `additionalTextEdits' information.
    (cl-letf (((symbol-function 'acm-frame-visible-p) 'acm-terminal-popon-visible-p))
      (acm-fetch-candidate-doc))))

(defun acm-terminal-menu-adjust-pos (&optional lines)
  "Adjust menu frame position."
  (pcase-let* ((`(,edge-left ,edge-top ,edge-right ,edge-bottom) (window-inside-edges))
               (textarea-width (- (window-width)
                                  (+ (- edge-left (window-left-column))
                                     (acm-teminal-line-number-display-width))))
               (textarea-height (- edge-bottom edge-top))
               (`(,cursor-x . ,cursor-y)
                (prog1 (acm-terminal-get-popup-position)
                  (when lines
                    (plist-put (cdr acm-frame) :lines lines)
                    (plist-put (cdr acm-frame) :width (length (car lines))))))
               (`(,menu-w . ,menu-h) (popon-size acm-frame))
               (bottom-free-h (- edge-bottom edge-top cursor-y)))
    (let ((x (if (>= textarea-width (+ cursor-x menu-w))
                 cursor-x
               (- cursor-x (- (+ cursor-x menu-w) textarea-width) 1))))
      (plist-put (cdr acm-frame) :x x))
    (cond
     ;; top
     ((< bottom-free-h menu-h)
      (plist-put (cdr acm-frame) :direction 'top)
      (plist-put (cdr acm-frame) :y (- cursor-y menu-h)))
     ;; bottom
     (t
      (plist-put (cdr acm-frame) :direction 'bottom)
      (plist-put (cdr acm-frame) :y (+ cursor-y 1))))))

(defun acm-terminal-doc-top-edge-y (cursor-y menu-h doc-h &optional doc-lines)
  "Return the y-coordinate of doc at left/right top edge, set :lines if possible.

CURSOR-Y        y-coordinate of cursor
MENU-H          height of menu frame
DOC-H           height of doc frame
DOC-LINES       text lines of doc"
  (if (> doc-h cursor-y)
      ;; +---------y-------+--+
      ;; |         |       |  |
      ;; |         |       |  |
      ;; |  +------+       |  |
      ;; |  |      |       |  |
      ;; |  +-menu-+~~doc~~+  |
      ;; |  a|     :.......:  |
      ;; +--------------------+
      (prog1 0
        (when doc-lines
          (plist-put (cdr acm-doc-frame) :lines (seq-take doc-lines cursor-y))))
    (if (> doc-h menu-h)
        ;; +--------------------+
        ;; |         y-------+  |
        ;; |         |       |  |
        ;; |  +------+       |  |
        ;; |  |      |       |  |
        ;; |  +-menu-+--doc--+  |
        ;; |  a|                |
        ;; +--------------------+
        (- cursor-y doc-h)
      ;; +--------------------+
      ;; |  +------y-------+  |
      ;; |  |      |       |  |
      ;; |  |      +--doc--+  |
      ;; |  |      |          |
      ;; |  +-menu-+          |
      ;; |  a|                |
      ;; +--------------------+
      (- cursor-y menu-h))))

(defun acm-terminal-doc-adjust-pos (&optional candidate-doc)
  "Adjust doc frame position."
  (pcase-let* ((`(,edge-left ,edge-top ,edge-right ,edge-bottom) (window-inside-edges))
               (textarea-width (- (window-width)
                                  (+ (- edge-left (window-left-column))
                                     (acm-teminal-line-number-display-width))))
               (textarea-height (- edge-bottom edge-top))
               (`(,cursor-x . ,cursor-y) (acm-terminal-get-popup-position))
               (`(,menu-x . ,menu-y) (popon-position acm-frame))
               (`(,menu-w . ,menu-h) (popon-size acm-frame))
               (menu-right (+ menu-x menu-w))
               (doc-w nil)
               (doc-h nil)
               (doc-lines nil))
    (cond
     ;; l:menu + r:document
     ((>= textarea-width (+ menu-right acm-terminal-doc-max-width))
      (setq doc-lines (acm-terminal-doc-render candidate-doc))
      (setq doc-h (length doc-lines))
      (plist-put (cdr acm-doc-frame) :lines doc-lines)
      (plist-put (cdr acm-doc-frame) :x menu-right)
      (plist-put (cdr acm-doc-frame)
                 :y (if (eq 'bottom (plist-get (cdr acm-frame) :direction))
                        ;; right bottom
                        (1+ cursor-y)
                      ;; right top
                      (acm-terminal-doc-top-edge-y cursor-y menu-h doc-h doc-lines))))
     (t
      (let* ((fix-width (min acm-terminal-doc-max-width (- textarea-width 1)))
             (rects
              (list
               (list 'right-bottom (- textarea-width menu-x menu-w) (- textarea-height cursor-y))
               (list 'right-top (- textarea-width menu-x menu-w) cursor-y)
               (list 'bottom fix-width (- edge-bottom edge-top menu-y menu-h))
               (list 'left-bottom menu-x (- textarea-height cursor-y))
               (list 'left-top menu-x cursor-y)
               (list 'top    fix-width menu-y))))
        ;; Find the largest free space in left/top/bottom/right
        (pcase-let* ((`(,rect ,rect-width ,_rect-height)
                      (car (seq-sort (lambda (r1 r2)
                                       (> (apply #'* (cdr r1)) (apply #'* (cdr r2))))
                                     (if acm-terminal-doc-min-width
                                         (seq-filter
                                          (lambda (r)
                                            (>= (cadr r) acm-terminal-doc-min-width))
                                          rects)
                                       rects))))
                     (rerender-width (- (min fix-width rect-width) 1))
                     (lines (acm-terminal-doc-render candidate-doc rerender-width)))
          (plist-put (cdr acm-doc-frame) :lines lines)
          (setq doc-h (length lines)) ;; Update doc height
          (setq doc-w (1+ rerender-width))
          (pcase rect
            ('left-bottom
             (plist-put (cdr acm-doc-frame) :x (- menu-x doc-w))
             (plist-put (cdr acm-doc-frame) :y (1+ cursor-y)))
            ('left-top
             (plist-put (cdr acm-doc-frame) :x (- menu-x doc-w))
             (plist-put (cdr acm-doc-frame) :y (acm-terminal-doc-top-edge-y
                                                cursor-y menu-h doc-h doc-lines)))
            ('top
             (plist-put (cdr acm-doc-frame) :x (if (>= (- textarea-width menu-x) doc-w)
                                                   menu-x
                                                 (- textarea-width doc-w)))
             (plist-put (cdr acm-doc-frame) :y (if (< menu-y cursor-y)
                                                   (- menu-y doc-h)
                                                 (- menu-y doc-h
                                                    (if (eq 'bottom (plist-get (cdr acm-frame) :direction))
                                                        1
                                                      0)))))
            ('bottom
             (plist-put (cdr acm-doc-frame) :x (if (>= (- textarea-width menu-x) doc-w)
                                                   menu-x
                                                 (- textarea-width doc-w)))
             (plist-put (cdr acm-doc-frame) :y (+ menu-y menu-h)))
            ('right-bottom
             (plist-put (cdr acm-doc-frame) :x (+ menu-x menu-w))
             (plist-put (cdr acm-doc-frame) :y (1+ cursor-y)))
            ('right-top
             (plist-put (cdr acm-doc-frame) :x (+ menu-x menu-w))
             (plist-put (cdr acm-doc-frame) :y (acm-terminal-doc-top-edge-y
                                                cursor-y menu-h doc-h doc-lines))))))))
    (popon-redisplay)))

(defun acm-terminal-doc-hide ()
  (when (popon-live-p acm-doc-frame)
    (setq acm-doc-frame (popon-kill acm-doc-frame))))

(defun acm-terminal-doc-show ()
  (when acm-enable-doc
    (let* ((candidate (acm-menu-current-candidate))
           (backend (plist-get candidate :backend))
           (candidate-doc
            (pcase backend
              ("lsp" (acm-backend-lsp-candidate-doc candidate))
              ("elisp" (acm-backend-elisp-candidate-doc candidate))
              ("yas" (acm-backend-yas-candidate-doc candidate))
              ("tempel" (acm-backend-tempel-candidate-doc candidate))
              (_ ""))))
      (setq acm-terminal-candidate-doc candidate-doc)
      (if (and candidate-doc
               (not (string-equal candidate-doc "")))
          (progn
            ;; Create doc frame if it not exist.
            (acm-terminal-create-frame-if-not-exist acm-doc-frame acm-doc-buffer "acm doc frame")

            ;; Adjust doc frame position and size.
            (acm-terminal-doc-adjust-pos candidate-doc))

        ;; Hide doc frame
        (acm-terminal-doc-hide)))))

(defun acm-terminal-hide ()
  (interactive)
  ;; Turn off `acm-mode'.
  (acm-mode -1)

  ;; Hide menu frame.
  (when acm-frame
    (setq acm-frame (popon-kill acm-frame)))

  ;; Hide doc frame.
  (acm-terminal-doc-hide)

  ;; Clean `acm-menu-max-length-cache'.
  (setq acm-menu-max-length-cache 0)

  ;; Remove hook of `acm--pre-command'.
  (remove-hook 'pre-command-hook #'acm--pre-command 'local))

(defun acm-terminal-update ()
  ;; Adjust `gc-cons-threshold' to maximize temporary,
  ;; make sure Emacs not do GC when filter/sort candidates.
  (let* ((gc-cons-threshold most-positive-fixnum)
         (keyword (acm-get-input-prefix))
         (candidates (acm-update-candidates))
         (bounds (bounds-of-thing-at-point 'symbol))
         (direction (when (popon-live-p acm-frame)
                      (plist-get (cdr acm-frame) :direction))))
    (setq acm-terminal-current-input (acm-backend-search-words-get-point-string))
    (cond
     ;; Hide completion menu if user type first candidate completely.
     ((and (equal (length candidates) 1)
           (string-equal keyword (plist-get (nth 0 candidates) :label))
           ;; Volar always send back single emmet candidate, we need filter this condition.
           (not (string-equal "Emmet Abbreviation" (plist-get (nth 0 candidates) :annotation))))
      (acm-hide))
     ((> (length candidates) 0)
      (let* ((menu-old-cache (cons acm-menu-max-length-cache acm-menu-number-cache)))
        ;; Enable acm-mode to inject mode keys.
        (acm-mode 1)

        ;; Use `pre-command-hook' to hide completion menu when command match `acm-continue-commands'.
        (add-hook 'pre-command-hook #'acm--pre-command nil 'local)

        ;; Init candidates, menu index and offset.
        (setq-local acm-candidates candidates)
        (setq-local acm-menu-candidates
                    (cl-subseq acm-candidates
                               0 (min (length acm-candidates)
                                      acm-menu-length)))
        (setq-local acm-menu-index (if (zerop (length acm-menu-candidates)) -1 0))
        (setq-local acm-menu-offset 0)

        ;; Init colors.
        (acm-init-colors)

        ;; Record menu popup position and buffer.
        (setq acm-frame-popup-point (or (car bounds) (point)))

        ;; `posn-at-point' will failed in CI, add checker make sure CI can pass.
        ;; CI don't need popup completion menu.
        (when (posn-at-point acm-frame-popup-point)
          (setq acm-frame-popup-position (acm-frame-get-popup-position))

          ;; Create menu frame if it not exists.
          (acm-terminal-create-frame-if-not-exist acm-frame acm-buffer "acm frame")
          (plist-put (cdr acm-frame) :direction direction)

          ;; Render menu.
          (acm-menu-render menu-old-cache))
        ))
     (t
      (acm-hide)))))

(advice-add 'acm-init-colors :override 'acm-terminal-init-colors)
(advice-add 'acm-hide :override #'acm-terminal-hide)
(advice-add 'acm-update :override #'acm-terminal-update)
(advice-add 'acm-doc-show :override #'acm-terminal-doc-show)
(advice-add 'acm-doc-hide :override #'acm-terminal-doc-hide)
(advice-add 'acm-menu-render :override #'acm-terminal-menu-render)
(advice-add 'acm-menu-render-items :override #'acm-terminal-menu-render-items)

(provide 'acm-terminal)

;;; acm-terminal.el ends here
