(in-package :lem)

(defvar *file-type-relationals* '())
(defvar *program-name-relationals* '())

(defun get-file-mode (pathname)
  (alexandria:assoc-value *file-type-relationals*
                          (pathname-type pathname)
                          :test #'string=))

(defun associcate-file-type (type-list mode)
  (dolist (type type-list)
    (pushnew (cons type mode)
             *file-type-relationals*
             :test #'equal)))

(defmacro define-file-type ((&rest type-list) mode)
  `(associcate-file-type ',type-list ',mode))

(defun get-program-mode (program-name)
  (alexandria:assoc-value *program-name-relationals*
                          program-name
                          :test #'string=))

(defun associcate-program-name-with-mode (program-names mode)
  (dolist (name program-names)
    (pushnew (cons name mode)
             *program-name-relationals*
             :test #'equal)))

(defmacro define-program-name-with-mode ((&rest program-names) mode)
  `(associcate-program-name-with-mode ',program-names ',mode))

;;;
(defun scan-var/val (str start)
  (multiple-value-bind (start end reg-starts reg-ends)
      (ppcre:scan "\\s*([a-zA-Z0-9-_]+)\\s*:\\s*" str :start start)
    (when start
      (let ((var (subseq str
                         (aref reg-starts 0)
                         (aref reg-ends 0))))
        (multiple-value-bind (val end)
            (handler-bind ((error (lambda (c)
                                    (declare (ignore c))
                                    (return-from scan-var/val))))
              (let ((*read-eval* nil))
                (read-from-string str nil nil :start end)))
          (values end var val))))))

(defun set-file-property (buffer var val)
  (cond ((string-equal var "mode")
         (let ((mode (find-mode-from-name val)))
           (when mode
             (change-buffer-mode buffer mode))))
        (t
         (let ((ev (find-editor-variable var)))
           (if ev
               (setf (variable-value ev :buffer buffer) val)
               (setf (buffer-value buffer (string-downcase var)) val))))))

(defun scan-line-property-list (buffer str)
  (loop :with i := 0
        :do (multiple-value-bind (pos var val)
                (scan-var/val str i)
              (unless pos (return))
              (set-file-property buffer var val)
              (setf i pos))))

(defun scan-file-property-list (buffer)
  (with-point ((cur-point (buffer-point buffer)))
    (buffer-start cur-point)
    (loop :until (end-line-p cur-point)
          :for string := (line-string cur-point)
          :do (ppcre:register-groups-bind (result)
                  ("-\\*-(.*)-\\*-" string)
                (when result
                  (scan-line-property-list buffer result)
                  (return)))
              (if (string= "" (string-trim '(#\space #\tab) string))
                  (line-offset cur-point 1)
                  (return)))))
;;;
(defun parse-shebang (line)
  (let* ((args (split-sequence:split-sequence #\space line :remove-empty-subseqs t))
         (program (alexandria:lastcar (split-sequence:split-sequence #\/ (alexandria:lastcar args)))))
    (cond ((string= program "env")
           (second args))
          (t
           program))))

(defun program-name-to-mode (program)
  (or (find-mode-from-name program)
      (get-program-mode program)))

(defun parse-file-mode (buffer)
  (with-point ((point (buffer-point buffer)))
    (buffer-start point)
    (let ((header-line (line-string point)))
      (when (alexandria:starts-with-subseq "#!" header-line)
        (program-name-to-mode (parse-shebang header-line))))))

(defun detect-file-mode (buffer)
  (or (get-file-mode (buffer-filename buffer))
      (parse-file-mode buffer)))

(defun process-file-mode-and-options (buffer)
  (alexandria:when-let (mode (detect-file-mode buffer))
    (change-buffer-mode buffer mode))
  (scan-file-property-list buffer))

;;;
(defun detect-external-format-from-file (pathname)
  (values (inq:dependent-name (inq:detect-encoding (pathname pathname) :jp))
          (or (inq:detect-end-of-line (pathname pathname)) :lf)))

(setf *external-format-function* 'detect-external-format-from-file)
