;;; -*- lisp -*-

(defsystem :cl-org-more-tests
  :serial t
  :components
  ((:module :t
	    :serial t
	    :components
            ((:file "raw")
             (:file "middle"))))
  :depends-on (:cl-org-more-raw :parser-combinators-debug
               :cl-org-more :rt))
