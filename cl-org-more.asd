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
     (:file "present"))))
  :in-order-to ((asdf:test-op (asdf:load-op :cl-org-more/tests)))
  :perform (asdf:test-op :after (op c)
                         (or (funcall (intern "DO-TESTS" (find-package "RTEST")))
                             (error "TEST-OP failed for CL-ORG-MORE-TESTS")))
  :serial t
  :depends-on (:alexandria :iterate :cl-org-more/raw :parser-combinators-debug))

(defsystem :cl-org-more/tests
  :serial t
  :components
  ((:module :t
    :serial t
    :components
    ((:file "raw")
     (:file "middle"))))
  :depends-on (:cl-org-more/raw :parser-combinators-debug :cl-org-more :rt))

(defsystem :cl-org-more/raw
  :components
  ((:module :src
    :serial t
    :components
    ((:module :raw
      :serial t
      :components
      ((:file "packages")
       (:file "utils")
       (:file "parser"))))))
  :serial t
  :depends-on (:alexandria :parser-combinators :split-sequence))

(defsystem :cl-org-more/extended
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
  :in-order-to ((asdf:test-op (asdf:load-op :cl-org-more/extended/tests)))
  :perform (asdf:test-op :after (op c)
                         (or (funcall (intern "DO-TESTS" (find-package "RTEST")))
                             (error "TEST-OP failed for CL-ORG-MORE-EXTENDED-TESTS")))
  :depends-on (:cl-org-more :ironclad :flexi-streams))

(defsystem :cl-org-more/extended/tests
  :serial t
  :components
  ((:module :t
    :serial t
    :components
    ((:file "extended"))))
  :depends-on (:cl-org-more/tests :cl-org-more/extended))
