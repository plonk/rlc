(def fizz (i)
  (if (== i 20)
      nil
      (progn
        (setq p (.list (== (% i 3) 0) (== (% i 5) 0)))
        (if (== p (.list true true))
            (.puts "fizzbuzz")
            (if (== p (.list true false))
                (.puts "fizz")
                (if (== p (.list false true))
                    (.puts "buzz")
                    (if (== p (.list false false))
                        (.puts i)))))
        (.fizz (+ i 1)))))

(.fizz 1)