(in-package :cl-user)
(defpackage :lem.go-mode
  (:use :cl :lem)
  (:export))
(in-package :lem.go-mode)

(defvar *go-tab-width* 8)

(defvar *go-builtin*
  '("append" "cap"   "close"   "complex" "copy"
    "delete" "imag"  "len"     "make"    "new"
    "panic"  "print" "println" "real"    "recover"))

(defvar *go-keywords*
  '("break"    "default"     "func"   "interface" "select"
    "case"     "defer"       "go"     "map"       "struct"
    "chan"     "else"        "goto"   "package"   "switch"
    "const"    "fallthrough" "if"     "range"     "type"
    "continue" "for"         "import" "return"    "var"))

(defvar *go-constants*
  '("nil" "true" "false" "iota"))

(defvar *go-syntax-table*
  (let ((table (make-syntax-table
                :space-chars '(#\space #\tab #\newline)
                :symbol-chars '(#\_)
                :paren-alist '((#\( . #\))
                               (#\{ . #\})
                               (#\[ . #\]))
                :string-quote-chars '(#\" #\' #\`)
                :line-comment-preceding-char #\/
                :line-comment-following-char #\/
                :block-comment-preceding-char #\/
                :block-comment-following-char #\*)))

    (dolist (k *go-keywords*)
      (syntax-add-match table
                        (make-syntax-test k :word-p t)
                        :attribute *syntax-keyword-attribute*))

    (dolist (k *go-builtin*)
      (syntax-add-match table
                        (make-syntax-test k :word-p t)
                        :attribute *syntax-keyword-attribute*))

    (dolist (k *go-constants*)
      (syntax-add-match table
                        (make-syntax-test k :word-p t)
                        :attribute *syntax-constant-attribute*))
    table))

(define-major-mode go-mode nil
    (:name "go"
	   :keymap *go-mode-keymap*
	   :syntax-table *go-syntax-table*)
  (setf (get-bvar :enable-syntax-highlight) t)
  (setf (get-bvar :calc-indent-function) 'go-calc-indent))

(defun following-word ()
  (points-to-string (current-point)
		    (form-offset (copy-point (current-point) :temporary) 1)))

(defun semicolon-p ()
  (let ((c (preceding-char)))
    (case c
      ((#\;) t)
      ((#\' #\" #\`) t)
      ((#\+ #\-)
       (prev-char 1)
       (eql c (preceding-char)))
      ((#\) #\] #\}) t)
      (t
       (and (/= 0 (skip-chars-backward (current-point) #'syntax-word-char-p))
            #-(and)(not (member (following-word)
                                '("break" "continue" "fallthrough" "return")
                                :test #'string=)))))))

(defun go-calc-indent (point)
  (save-excursion
    (setf (current-buffer) (point-buffer point))
    (move-point (current-point) point)
    (back-to-indentation)
    (let ((attribute (text-property-at (current-point) :attribute -1)))
      (cond ((eq attribute *syntax-comment-attribute*)
	     (previous-single-property-change (current-point) :attribute)
	     (1+ (current-column)))
	    ((eq attribute *syntax-string-attribute*)
	     nil)
	    (t
	     (let ((inside-indenting-paren nil)
		   (indent))
	       (setf indent
		     (save-excursion
		       (when (up-list 1 t)
			 (case (following-char)
			   (#\{
			    (back-to-indentation)
			    (+ *go-tab-width* (current-column)))
			   (#\(
			    (let ((n 0))
			      (when (save-excursion
				      (backward-sexp 1 t)
				      (member (following-word)
					      '("import" "const" "var" "type" "package")
					      :test #'string=))
				(setf inside-indenting-paren t)
				(incf n *go-tab-width*))
			      (back-to-indentation)
			      (+ (current-column) n)))))))
	       (when (null indent)
		 (return-from go-calc-indent 0))
	       (cond ((looking-at-line "case\\W|default\\W" :start (point-charpos (current-point)))
		      (decf indent *go-tab-width*))
		     ((looking-at-line "\\s*}")
		      (save-excursion
			(end-of-line)
			(skip-chars-backward (current-point) '(#\)))
			(backward-sexp 1 t)
			(back-to-indentation)
			(setf indent (current-column)))))
	       (save-excursion
		 (beginning-of-line)
		 (skip-space-and-comment-backward (current-point))
		 (when (case (preceding-char)
			 ((nil #\{ #\:)
			  nil)
			 (#\(
			  (not inside-indenting-paren))
			 (#\,
			  (and (up-list 1 t)
			       (not (eql #\{ (following-char)))))
			 (t
			  (not (semicolon-p))))
		   (incf indent *go-tab-width*)))
	       (when (and (looking-at-line "^\\s*\\)\\s*$") inside-indenting-paren)
		 (decf indent *go-tab-width*))
	       indent))))))

(define-key *go-mode-keymap* "}" 'go-electric-close)
(define-command go-electric-close (n) ("p")
  (self-insert n)
  (indent))

(define-command gofmt () ()
  (filter-buffer "gofmt"))

(pushnew (cons "\\.go$" 'go-mode) *auto-mode-alist* :test #'equal)