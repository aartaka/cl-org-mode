(in-package :cl-org-mode)

(defmethod read-next-node (node (next-node null) stream) 
  "This method is called when we don't yet know what the next node is"
  (let (stack)
    (loop for char = (read-char stream nil)
       :if (null char) 
       :do (return (finalize-node node NIL stack))
       :else 
       :do (push char stack)
	 (multiple-value-bind (new-node old-stack)
		 (find-next-node node next-node stack)	   
	       (when new-node 
		 (return (finalize-node node new-node old-stack)))))))

(defmethod read-next-node (node (next-node node) stream)
  "When we know what the node is already, just return it"
  next-node)

(defmethod read-next-node :around (node next-node stream)
  (let ((*dispatchers* (node-dispatchers node)))
  ;(warn "DISPATHERS FOR ~A ~A: ~A" node next-node *dispatchers*)
    (call-next-method)))


(defmethod find-next-node (node next-node stack)
  (loop for object in *dispatchers*
       :do (multiple-value-bind (result old-stack)
	       (node-start object stack)
	     (when result (return (values result old-stack))))))

(declaim (optimize debug safety))

;;
;; Extensions
(defmacro c? (form)
  `(check? ,form))

(defmacro mdo* (&body spec)
  (with-gensyms (ret)
    `(named-seq*
      ,@(butlast spec)
      (<- ,ret ,(lastcar spec))
      ,ret)))

