(in-package :formlets)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; CLASS DECLARATIONS
(defclass formlet ()
  ((name			 :reader name			:initarg :name)
   (fields			 :reader fields			:initarg :fields)
   (validation-functions 	 :accessor validation-functions :initarg :validation-functions	 :initform nil)
   (error-messages	 	 :reader error-messages		:initarg :error-messages 	 :initform nil)
   (submit-caption		 :reader submit			:initarg :submit		 :initform "Submit")
   (enctype			 :accessor enctype		:initarg :enctype		 :initform "application/x-www-form-urlencoded")
   (on-success			 :reader on-success		:initarg :on-success)))

(defclass formlet-field ()
  ((name			:reader name			:initarg :name)
   (validation-functions	:accessor validation-functions	:initarg :validation-functions	:initform nil)
   (default-value		:reader default-value		:initarg :default-value		:initform nil)
   (error-messages		:accessor error-messages	:initarg :error-messages	:initform nil)))
(defclass hidden			(formlet-field) ())
(defclass text				(formlet-field) ())
(defclass textarea			(formlet-field) ())
(defclass password			(formlet-field) ())
(defclass file				(formlet-field) ())
(defclass checkbox			(formlet-field) ())

(defclass formlet-field-set		(formlet-field)
  ((value-set :accessor value-set :initarg :value-set :initform nil))
  (:documentation "This class is for fields that show the user a list of options"))
(defclass select			(formlet-field-set) ())
(defclass radio-set			(formlet-field-set) ())

(defclass formlet-field-return-set	(formlet-field-set) ()
  (:documentation "This class is specifically for fields that return multiple values from the user"))
(defclass multi-select			(formlet-field-return-set) ())
(defclass checkbox-set			(formlet-field-return-set) ())

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; METHODS
;;;;;;;;;;post-value
;;;;NOTE:   This section exists because Hunchentoots' (post-parameter [field-name])
;;        returns a single value. This is problematic for multi-select boxes and checkbox sets
;;        (both of which potentially return multiple values from the user).
;;          post-value is not necessarily Hunchentoot specific, but it does expect values in the form of an alist

(defmethod post-value ((formlet formlet) post-alist)
  (mapcar (lambda (f) (post-value f post-alist)) (fields formlet)))

(defmethod post-value ((field formlet-field) post-alist)
  (cdr (assoc (name field) post-alist :test #'string=)))

(defmethod post-value ((field formlet-field-return-set) post-alist)
  (loop for (k . v) in post-alist
	if (string= k (name field)) collect v))
  
;;;;;;;;;;validate
;;;;;NOTE: The validate methods each return (values [validation result] [errors]). 
;;         [validation result] is a boolean
;;         [errors] can be either a list or tree of strings

(defmethod validate ((formlet formlet) form-values)
  (let ((errors (if (validation-functions formlet)
		    (make-list (length (fields formlet)) ;;so that elements don't get cut off
			       :initial-element
			       (loop for f in (validation-functions formlet)
				     for msg in (error-messages formlet)
				     unless (apply f form-values) collect msg))
		    (loop for f in (fields formlet)
			  for v in form-values
			  collect (multiple-value-bind (result error) (validate f v) (unless result error))))))
    (values (every #'null errors) errors)))

(defmethod validate ((field formlet-field) value)
  "Returns (values T NIL) if there are no errors, and (values NIL list-of-errors). 
   By default, a formlet-field passes only its own value to its validation functions."
  (let ((errors (loop for fn in (validation-functions field)
		      for msg in (error-messages field)
		      unless (funcall fn value) collect msg)))
    (values (every #'null errors) errors)))

;;;;;;;;;;show
;;;; The show functions just take a formlet/(-field)?/ (along with its value/s?/ and error/s?/)
;;   and output the corresponding HTML. This part is cl-who specific, but it could be easily made portable
;;   by replacing html-to-stout and html-to-str with raw format calls

(defmethod show ((formlet formlet) &optional values errors)
  (with-slots (error-messages name enctype) formlet
    (html-to-stout
      (when (and (not (every #'null errors)) error-messages)
	(htm (:span :class "general-error" 
		    (dolist (s (car errors)) 
				  (htm (:p (str s)))))))
      (:form :name (string-downcase name) :id (string-downcase name) :action (format nil "/validate-~(~a~)" name) :enctype enctype :method "post"
	     (:ul :class "form-fields"
		  (loop for a-field in (fields formlet)
			for e in errors
			for v in values
			do (str (show a-field v (when (and e (not error-messages)) e))))
		  (:li (:span :class "label") (:input :type "submit" :class "submit" :value (submit formlet))))))))

(defmethod show ((field hidden) &optional value error)
  (html-to-str (:input :name (name field) :value value :type "hidden")))

(defmacro define-show (field-type &body body)
  `(defmethod show ((field ,field-type) &optional value error)
     (html-to-str 
       (:li :class (string-downcase (name field))
	    (:span :class "label" (str (string-capitalize (regex-replace-all "-" (name field) " "))))
	    ,@body
	    (when error (htm (:span :class "formlet-error"
				    (dolist (s error) 
				      (htm (:p (str s)))))))))))

(define-show formlet-field (:input :name (name field) :value value :class "text-box"))
(define-show textarea (:textarea :name (name field) (str value)))
(define-show password (:input :name (name field) :type "password" :class "text-box"))
(define-show file (:input :name (name field) :type "file" :class "file"))

(define-show select 
  (:select :name (name field)
	   (loop for v in (value-set field) 
		 do (htm (:option :value v :selected (when (string= v value) "selected") (str v))))))

(define-show checkbox
  (:input :type "checkbox" :name (name field) :value (name field) 
	  :checked (when (string= (name field) value) "checked")))

(define-show radio-set 
  (loop for v in (value-set field)
	do (htm (:span :class "input+label" 
			      (:input :type "radio" :name (name field) :value v 
				      :checked (when (string= v value) "checked"))
			      (str v)))))

(define-show multi-select
  (:select :name (name field) :multiple "multiple" :size 5
	   (loop for v in (value-set field)
		 do (htm (:option :value v 
				  :selected (when (member v value :test #'string=) "selected")
					    (str v))))))

(define-show checkbox-set
  (loop for v in (value-set field)
	do (htm (:span :class "input+label"
			      (:input :type "checkbox" :name (name field) :value v 
				      :checked (when (member v value :test #'string=) "checked"))
			      (str v)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; PREDICATES
(defmacro define-predicate (name (&rest args) &body body)
  `(defun ,name ,args (lambda (val) ,@body)))

;;;;;;;;;; basic field predicates
(define-predicate longer-than? (num) (> (length val) num))
(define-predicate shorter-than? (num) (< (length val) num))
(define-predicate matches? (regex) (scan regex val))
(define-predicate mismatches? (regex) (not (scan regex val)))
(define-predicate not-blank? () (or (null val) (and (stringp val) (not (string= "" val)))))
(define-predicate same-as? (field-name-string) (string= val (post-parameter field-name-string)))

;;;;;;;;;; file-related
;; a hunchentoot file tuple is '([temp filename] [origin filename] [file mimetype])
(define-predicate file-type? (&rest accepted-types) (member (third val) accepted-types :test #'equal))
(define-predicate file-smaller-than? (byte-size) (and (car val) (> byte-size (file-size (car val)))))

;;;;;;;;;; set-related
(define-predicate picked-more-than? (num) (> (length val) num))
(define-predicate picked-fewer-than? (num) (< (length val) num))
(define-predicate picked-exactly? (num) (= (length val) num))