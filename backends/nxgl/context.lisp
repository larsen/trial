(in-package #:org.shirakumo.fraf.trial.nxgl)

(defvar *monitor* (make-instance 'monitor))

(defclass context (trial:context)
  ((pointer :initform NIL :accessor pointer)
   (thread :initform NIL :accessor thread)
   (profile :initarg :profile :initform NIL :accessor profile)
   (version :initarg :version :initform NIL :accessor version)
   (vsync :initform NIL :accessor vsync)
   (initargs :initform () :accessor initargs)
   (mouse-pos :initform (vec 0 0) :accessor mouse-pos)
   (close-pending-p :initform NIL :accessor close-pending-p)))

(defmethod shared-initialize :after ((context context) slots
                                     &key (version NIL version-p)
                                          (profile NIL profile-p)
                                          (width NIL width-p)
                                          (height NIL height-p)
                                          (vsync NIL vsync-p)
                                          (robustness NIL robustness-p)
                                          (forward-compat NIL forward-compat-p)
                                          (debug-context NIL debug-context-p)
                                          double-buffering stereo-buffer title visible)
  (declare (ignore double-buffering stereo-buffer title visible))
  (flet (((setf g) (value name) (setf (getf (initargs context) name) value)))
    (macrolet ((maybe-set (var &optional (name (intern (string var) :keyword)))
                 `(when ,(let ((*print-case* (readtable-case *readtable*)))
                           (intern (format NIL "~a-~a" var 'p)))
                    (setf (g ,name) ,var))))
      (maybe-set width)
      (maybe-set height)
      (maybe-set vsync)
      (maybe-set profile)
      (maybe-set robustness)
      (maybe-set forward-compat)
      (maybe-set debug-context)
      (when version-p
        (setf (g :context-version-major) (first version))
        (setf (g :context-version-minor) (second version))))))

(defmethod initialize-instance ((context context) &key)
  (prog1 (call-next-method)
    (create-context context)))

(defmethod create-context ((context context))
  (flet ((arg (arg) (getf (initargs context) arg)))
    (let ((pointer (apply #'nxgl:create-context (arg :width) (arg :height)
                          :focus-gain (cffi:callback focus-gain)
                          :focus-lose (cffi:callback focus-lose)
                          :resize (cffi:callback resize)
                          :quit (cffi:callback quit)
                          :mouse-move (cffi:callback mouse-move)
                          :mouse-press (cffi:callback mouse-press)
                          :mouse-release (cffi:callback mouse-release)
                          :mouse-wheel (cffi:callback mouse-wheel)
                          :key-press (cffi:callback key-press)
                          :key-release (cffi:callback key-release)
                          (initargs context))))
      (when (cffi:null-pointer-p pointer)
        (error "Failed to create context: ~a" nxgl:error))
      (setf (pointer context) pointer)
      (setf (vsync context) (arg :vsync))
      context)))

(defmethod destroy-context ((context context))
  (when (pointer context)
    (nxgl:destroy-context (pointer context))
    (setf (pointer context) NIL))
  context)

(defmethod valid-p ((context context))
  (not (null (pointer context))))

(defmethod make-current ((context context))
  (unless (nxgl:make-current (pointer context))
    (nxgl:check-error)))

(defmethod done-current ((context context))
  context)

(defmethod hide ((context context))
  context)

(defmethod show ((context context) &key mode &allow-other-keys)
  (when mode
    (resize context (first mode) (second mode)))
  context)

(defmethod visible-p ((context context))
  T)

(defmethod resize ((context context) width height)
  (unless (nxgl:resize (pointer context) width height)
    (error "Failed to resize"))
  (handle (make-event 'resize :width width :height height) (handler context))
  context)

(defmethod quit ((context context))
  (setf (close-pending-p context) T)
  context)

(defmethod swap-buffers ((context context))
  (unless (nxgl:swap-buffers (pointer context))
    (nxgl:check-error))
  context)

(defmethod show-cursor ((context context))
  context)

(defmethod hide-cursor ((context context))
  context)

(defmethod lock-cursor ((context context))
  context)

(defmethod unlock-cursor ((context context))
  context)

(defmethod cursor ((context context))
  NIL)

(defmethod (setf cursor) (cursor (context context))
  cursor)

(defmethod title ((context context))
  "Trial")

(defmethod (setf title) (value (context context))
  value)

(defmethod (setf vsync) :before (mode (context context))
  (unless (nxgl:swap-interval (pointer context) (ecase mode ((NIL :off) 0) ((:on T) 1) (:adaptive -1)))
    (nxgl:check-error)))

(defmethod current-monitor ((context context))
  *monitor*)

(defmethod list-monitors ((context context))
  (list *monitor*))

(defmethod list-video-modes ((monitor monitor))
  (list (list 1920 1080 60 "")
        (list 1280 720 60 "")))

(defmethod find-monitor (name (context context))
  *monitor*)

(defmethod name ((monitor monitor))
  "")

(defmethod clipboard ((context context))
  "")

(defmethod (setf clipboard) (value (context context))
  value)

(defmethod cursor-position ((context context))
  (vec 0 0))

(defmethod (setf cursor-position) (pos (context context))
  pos)

(defmethod local-key-string ((context context) scan-code)
  "")

(defmethod (setf icon) (icon (context context))
  icon)

(defmethod width ((context context))
  (nxgl:width (pointer context)))

(defmethod height ((context context))
  (nxgl:height (pointer context)))

(cffi:define-foreign-library %gl::opengl
  (t "opengl.nso"))

(deploy:define-hook (:boot nxgl) ()
  (deploy:status 1 "Initialising NXGL")
  (cffi:load-foreign-library 'nxgl:nxgl)
  (nxgl:init)
  (setf %gl:*gl-get-proc-address* #'nxgl:proc-address)
  (%gl::reset-gl-pointers))

(deploy:define-hook (:quit nxgl) ()
  (nxgl:shutdown))

(defun trial:launch-with-context (&optional main &rest initargs)
  (let ((main (apply #'make-instance main initargs)))
    (start main)
    (trial:rename-thread "input-loop")
    (v:debug :trial.backend.nxgl "Entering input loop")
    (unwind-protect
         (let* ((context (trial:context main))
                (*context* context))
           (loop until (close-pending-p context)
                 do (poll-input main)
                    (nxgl:poll (pointer context))
                    (sleep 0.0001)))
      (v:debug :trial.backend.nxgl "Cleaning up")
      (finalize main))))

(defun trial:make-context (&optional handler &rest initargs)
  (apply #'make-instance 'context :handler handler initargs))

(defmacro define-callback (name args &body body)
  `(cffi:defcallback ,name :void ((context :pointer) (user :pointer) ,@args)
     (declare (ignore context user))
     (let ((context *context*))
       (flet ((fire (event-type &rest args)
                (handle (apply #'make-event event-type args) (handler context))))
         (declare (ignorable #'fire))
         ,@body))))

(define-callback focus-gain ()
  (fire 'gain-focus))

(define-callback focus-lose ()
  (fire 'lose-focus))

(define-callback resize ((width :int) (height :int))
  (fire 'resize :width width :height height))

(define-callback quit ()
  (fire 'window-close))

(define-callback mouse-move ((x :int) (y :int))
  (let ((current (vec x y)))
    (fire 'mouse-move :old-pos (mouse-pos context)
                      :pos current)
    (setf (mouse-pos context) current)))

(define-callback mouse-press ((button :int))
  (fire 'mouse-press :pos (mouse-pos context) :button (button->keyword button)))

(define-callback mouse-release ((button :int))
  (fire 'mouse-release :pos (mouse-pos context) :button (button->keyword button)))

(define-callback mouse-wheel ((delta :int))
  (fire 'mouse-scroll :pos (mouse-pos context) :delta delta))

(define-callback key-press ((code :int))
  (fire 'key-press :key (scan-code->keyword code)))

(define-callback key-release ((code :int))
  (fire 'key-release :key (scan-code->keyword code)))

(defmethod org.shirakumo.depot:commit :after ((depot org.shirakumo.depot.zip::zip-file-archive) &key)
  (nxgl:commit-save))
