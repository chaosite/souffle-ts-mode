;;; souffle-ts-mode.el --- Major mode for editing Soufflé Datalog code

;; Copyright (C) 2023  Matan Peled

;; Author: Matan Peled <chaosite(at)gmail(dot)com>
;; Keywords: datalog, languages
;; Version: 0.1

;; This file is NOT part of Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; A tree-sitter based major mode for Soufflé Datalog
;; (https://souffle-lang.github.io/).
;;
;; Features: Syntax highlighting (font-lock), indentation, navigation.
;;
;; Put this file in your load-path and add the following to your init file:
;;
;; (require 'souffle-ts-mode)
;;
;; Or using use-package:
;;
;; (use-package souffle-ts-mode
;;    :ensure t
;;    :mode (("\\.dl$" . souffle-ts-mode)))
;;
;; As with all tree-sitter modes, you also need a grammar. See:
;;  - https://github.com/chaosite/tree-sitter-souffle
;;  - https://github.com/casouri/tree-sitter-module

;;; Code:

;; Prerequisites

(require 'treesit)
(eval-when-compile (require 'rx))
(require 'c-ts-common)

;; Local variables

(defcustom souffle-ts-mode-indent-offset 4
  "Number of spaces for each indentation step in `souffle-ts-mode'."
  :type 'integer
  :safe 'integerp
  :group 'souffle)

;; Language definitions

(defconst souffle-ts-mode--keywords
  '((INPUT_DECL) (OUTPUT_DECL) (DECL) (TYPE) (FUNCTOR))
  "Souffle keywords for tree-sitter font-locking.")

(defconst souffle-ts-mode--operators
  '((IF) (STAR) (EQUALS) (GE) (NE) (LE) (MINUS) (EXCLAMATION)
    (UNDERSCORE) (PIPE))
  "Souffle operators for tree-sitter font-locking.")

(defconst souffle-ts-mode--font-lock-settings
  (treesit-font-lock-rules
   :feature 'comment
   :language 'souffle
   '((COMMENT) @font-lock-comment-face)

   :feature 'string
   :language 'souffle
   '((STRING) @font-lock-string-face)

   :feature 'number
   :language 'souffle
   '((NUMBER) @font-lock-number-face)

   :feature 'builtin
   :language 'souffle
   '((NIL) @font-lock-builtin-face)

   :feature 'keyword
   :language 'souffle
   `([,@souffle-ts-mode--keywords] @font-lock-keyword-face)

   :feature 'type-name
   :language 'souffle
   '((type (TYPE) :anchor (IDENT) @font-lock-type-face)
     (non_empty_attributes (IDENT) :anchor (COLON) :anchor
                           (identifier (IDENT) @font-lock-type-face))
     (non_empty_record_type_list (IDENT) :anchor (COLON) :anchor
                                 (identifier (IDENT) @font-lock-type-face))
     (union_type_list (identifier (IDENT) @font-lock-type-face))
     ((SUBTYPE) :anchor (IDENT) @font-lock-type-face)
     )

   :feature 'decl-name
   :language 'souffle
   '((relation_decl (relation_list (IDENT) @font-lock-function-name-face))
     (atom (identifier (IDENT) @font-lock-function-name-face))
     (io_directive_list (io_relation_list
                         (identifier (IDENT) @font-lock-function-name-face))))

   :feature 'operator
   :language 'souffle
   `([,@souffle-ts-mode--operators] @font-lock-operator-face))

  "Tree-sitter font-lock settings for `souffle-ts-mode'.")

(defconst souffle-ts-mode--indent-rules
  (let ((offset souffle-ts-mode-indent-offset))
    `((souffle
       ((node-is "RPAREN") first-sibling 0)
       ((node-is "RBRACKET") first-sibling 0)
       ; matches relation parameters
       ((parent-is "non_empty_arg_list") parent 0)
       ((parent-is "non_empty_record_type_list") parent 0)
       ; matches the types
       ((and (parent-is "non_empty_attributes") (node-is "identifier"))
        prev-sibling 2)
       ; matches relation parameters with types (in .decl's)
       ((and (parent-is "non_empty_attributes") (not (node-is "identifier")))
        parent 0)
       ; matches rule bodies
       ((parent-is "rule_def") standalone-parent ,offset)
       ((parent-is "conjunction") first-sibling 0)
       ((parent-is "disjunction") first-sibling 0)
       )))
  "Tree-sitter indent rules for Souffle Datalog.")

;; Syntax table
;; taken from: https://github.com/gbalats/souffle-mode

(defconst souffle-ts-mode--syntax-table
  (let ((st (make-syntax-table)))
    ;; C++ style comment `//' ..."
    (modify-syntax-entry ?/ ". 124b" st)
    (modify-syntax-entry ?* ". 23" st)
    (modify-syntax-entry ?\n "> b" st)
    (modify-syntax-entry ?. "." st)
    (modify-syntax-entry ?: "." st)
    (modify-syntax-entry ?? "_" st)
    st)
  "Syntax table for `souffle-ts-mode'.")

;; Define the mode

;;;###autoload
(define-derived-mode souffle-ts-mode prog-mode "Soufflé"
  "Major mode for editting Soufflé Datalog, powered by tree-sitter."
  :group 'souffle
  :syntax-table souffle-ts-mode--syntax-table

  (when (treesit-ready-p 'souffle)
    (treesit-parser-create 'souffle)

    ;; Comments.
    (c-ts-common-comment-setup)  ; Soufflé uses C-style comments

    ;; Electric.
    (setq-local electric-indent-chars
                (append "{}(),;." electric-indent-chars))

    ;; Font-lock.
    (setq-local treesit-font-lock-settings souffle-ts-mode--font-lock-settings)
    (setq-local treesit-font-lock-feature-list
                '((comment decl-name type-name)
                  (keyword string builtin)
                  (number operator)
                  ()))

    ;; Indentation.
    (setq-local treesit-simple-indent-rules souffle-ts-mode--indent-rules)

    ;; Navigation.
    (setq-local treesit-defun-type-regexp (rx (or "decl" "type")))
    (setq-local treesit-sentence-type-regexp (rx "unit"))
    (setq-local treesit-sexp-type-regexp (rx (or "atom"
                                                 "term"
                                                 "relation_decl"
                                                 "type"
                                                 "io_head")))

    (treesit-major-mode-setup)))

(if (treesit-ready-p 'souffle)
    (add-to-list 'auto-mode-alist '("\\.dl$" . souffle-ts-mode)))

(provide 'souffle-ts-mode)
