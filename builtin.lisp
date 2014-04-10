(def list (&rest items)
  items)

(set_macro_character LR
                     "'"
                     (lambda (input char)
                       (setq res (read LR input))
                       (.list (.list (quote quote) (first res)) (last res))))

(set_dispatch_macro_character LR "#" "'"
                              (lambda (input char_a char_b)
                                (setq res (read LR input))
                                (.list (.list 'function (first res)) (last res))))

(set_dispatch_macro_character LR "#" (chr 92) ; バックスラッシュ
                              (lambda (input char_a char_b)
                                (.list (slice input 0)
                                       (slice input 1 (- (length input) 1)))))

(set_dispatch_macro_character LR #\# #\"
                              (lambda (input char_a char_b)
                                (setq res (read LR input))
                                (.list (.list 'private_function (first res)) (last res))))

(defmacro function (name) (.list 'to_proc (.list 'quote name)))

(defmacro let (varlist &rest body)
  (.list 'apply (+ '(.list) (map varlist & #'last))
         '& (+ (.list 'lambda (.list (map varlist & #'first))) body)))

(let ((counter 0))
  (.define_method 'gensym &(lambda ()
                             (to_sym (% "g_%05x" (setq counter (+ counter 1)))))))

(defmacro unless (condition &rest body)
 (.list 'if condition
    'nil
    (+ (.list 'progn) body)))

(defmacro when (condition &rest body)
 (.list 'if condition
          (+ (.list 'progn) body)
          'nil))

(defmacro rotatef (a b)
  (setq tmp (.gensym))
  (.list 'let (.list (.list tmp a))
         (.list 'setq a b)
         (.list 'setq b tmp)
         'nil))

(defmacro incf (place)
  (.list 'setq place (.list '+ place 1)))

(defmacro cond (&rest cases)
  (if (empty? cases)
      'nil
      (.list 'if (first (first cases))
             (+ (.list 'progn)  (rest (first cases)))
             (+ '(cond) (rest cases)))))