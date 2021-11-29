;;; -*- lisp -*-

(defsystem :cl-org-more-extended
  :components
  ((:module :src
	    :serial t
	    :components
	    ((:module :extended
                      :serial t
                      :components
                      ((:file "packages")
                       (:file "conditions")
                       (:file "utils")
                       (:file "hash")
                       (:file "extended")
                       ))
	     )))
  :in-order-to ((asdf:test-op (asdf:load-op :cl-org-more-extended-tests)))
  :perform (asdf:test-op :after (op c)
             (or (funcall (intern "DO-TESTS" (find-package "RTEST")))
                 (error "TEST-OP failed for CL-ORG-MORE-EXTENDED-TESTS")))
  :depends-on (:cl-org-more :ironclad :flexi-streams))
