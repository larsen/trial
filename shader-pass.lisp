#|
 This file is a part of trial
 (c) 2017 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:org.shirakumo.fraf.trial)
(in-readtable :qtools)

(defclass shader-pass-class (shader-subject-class)
  ((pass-inputs :initarg :pass-inputs :initform () :accessor pass-inputs)))

(defmethod c2mop:validate-superclass ((class shader-pass-class) (superclass T))
  NIL)

(defmethod c2mop:validate-superclass ((class T) (superclass shader-pass-class))
  NIL)

(defmethod c2mop:validate-superclass ((class shader-pass-class) (superclass standard-class))
  T)

;; FIXME: check for input compatibility in inheritance

(defclass shader-pass (shader-subject)
  ((pass-inputs :initarg :pass-inputs :initform () :accessor pass-inputs))
  (:metaclass shader-pass-class))

(defgeneric register-object-for-pass (pass object))
(defgeneric shader-program-for-pass (pass object))

(defmethod paint ((pass shader-pass) target)
  (when (typep target 'main)
    (paint (scene target) pass)))

(defmacro define-shader-pass (name direct-superclasses inputs &optional slots &rest options)
  (unless (find :metaclass options :key #'car)
    (push '(:metaclass shader-pass-class) options))
  `(defclass ,name (,@direct-superclasses shader-pass)
     ,slots
     ,@options
     (:pass-inputs ,@inputs)))

(define-shader-pass per-object-pass ()
  ()
  ((assets :initform (make-hash-table :test 'eql) :accessor assets)))

(define-handler (per-object-pass update-shader-for-redefined-subject subject-class-redefined) (ev subject-class)
  (let ((assets (assets per-object-pass)))
    (flet ((refresh (class)
             (let ((loaded (and (gethash class assets) (resource (gethash class assets)))))
               (when loaded (offload (gethash class assets)))
               (remhash class assets)
               (register-object-for-pass per-object-pass class)
               (when loaded (load (gethash class assets))))))
      (cond ((eql subject-class (class-of per-object-pass))
             ;; Pass changed, recompile everything
             (loop for class being the hash-keys of assets
                   do (refresh class)))
            ((and (typep subject-class 'shader-subject-class)
                  (not (typep subject-class 'shader-pass-class)))
             ;; Object changed, recompile it
             (refresh subject-class))))))

(defmethod load progn ((pass per-object-pass))
  (loop for v being the hash-values of (assets pass)
        do (load v)))

(defmethod shader-program-for-pass ((pass per-object-pass) (subject shader-subject))
  (gethash (class-of subject) (assets pass)))

(defmethod coerce-pass-shader ((pass per-object-pass) type spec)
  (glsl-toolkit:merge-shader-sources
   (list (class-shader type pass) spec)))

(defmethod register-object-for-pass ((pass per-object-pass) o))

(defmethod register-object-for-pass ((pass per-object-pass) (class shader-subject-class))
  (let ((shaders ()))
    (unless (gethash class (assets pass))
      (loop for (type spec) on (effective-shaders class) by #'cddr
            for inputs = (coerce-pass-shader pass type spec)
            for shader = (make-asset 'shader-asset inputs :type type)
            do (push shader shaders))
      (setf (gethash class (assets pass))
            (make-asset 'shader-program-asset shaders)))))

(defmethod register-object-for-pass ((pass per-object-pass) (subject shader-subject))
  (register-object-for-pass pass (class-of subject)))

(defmethod paint :around ((subject shader-subject) (pass per-object-pass))
  (let ((program (shader-program-for-pass pass subject)))
    (gl:use-program (resource program))
    ;; FIXME: register inputs as uniforms... ?
    (call-next-method)))

(define-shader-pass single-shader-pass ()
  ()
  ((shader-program :initform (make-instance 'shader-program-asset) :accessor shader-program)
   (pass-uniforms :initarg :uniforms :initform () :accessor pass-uniforms)))

(define-handler (single-shader-pass update-shader-for-redefined-subject subject-class-redefined) (ev subject-class)
  (when (eql subject-class (class-of single-shader-pass))
    (let* ((program (shader-program single-shader-pass))
           (loaded (and program (resource program))))
      (when loaded (offload program))
      (setf (shader-program single-shader-pass) (make-class-shader-program single-shader-pass))
      (when loaded (load (shader-program single-shader-pass))))))

(defmethod load progn ((pass single-shader-pass))
  (setf (shader-program pass) (load (make-class-shader-program pass))))

(defmethod register-object-for-pass ((pass single-shader-pass) o))

(defmethod shader-program-for-pass ((pass single-shader-pass) o)
  (shader-program pass))

(defmethod paint :around ((pass single-shader-pass) target)
  (let ((program (shader-program pass)))
    (gl:use-program (resource program))
    (loop for (uniform value) in (pass-uniforms pass)
          do (setf (uniform program uniform) value))
    ;; FIXME: register inputs as uniforms properly
    (loop for (uniform fbo) in (pass-inputs pass)
          for texture-index from 8
          for texture-name in '(:texture8 :texture9 :texture10)
          do (setf (uniform program uniform) texture-index)
             (gl:active-texture texture-name)
             ;; First is always the colour texture
             (gl:bind-texture :texture-2d (resource (first (textures fbo)))))
    (call-next-method)))

(define-shader-pass post-effect-pass (single-shader-pass)
  ()
  ((vertex-array :initform (asset 'geometry 'fullscreen-square) :accessor vertex-array)))

(defmethod load progn ((pass post-effect-pass))
  (load (vertex-array pass)))

(defmethod paint ((pass post-effect-pass) target)
  (let ((vao (vertex-array pass)))
    (with-pushed-attribs
      (disable :depth-test)
      (gl:bind-vertex-array (resource vao))
      (%gl:draw-elements :triangles (size vao) :unsigned-int 0)
      (gl:bind-vertex-array 0))))

(define-class-shader post-effect-pass :vertex-shader
  "
layout (location = 0) in vec3 position;
layout (location = 1) in vec2 in_texCoord;
out vec2 texCoord;

void main(){
  gl_Position = vec4(position, 1.0f);
  texCoord = in_texCoord;
}")

(define-class-shader post-effect-pass :fragment-shader
  "
in vec2 texCoord;")

(define-shader-pass copy-pass (post-effect-pass)
  ("previousPass"))

(define-class-shader copy-pass :fragment-shader
  "
in vec2 texCoord;
out vec4 color;
uniform sampler2D previousPass;

void main(){
  color = texture(previousPass, texCoord);
}")
