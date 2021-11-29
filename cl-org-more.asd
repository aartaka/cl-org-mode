;;; -*- lisp -*-

(defsystem :cl-org-more
  :components
  ((:module :src
	    :serial t
	    :components
	    ((:file "packages")
	     (:file "protocol")
             (:file "utils")
	     (:file "conditions")
	     (:file "cl-org-more")
	     (:file "dress")
	     (:file "traversal")
	     (:file "present")
	     )))
  :in-order-to ((asdf:test-op (asdf:load-op :cl-org-more-tests)))
  :perform (asdf:test-op :after (op c)
             (or (funcall (intern "DO-TESTS" (find-package "RTEST")))
                 (error "TEST-OP failed for CL-ORG-MORE-TESTS")))
  :serial t
  :depends-on (:alexandria :iterate :cl-org-more-raw :parser-combinators-debug))