(defun before* (p q)
  "Non-backtracking parser: Find a p before q, doesn't consume q."
  (parser-combinators::with-parsers (p q)
    (define-oneshot-result inp is-unread
      (let ((p-result (funcall (funcall p inp))))
        (when p-result
          (let* ((p-suffix (suffix-of p-result))
                 (q-result (funcall (funcall q p-suffix))))
            (when (and p-result q-result)
              (make-instance 'parser-possibility :tree (tree-of p-result) :suffix p-suffix))))))))

(defun chookahead? (result p)
  "Parser: return result if p matches, but do no advance"
  (parser-combinators::with-parsers (p)
    (define-oneshot-result inp is-unread
      (let ((p-result (funcall (funcall p inp))))
        (when p-result
          (make-instance 'parser-possibility :tree result :suffix inp))))))

(defun failing? (p)
  (named-seq*
   p
   (zero)))

;;;
;;; Tools
(defun unzip (fn sequence &key (key #'identity))
  (iter (for elt in sequence)
        (if (funcall fn (funcall key elt))
            (collect elt into yes)
            (collect elt into no))
        (finally (return (values yes no)))))

(defun tree-getf (tree &rest keys)
  (if keys
      (apply #'tree-getf (getf tree (first keys)) (rest keys))
      tree))

(defun to-string (xs)
  (coerce xs 'string))

(defun to-symbol (package xs)
  (intern (string-upcase (to-string xs)) package))

(defun intersperse (elt xs)
  (nbutlast
   (loop :for x :in xs
      :collect x
      :collect elt)))

(define-constant +newline-string+ (coerce #(#\Newline) 'string) :test #'equal)

(defun strconcat (xs)
  (apply #'concatenate 'string xs))

(defun strconcat* (&rest xs)
  (strconcat xs))

;;;
;;; Primitives
(defun char-bag (bag)
  (sat (lambda (x) (find x bag :test #'char=))))

(defun char-not-bag (bag)
  (sat (lambda (x) (not (find x bag :test #'char=)))))

(defun line-constituent-but (except)
  (char-not-bag (list* #\Linefeed #\Newline #\Return except)))

(defun line-constituent-but* (&rest except)
  (line-constituent-but except))

(defun string-of (p)
  (between* p 0 nil 'string))

(defun string-of-1+ (p)
  (between* p 1 nil 'string))

(defun line-but-of (&rest except)
  (string-of (line-constituent-but except)))

(defun line-but-of-1+ (&rest except)
  (string-of-1+ (line-constituent-but except)))

(defun caseless (x)
  (choices1 (string-downcase x) (string-upcase x)))

(defun spacetab ()
  (char-bag '(#\Space #\Tab)))

(defun newline ()
  (chook? +newline-string+
          (choices1 #\Newline
                    (seq-list* #\Return #\Newline)
                    #\Return)))

(defun eol ()
  (choice1 (newline)
           (end?)))

(defun line-without-eol ()
  (named-seq*
   (<- string (line-but-of))
   (eol)
   string))

(defun line-full ()
  (hook? (lambda (x) (concatenate 'string x +newline-string+))
         (line-without-eol)))

(defun spacetabs ()
  (between* (spacetab) nil nil 'string))

(defun spacetabs1 ()
  (between* (spacetab) 1 nil 'string))

(defun pre-white1? (x)
  (mdo*
    (spacetabs1)
    x))

(defun pre-white? (x)
  (mdo*
    (spacetabs)
    x))

(defun org-name ()
  (string-of-1+ (choices1 (alphanum?) #\_ #\-)))

(defun tag (tag x)
  (hook? (lambda (x)
           (list tag x))
         x))
;;;;
;;;; The grammar encoded therein roughly approximates http://orgmode.org/worg/dev/org-syntax.html
;;;;
;;;
;;;  Element   http://orgmode.org/worg/dev/org-syntax.html#Elements
(defun org-greater-signature ()
  (pre-white? (choice1 "#+" (bracket? ":" (org-name) ":"))))

(defun org-greater-end-signature ()
  (pre-white? (choice1 (seq-list* (caseless "#+END")
                                  (choice1 "_"
                                           (before* (opt* ":")
                                                    (eol))))
                       (caseless ":END:"))))

(defun org-boundary (&key for)
  (choices1 "*"
            (ecase for
              (:element
               (org-greater-signature))
              (:section
               (org-greater-end-signature)))
            (end?)))

(defun org-element-line ()
  (choice1
   (except? (named-seq*
             (<- first-char (line-constituent-but* #\*))
             (<- line       (line-full))
             (concatenate 'string (list first-char) line))
            (org-greater-signature))
   (eol)))

(defun org-element ()
  "Actually org-paragraph."
  (mdo
    (<- lines (find-before* (c? (org-element-line))
                            (c? (org-boundary :for :element))))
   (if lines
       (result (strconcat lines))
       (zero))))

;;;
;;;  Affiliated keyword   http://orgmode.org/worg/dev/org-syntax.html#Affiliated_keywords
(defun org-affiliated-keyword ()
  "Deviation: allows optionals for keys other than CAPTION and RESULTS."
  (named-seq* "#+"
              (<- name      (except? (org-name) (seq-list* (caseless "END")
                                                           (choices1 " " "_" ":"))))
              (<- optional (opt* (bracket? "[" (line-but-of-1+ #\[ #\]) "]")))
              (opt* ":") (opt* " ")
              (<- value    (line-without-eol))
              (let ((attributep (starts-with-subseq "ATTR_" name)))
                (append (if attributep
                            (list :attribute (subseq name 5))
                            (list :keyword name))
                        (when optional
                          (list :optional optional))
                        (list :value value)))))

;;;
;;;  Section   http://orgmode.org/worg/dev/org-syntax.html#Headlines_and_Sections
(defun org-section (allowed-greater-element)
  (named-seq*
   (<- content (find-before*
                (choices1
                 (c? (org-element))
                 (c? allowed-greater-element)
                 (c? (org-affiliated-keyword)))
                (c? (org-boundary :for :section))))
   (when-let ((filtered-content (remove "" content :test #'equal)))
     (list :section filtered-content))))

;;;
;;;  Greater element   http://orgmode.org/worg/dev/org-syntax.html#Greater_Elements
;;
;; part of the section->greater-element->section loop
(defun org-greater-nondrawer-element ()
  (choice1
   (org-greater-block)
   (org-dynamic-block)))

(defun org-greater-element ()
  (choice1
   (org-greater-nondrawer-element)
   (org-drawer)))

;;;
;;;  Greater blocks   http://orgmode.org/worg/dev/org-syntax.html#Greater_Blocks
(defun org-greater-block ()
  "Deviation: does not parse own contents."
  (mdo
    (pre-white? (caseless "#+BEGIN_"))
    (<- name (org-name))
    (<- parameters (opt* (pre-white1? (line-without-eol))))
    (<- contents (c? (delayed? (org-section (org-greater-element)))))
    (pre-white? (caseless "#+END_")) (caseless name) (opt* (seq-list* (spacetabs1) (line-but-of))) (eol)
    (result (list :block name
                  :parameters parameters
                  :contents contents))))

;;;
;;;  Drawer   http://orgmode.org/worg/dev/org-syntax.html#Drawers_and_Property_Drawers
(defun org-property ()
  (named-seq*
   (spacetabs)
   (<- name (bracket? ":" (except? (org-name) "END") ":"))
   (<- value (opt* (pre-white1? (line-but-of))))
   (spacetabs) (eol)
   (list :property name :value value)))

(defun org-drawer ()
  "Deviation: does not parse own contents."
  (mdo
    (<- name    (pre-white? (bracket? ":" (except? (org-name) (caseless "END")) ":")))
    (opt* (line-but-of)) (eol)
    (<- contents (cond ((string-equal name "PROPERTIES")
                        (many* (org-property)))
                       (t
                        (delayed? (org-section (org-greater-nondrawer-element))))))
    (choices1
     (seq-list* (pre-white? (caseless ":END:")) (spacetabs) (eol))
     (chookahead? t (choices1 "*"
                              (seq-list* (spacetabs) "#+")
                              (end?))))
    (result (list :drawer name
                  :contents contents))))

;;;
;;;  Dynamic block   http://orgmode.org/worg/dev/org-syntax.html#Dynamic_Blocks
(defun org-dynamic-block ()
  (mdo
    (pre-white? (caseless "#+BEGIN:"))
    (<- name (pre-white1? (line-but-of #\Space)))
    (<- parameters (opt* (pre-white? (line-without-eol))))
    (<- contents (delayed? (org-section (org-greater-element))))
    (pre-white? (seq-list* (caseless "#+END")
                           (before* (opt* ":")
                                    (seq-list* (opt* (seq-list* (spacetabs1)
                                                                (line-but-of)))
                                               (eol)))))
    (result (list :dynamic-block name
                  :parameters parameters
                  :contents contents))))

;;;
;;;  Headline   http://orgmode.org/worg/dev/org-syntax.html#Headlines_and_Sections
(defun org-priority (priorities)
  (named-seq* "[#"
              (<- priority (apply #'choices1 priorities))
              "]"
              (string priority)))

(defun org-tag-name ()
  (string-of-1+ (choices1 (alphanum?) #\_ #\@ #\# #\%)))

(defun org-tags ()
  (named-seq* ":"
              (<- tags (sepby* (org-tag-name) #\:))
              ":"
              tags))

(defun org-title ()
  (hook? #'to-string
         (find-before* (line-constituent-but nil)
                       (seq-list* (opt* (pre-white1? (org-tags)))
                                  (eol)))))

(defun org-stars (n)
  (seq-list* (times? #\* n)
             (chookahead? t " ")))
(defparameter *org-default-startup*
  '(:odd              nil
    :comment-keyword  "COMMENT"
    :quote-keyword    "QUOTE"
    :footnote-title   "Footnotes"
    :keywords        ("TODO" "DONE")
    :priorities      ("A" "B" "C"))
  "So called 'startup' options, in absence of any headers.")

(defun org-headline (nstars &optional (startup *org-default-startup*))
  (destructuring-bind (&key comment-keyword quote-keyword keywords priorities
                       &allow-other-keys) startup
    (named-seq*
      (c? (org-stars nstars))
      (<- commentedp (c? (opt* (pre-white1? (tag :commented (chook? t (before* comment-keyword
                                                                               (spacetabs1))))))))
      (<- quotedp (c? (opt* (pre-white1? (tag :quoted (chook? t (before* quote-keyword
                                                                         (spacetabs1))))))))
      (<- keyword (c? (opt* (pre-white1? (tag :todo (before* (apply #'choices1 keywords)
                                                             (spacetabs1)))))))
      (<- priority (c? (opt* (pre-white1? (tag :priority (before* (org-priority priorities)
                                                                  (spacetabs1)))))))
      (<- title (c? (tag :title (choice1 (pre-white1? (org-title)) ""))))
      (<- tags (c? (opt* (pre-white1? (tag :tags (org-tags))))))
      (c? (spacetabs)) (c? (eol))
      (append commentedp quotedp keyword priority title tags))))

;;;
;;;  Entry   http://orgmode.org/worg/dev/org-syntax.html#Headlines_and_Sections
(defun org-closing-headline-variants (current startup)
  (let ((variants (loop :for x :downfrom current :to 1 :by (if (getf startup :odd) 2 1)
                     :collect x)))
    (apply #'choices1 (mapcar (lambda (n)
                                (seq-list* (org-stars n)
                                           " "))
                              variants))))

(defun org-entry (stars &optional (startup *org-default-startup*))
  (named-seq*
   (<- headline (c? (org-headline stars)))
   (<- body     (c? (named-seq*
                     (<- section  (delayed? (org-section (org-greater-element))))
                     (<- children (delayed? (many* (org-child-entry stars startup))))
                     (append (when section
                               (list section))
                             children))))
   (append (list :entry headline)
           body)))

(defun org-top-entry (startup)
  (org-entry 1 (merge-startup startup *org-default-startup*)))

(defun org-child-entry (stars startup &aux (odd (getf startup :odd)))
  (org-entry (+ stars (if odd 2 1)) startup))

(defparameter *testcases*
  '(;; 0
    ("* a" (:ENTRY (:TITLE "a")))
    ;; 1
    ("* a
"          (:ENTRY (:TITLE "a")))
    ;; 2
    ("* a
   a text" (:ENTRY (:TITLE "a")
            (:SECTION ("   a text
"))))
    ;; 3
    ("* a
** b
"          (:ENTRY (:TITLE "a")
            (:ENTRY (:TITLE "b"))))
    ;; 4
    ("* a
   a text
** b
"          (:ENTRY (:TITLE "a")
            (:SECTION ("   a text
"))
            (:ENTRY (:TITLE "b"))))
    ;; 5
    ("* a

  a text

** b
   b text

"          (:ENTRY (:TITLE "a")
            (:SECTION ("
  a text

"))
            (:ENTRY (:TITLE "b")
                    (:SECTION
                     ("   b text

")))))
    ("* a

** b
"          (:ENTRY (:TITLE "a")
            (:SECTION ("
"))
            (:ENTRY (:TITLE "b"))))))

(defun test-org-entry (&optional (trace t) (debug t)
                       &aux (*debug-mode* debug))
  (values-list
   (mapcan (lambda (tc n)
             (when trace
               (format t "---------------- #~D~%" n))
             (destructuring-bind (input expected) tc
               (with-position-cache (cache input)
                 (let ((output (parse-string* (org-entry 1) input)))
                   (unless (equal output expected)
                     (when trace
                       (format t "-~%~S~%~S~%~S~%" n input output))
                     (list '_ n input output))))))
           *testcases*
           (iota (length *testcases*)))))

;;;
;;;  Header   http://orgmode.org/manual/In_002dbuffer-settings.html#In_002dbuffer-settings
(defparameter *org-startup*
  '((:overview :content :showall :showeverything)
    (:indent :noindent)
    (:align :noalign)
    (:inlineimages :noinlineimages)
    (:latexpreview :nolatexpreview)
    (:logdone :lognotedone :nologdone)
    (:logrepeat :lognoterepeat :nologrepeat)
    (:logreschedule :lognotereschedule :nologreschedule)
    (:logredeadline :lognoteredeadline :nologredeadline)
    (:logrefile :lognoterefile :nologrefile)
    (:lognoteclock-out :nolognoteclock-out)
    (:logdrawer :nologdrawer)
    (:logstatesreversed :nologstatesreversed)
    (:hidestars :showstars)
    (:indent :noindent)
    (:odd :oddeven)
    (:customtime)
    (:constcgs :constsi)
    (:fninline :fnnoinline :fnlocal)
    (:fnprompt :fnauto :fnconfirm :fnplain)
    (:fnadjust :nofnadjust)
    (:hideblocks :nohideblocks)
    (:entitiespretty :entitiesplain)
    ))

(defun merge-startup (stronger weaker)
  (append stronger weaker))

(let ((set (make-hash-table :test 'eq)))
  (dolist (xs *org-startup*)
    (dolist (x xs)
      (setf (gethash x set) xs)))
  (defun org-startup-option? (x)
    (gethash x set)))

(defun org-header (&key trace)
  "15.6 Summary of in-buffer settings"
  (flet ((org-keywords-as-plist (xs)
           (iter (for x in xs)
                 (appending (destructuring-bind (&key keyword value) x
                              (list (make-keyword (string-upcase keyword))
                                    value)))))
         (keywords-as-flags (xs)
           (mapcan (rcurry #'list t) xs))
         (parse-startup (xs)
           (let ((all-opts (mapcar (compose #'make-keyword #'string-upcase)
                                   (split-sequence:split-sequence #\Space xs
                                                                  :remove-empty-subseqs t)))
                 decided-co-sets
                 valid unknown duplicate conflicted)
             (dolist (o all-opts)
               (let* ((co-set (org-startup-option? o))
                      (conflicted? (find co-set decided-co-sets))
                      (conflict (find-if (lambda (x) (find x valid)) co-set)))
                 (cond ((not co-set)
                        (push o unknown))
                       ((find o valid)
                        (push o duplicate))
                       (conflicted?
                        (push o conflicted)
                        (push conflict conflicted))
                       (t
                        (push co-set decided-co-sets)
                        (push o valid)))))
             (setf valid (set-difference valid conflicted))
             (values all-opts valid unknown duplicate conflicted))))
    (named-seq*
     (<- mix (opt* (org-section (org-greater-element))))
     (multiple-value-bind (raw-keywords section-content)
         (unzip (lambda (x) (and (consp x) (eq :keyword (car x)))) (second mix))
       (let ((keyword-plist (org-keywords-as-plist raw-keywords)))
         (when trace
           (format t ";;; header options:~{ ~S~}~%" keyword-plist)
           (when section-content
             (format t ";;; header section: ~S~%" section-content)))
         (destructuring-bind (&key (startup "") &allow-other-keys) keyword-plist
           (multiple-value-bind (all valid unknown duplicate conflicted)
               (parse-startup startup)
             (when trace
               (format t ";;; header startup:~%")
               (when valid
                 (format t ";;;    valid:     ~{ ~S~}~%" valid))
               (when unknown
                 (format t ";;;    unknown:   ~{ ~S~}~%" unknown))
               (when duplicate
                 (format t ";;;    duplicate: ~{ ~S~}~%" duplicate))
               (when conflicted
                 (format t ";;;    conflicted:~{ ~S~}~%" conflicted)))
             `((:header
                ,(append (remove-from-plist keyword-plist :startup)
                         (when valid
                           (list :startup (keywords-as-flags valid)))
                         (when (or unknown conflicted)
                           (list :startup-all (keywords-as-flags all)))))
               ,@(when section-content
                       (list (list :section section-content)))))))))))

;;;
;;; Whole thing
(defun org-parser ()
  (mdo
    (<- initial (org-header))
    (<- entries    (many* (org-top-entry (tree-getf (first initial) :header :startup))))
    (result (cons :org
                  (append initial entries)))))

(defun org-parse-string (string)
  (parse-string* (org-parser) string))

(defun org-parse (x)
  (etypecase x
    (string
     (org-parse-string x))
    ((or pathname stream)
     (org-parse-string (read-file-into-string x)))))

;;;
;;; Testing
(progn
  ;; (progn (require :cl-org-mode) (in-package :cl-org-mode))
  (defun string-position-context-full (string cache posn &key (around 0))
    (multiple-value-bind (lineno lposn ctxstart ctxend)
        (parser-combinators::string-position-context cache posn :around around)
      (let ((lend (or (position #\Newline string :start lposn)
                      (length string))))
        (values lineno (- posn lposn) lposn lend
                (subseq string lposn lend)
                (subseq string ctxstart ctxend)))))
  (defun show-string-position (place string posn cache &key (around 0))
    (multiple-value-bind (lineno col lposn rposn line ctx) (string-position-context-full string cache posn :around around)
      (declare (ignore lposn rposn line))
      (let ((fmt (format nil "; at ~~A, line ~~D, col ~~D:~~%~~A~~%~~~D@T^~~%" col)))
        (format t fmt place (1+ lineno) (1+ col) ctx))))
  (defun org-complexity (text &optional (parser (if (and (plusp (length text))
                                                         (starts-with #\* text))
                                                    (curry #'org-entry 1)
                                                    #'org-element)))
    (with-position-cache (cache text)
      (multiple-value-bind (result vector-context successp front seen-positions)
          (parse-string* (funcall parser) text)
        (declare (ignorable result vector-context front))
        #+nil
        (format t "parser ~S, text:~%~S~%result ~S, vector-context ~S, successp ~S, front ~S, seen-positions ~S~%"
                parser text result vector-context successp front seen-positions)
        (unless successp
          (error "Failed to parse (using ~S):~%~A"
                 parser (format nil "--- 8< ---~%~S~%--- >8 ---~%" text)))
        (apply #'+ (hash-table-values seen-positions)))))
  (defparameter *overhead-measured-parsers*
    `(("element-line" nil nil ,#'org-element-line)
      ("element"      nil nil ,#'org-element)
      ("section"      nil t   ,(curry #'org-section (org-greater-element)))
      ("entry"        t   t   ,(curry #'org-entry 1))
      ("org"          t   t   ,#'org-parser)))
  (defun parser-context-overheads (&key
                                     debug
                                     (depth-range 5) (depth-start 0)
                                     (text-length-range 15)
                                     (parsers *overhead-measured-parsers*)
                                     (text-meat-char #\x)
                                     trailing-newline-p
                                   &aux
                                     (*debug-mode* debug))
    (labels ((generate-overhead-org (depth text-length)
               (iter (for i below (1+ depth))
                     (when (plusp i)
                       (collecting (strconcat* (make-string i :initial-element #\*)
                                               " "
                                               (string (code-char (+ i (1- (char-code #\a)))))
                                               +newline-string+)
                                   into lines))
                     (finally
                      (return (strconcat
                               (append lines
                                       (list (when (plusp text-length)
                                               (strconcat*
                                                (make-string (1- text-length)
                                                             :initial-element text-meat-char)
                                                "x")))
                                       (when trailing-newline-p
                                         (list +newline-string+)))))))))
      (values-list (map-product (lambda (parser-spec depth)
                                  (destructuring-bind (name entry-capable-p empty-capable-p parser)
                                      parser-spec
                                    (when (if (zerop depth)
                                              (not entry-capable-p)
                                              entry-capable-p)
                                      (let* ((seq (iter (for text-length below text-length-range)
                                                        (collect
                                                            (when (or (plusp text-length)
                                                                      empty-capable-p)
                                                              (org-complexity
                                                               (generate-overhead-org depth text-length)
                                                               parser)))))
                                             (tail (last seq 2))
                                             (rate (- (second tail) (first tail))))
                                        (append (list name) seq
                                                (list (list :char-cost rate)))))))
                                parsers (iota depth-range :start depth-start)))))
  (defun try-org-file (filename &key profile (parser #'org-parser)
                       &aux
                         (string (alexandria:read-file-into-string filename)))
    (with-position-cache (cache string)
      (flet ((string-context (posn &key (around 0))
               (string-position-context-full string cache posn :around around))
             (top-hits (hash n &aux
                             (alist (hash-table-alist hash))
                             (sorted (sort alist #'> :key #'cdr))
                             (top (subseq sorted 0 (min n (hash-table-count hash)))))
               (mapcar (lambda (x)
                         (destructuring-bind (posn . hits) x
                           (list* posn hits (multiple-value-list (parser-combinators::string-position-context cache posn)))))
                       top))
             #+nil
             (show-fn (posn)
               (show-string-position "x" string posn cache))
             (print-hit (posn hits)
               (show-string-position (format nil "~D hits" hits)
                                     string posn cache)))
        (declare (ignorable #'print-hit))
        (format t ";;;~%;;;~%;;; trying: ~S~%" filename)
        (multiple-value-bind (result vector-context successp front seen-positions)
            (parse-string* (funcall parser) string)
          (declare (ignore vector-context))
          (if (and successp (null front))
              (let ((top-hits (top-hits seen-positions 25))
                    (total-references (apply #'+ (hash-table-values seen-positions))))
                (when (eq profile :full)
                  (Iter (for line in (split-sequence:split-sequence #\Newline string))
                        (for lineno from 0)
                        (format t ";   ~A~%" line)
                        (dolist (line-top (remove lineno top-hits :test #'/= :key #'third))
                          (destructuring-bind (posn hits lineno lineposn ctxstart ctxend) line-top
                            (declare (ignore ctxstart ctxend))
                            (let* ((col (- posn lineposn))
                                   (fmt (format nil ";;; ~~~D@T^  ~~D hits, posn ~~D:~~D:~~D~~%" col)))
                              (format t fmt hits posn lineno col))))))
                (when profile
                  (format t ";;; total context references: ~D~%" total-references))
                (values result total-references))
              (let ((failure-posn (slot-value (slot-value front 'parser-combinators::context) 'position)))
                (multiple-value-bind (lineno col lposn rposn line ctx) (string-context failure-posn :around 2)
                  (declare (ignore lposn rposn line))
                  (format t "; ~A at line ~D, col ~D:~%~A~%"
                          (if successp "partial match" "failure") (1+ lineno) col ctx))))
          #+nil
          (iter (for (posn lineno hits) in )
                (print-hit posn hits))))))
  (defun maybe-time (timep f)
    (if timep (time (funcall f)) (funcall f)))
  (defmacro with-maybe-time ((time) &body body)
    `(maybe-time ,time (lambda () ,@body)))
  (load "~/org-file-index.lisp")
  (defun test (&key profile (total (length *org-files*))
               &aux
                 (filelist *org-files*)
                 (total-contexts 0)
                 (succeeded 0))
    (with-maybe-time (profile)
      (dolist (f (subseq filelist 0 total))
        (with-maybe-time (profile)
          (multiple-value-bind (success ncontexts) (try-org-file f :profile profile)
            (when ncontexts
              (incf total-contexts ncontexts))
            (when success
              (incf succeeded))))))
    (format t ";; total contexts: ~D~%" total-contexts)
    (format t ";; success rate: ~D/~D~%" succeeded total)))
