(defpackage :cl-org-more-extended
  (:nicknames :org-extended :org-ext)
  (:use :common-lisp :alexandria :iterate
        :cl-org-more :cl-org-more-slots :cl-org-more-utils)
  (:import-from :cl-org-more-raw
                :strconcat :strconcat* :unzip)
  (:export
   ;;
   #:org-dress-error
   #:org-object-error
   #:org-object-simple-error
   #:org-object-warning
   #:org-object-simple-warning
   #:org-object-relink-error
   ;;
   #:hash-of
   #:with-hash-cache
   #:clear-hash-cache
   ;;
   #:org-parse-extended))
