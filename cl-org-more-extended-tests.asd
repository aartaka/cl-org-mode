;;; -*- lisp -*-

(defsystem :cl-org-more-extended-tests
  :serial t
  :components
  ((:module :t
	    :serial t
	    :components
            ((:file "extended"))))
  :depends-on (:cl-org-more-tests
               :cl-org-more-extended))
