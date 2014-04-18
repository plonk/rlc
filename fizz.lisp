(def = (a b)
  (.== a b))
(def + (&rest args)
  (.inject args 0 '+))
(def * (&rest args)
  (.inject args 1 '*))
(def - (a &rest args)
  (.inject args a '-))
(def % (a b)
  (.% a b))

(def fizz (i)
  (if (= i 20)
      nil
      (progn
        (setq p (list (= (% i 3) 0) (= (% i 5) 0)))
        (cond
          ((= p (list true true)) (puts "fizzbuzz"))
          ((= p (list true false)) (puts "fizz"))
          ((= p (list false true)) (puts "buzz"))
          ((= p (list false false)) (puts i)))
        (fizz (+ i 1)))))

(fizz 1)