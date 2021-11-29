(defpackage :cl-org-more-middle-tests
  (:use :cl
        :alexandria
        :iterate
	:cl-org-more))

(in-package :cl-org-more-middle-tests)

(rtest:deftest :middle/org-dress (length (mapcar #'org-parse cl-org-more-raw-tests::*org-files*)) 3)
(rtest:deftest :middle/org-present (org-present :flat (org-parse (lastcar cl-org-more-raw-tests::*org-files*)) (make-broadcast-stream)) nil)
