 #lang racket
(require srfi/13)
(require "helper_functions.rkt" "make-reader.rkt" "sort.rkt" "shunting-yard.rkt" "get-condition.rkt")

;SELECT table1.St_Id,table1.Sname,table2.Name FROM table1.csv INNER JOIN table2.csv ON table1.St_Id = table2.ID
;SELECT * FROM table1.csv FULL OUTER JOIN table2.csv ON table1.St_Id = table2.ID
;SELECT table1.St_Id,table2.ID,table1.Sname,table2.Name,table1.St_Id FROM table1.csv FULL OUTER JOIN table2.csv ON table1.St_Id = table2.ID
;SELECT table1.St_Id,table1.Sname FROM table1.csv INNER JOIN table2.csv ON table1.St_Id = table2.ID UNION SELECT St_Id,Sname FROM table1.csv WHERE St_Id>=3
;AND St_Id<=5 UNION SELECT St_Id,Sname FROM table1.csv WHERE St_Id=1 UNION SELECT St_Id,Sname FROM table1.csv ORDER BY St_Id DESC

(define (union-select-where port command index)
  (define before-part (string-split(substring command 0 (+ (string-contains command " WHERE") 6))))
   (when (not (string-ci=? (third before-part) "FROM"))
    (error 'помилка "невірно введено команду SELECT. Будь ласка, спробуйте ще"))
  (when (not (string-ci=? (fifth before-part) "WHERE"))
    (error 'помилка "невірно введено умову WHERE. Будь ласка, спробуйте ще"))
  (define temp (substring command (+ (string-contains command "WHERE ") 6)))
  (define part
    (if (string-contains? temp "ORDER BY")
        (if (string-contains? (substring temp 0 (string-contains temp " ORDER BY")) "\"")
        (string-join (without-spaces (string-split (substring temp 0 (string-contains  temp " ORDER BY")) "\"")) "")
        (substring temp 0 (string-contains temp " ORDER BY")))
        (if (string-contains? temp "\"")
        (string-join (without-spaces (string-split temp "\"")) "")
        temp)))  
  (define read-row (make-reader port))
  (define head (append (read-row) (list "\n")))
  (if (= index 0)
      (append (list head) (operation (second before-part) read-row head (shunt part)))
      (operation (second before-part) read-row head (shunt part)))
  
)

(define (operation col read-row head condition)
  (cond
    [(string-ci=? col "*")
      (define rows (for/list ([row (in-producer read-row '())]
                             #:when (car (calculate-RPN condition head row)))
                     (append row (list "\n"))))
     rows]
    [(not (string-ci=? col "*"))
     (define column-name (string-split col ","))
     (define rows (for/list ([row (in-producer read-row '())]
                             #:when (car (calculate-RPN condition head row)))
                 (define column (multiple-list-ref row (multiple-index head column-name)))
                 (append column (list "\n"))))
     rows]
    [else (error 'помилка "невірно введено умову WHERE. Будь ласка, спробуйте ще")]))

(define (union-simple-select port command index)
  (when (not (string-ci=? (third command) "FROM"))
    (error 'помилка "невірно введено команду SELECT. Будь ласка, спробуйте ще"))
  (define read-row (make-reader port))
  (define head (read-row))
  (cond
    [(string-ci=? (second command) "*")
     (define rows (for/list ([row (in-producer read-row '())])
                 row))
     (if(= index 0)
        (append (list head) rows)
        rows)]
    [(not (string-ci=? (second command) "*"))
     (define column-name (string-split (second command) ","))
  (define contains-column (aremembers? column-name head))
  (when (eq? contains-column #f)
    (error 'помилка "невірно введено назви колонок. Будь ласка, спробуйте ще")) 
  (define rows (for/list ([row (in-producer read-row '())])
                 (define column (multiple-list-ref row (multiple-index head column-name)))
                 (append column (list "\n"))))
   (if(= index 0)
        (append (list (append (multiple-list-ref head (multiple-index head column-name)) (list "\n"))) rows)
        rows)]))

;------------------------------------------------------------------INNER_JOIN_command-----------------------------------------------------------------------
(define (inner-join port1 port2 command)
  (define syntax (and (string-ci=? (first command) "SELECT")
                      (string-ci=? (third command) "FROM")
                      (string-ci=? (fifth command) "INNER")
                      (string-ci=? (sixth command) "JOIN")
                      (string-ci=? (eighth command) "ON")
                      (string-ci=? (tenth command) "=")))
  (when (not syntax)
    (error 'помилка "невірно введено команду INNER JOIN. Будь ласка, спробуйте ще"))
  (define read-row1 (make-reader port1))
  (define read-row2 (make-reader port2))
  (define head1 (read-row1))
  (define head2 (read-row2))
  (define table1-info(string-split (ninth command) "."))
  (define table2-info(string-split (list-ref command 10) "."))
  (when (and (not (= (length table1-info) 2))
             (not (= (length table2-info) 2))
             (not (string-ci=? (first table1-info) (substring (fourth command) 0 (- (string-length (fourth command)) 4))))
             (not (string-ci=? (first table2-info) (substring (seventh command) 0 (- (string-length (seventh command)) 4)))))
    (error 'помилка "невірно введено команду INNER JOIN. Будь ласка, спробуйте ще"))
  (cond
    [(string-ci=? (second command) "*")
     (when (and (not (eq? head1 head2))
                (not (ismember? (second table1-info) head1))
                (not (ismember? (second table2-info) head2)))
       (error 'помилка "таблиці несумісні. Будь ласка, спробуйте ще"))
     (define rows1 (for/list ([row (in-producer read-row1 '())])
                 row))
     (define rows2 (for/list ([row (in-producer read-row2 '())])
                 row))
     (define table2-col (for/list ([row rows2])
                 (append (list (list-ref row (index-of head2 (second table2-info)))) (list ))))
     (define result (for/list ([row rows1]
                               #:when (ismember? (list (list-ref row (index-of head1 (second table1-info)))) table2-col))
                 (append row (get-row rows2 (list-ref row (index-of head1 (second table1-info)))) (list "\n"))))
     (define (->string row) (string-join row "\t"))
  (string-append* (map ->string (cons (remove-duplicates (append head1 head2 (list "\n"))) result)))]
    [(not (string-ci=? (second command) "*"))
     (define columns (string-split (second command) ","))
     (when (not (check-columns columns (first table1-info) (first table2-info) head1 head2))
       (error 'помилка "невірно вказані колонки. Будь ласка, спробуйте ще"))
     (define rows1 (for/list ([row (in-producer read-row1 '())])
                 (append row (list "\n"))))
     (define rows2 (for/list ([row (in-producer read-row2 '())])
                 (append row (list "\n"))))
     (define table2-col (for/list ([row rows2])
                 (append (list (list-ref row (index-of head2 (second table2-info)))) (list ))))
     (define result (for/list ([row rows1]
                               #:when (ismember? (list (list-ref row (index-of head1 (second table1-info)))) table2-col))
                 (define column (reverse (multiple-tabs-list-ref row (get-row rows2 (list-ref row (index-of head1 (second table1-info)))) (multiple-tabs-index (substring (fourth command) 0 (- (string-length (fourth command)) 4))
                                                                                         (substring (seventh command) 0 (- (string-length (seventh command)) 4))
                                                                                         head1 head2 columns))))
                 (append column (list "\n"))))
     (define (->string row) (string-join row "\t"))
  (string-append* (map ->string (cons (append (multiple-tabs-list-ref head1 head2 (reverse (multiple-tabs-index (substring (fourth command) 0 (- (string-length (fourth command)) 4))
                                                                                         (substring (seventh command) 0 (- (string-length (seventh command)) 4))
                                                                                         head1 head2 columns))) (list "\n")) result)))
     ])
)

(define (union-inner-join port1 port2 command index)
  (define syntax (and (string-ci=? (first command) "SELECT")
                      (string-ci=? (third command) "FROM")
                      (string-ci=? (fifth command) "INNER")
                      (string-ci=? (sixth command) "JOIN")
                      (string-ci=? (eighth command) "ON")
                      (string-ci=? (tenth command) "=")))
  (when (not syntax)
    (error 'помилка "невірно введено команду INNER JOIN. Будь ласка, спробуйте ще"))
  (define read-row1 (make-reader port1))
  (define read-row2 (make-reader port2))
  (define head1 (read-row1))
  (define head2 (read-row2))
  (define table1-info(string-split (ninth command) "."))
  (define table2-info(string-split (list-ref command 10) "."))
  (when (and (not (= (length table1-info) 2))
             (not (= (length table2-info) 2))
             (not (string-ci=? (first table1-info) (substring (fourth command) 0 (- (string-length (fourth command)) 4))))
             (not (string-ci=? (first table2-info) (substring (seventh command) 0 (- (string-length (seventh command)) 4)))))
    (error 'помилка "невірно введено команду INNER JOIN. Будь ласка, спробуйте ще"))
  (cond
    [(string-ci=? (second command) "*")
     (when (and (not (eq? head1 head2))
                (not (ismember? (second table1-info) head1))
                (not (ismember? (second table2-info) head2)))
       (error 'помилка "таблиці несумісні. Будь ласка, спробуйте ще"))
     (define rows1 (for/list ([row (in-producer read-row1 '())])
                 row))
     (define rows2 (for/list ([row (in-producer read-row2 '())])
                 row))
     (define table2-col (for/list ([row rows2])
                 (append (list (list-ref row (index-of head2 (second table2-info)))) (list ))))
     (define result (for/list ([row rows1]
                               #:when (ismember? (list (list-ref row (index-of head1 (second table1-info)))) table2-col))
                 (append row (get-row rows2 (list-ref row (index-of head1 (second table1-info)))) (list "\n"))))
     (if (= index 0)
         (append (list head1) result)
         result)]
    [(not (string-ci=? (second command) "*"))
     (define columns (string-split (second command) ","))
     (when (not (check-columns columns (first table1-info) (first table2-info) head1 head2))
       (error 'помилка "невірно вказані колонки. Будь ласка, спробуйте ще"))
     (define rows1 (for/list ([row (in-producer read-row1 '())])
                 (append row (list "\n"))))
     (define rows2 (for/list ([row (in-producer read-row2 '())])
                 (append row (list "\n"))))
     (define table2-col (for/list ([row rows2])
                 (append (list (list-ref row (index-of head2 (second table2-info)))) (list ))))
     (define result (for/list ([row rows1]
                               #:when (ismember? (list (list-ref row (index-of head1 (second table1-info)))) table2-col))
                 (define column (reverse (multiple-tabs-list-ref row (get-row rows2 (list-ref row (index-of head1 (second table1-info)))) (multiple-tabs-index (substring (fourth command) 0 (- (string-length (fourth command)) 4))
                                                                                         (substring (seventh command) 0 (- (string-length (seventh command)) 4))
                                                                                         head1 head2 columns))))
                 (append column (list "\n"))))
     (if (= index 0)
         (append (list (append (multiple-tabs-list-ref head1 head2 (reverse (multiple-tabs-index (substring (fourth command) 0 (- (string-length (fourth command)) 4))
                                                                                         (substring (seventh command) 0 (- (string-length (seventh command)) 4))
                                                                                         head1 head2 columns))) (list "\n"))) result)
         result)
    ]))
;------------------------------------------------------------------INNER_JOIN_command-----------------------------------------------------------------------

;------------------------------------------------------------------FULL_OUTER_JOIN_command-----------------------------------------------------------------------
(define (full-outer-join port1 port2 command)
  (define syntax (and (string-ci=? (first command) "SELECT")
                      (string-ci=? (third command) "FROM")
                      (string-ci=? (fifth command) "FULL")
                      (string-ci=? (sixth command) "OUTER")
                      (string-ci=? (seventh command) "JOIN")
                      (string-ci=? (ninth command) "ON")
                      (string-ci=? (list-ref command 10) "=")))
  (when (not syntax)
    (error 'помилка "невірно введено команду FULL OUTER JOIN. Будь ласка, спробуйте ще"))
  (define read-row1 (make-reader port1))
  (define read-row2 (make-reader port2))
  (define head1 (read-row1))
  (define head2 (read-row2))
  (define table1-info(string-split (tenth command) "."))
  (define table2-info(string-split (list-ref command 11) "."))
  (when (and (not (= (length table1-info) 2))
             (not (= (length table2-info) 2))
             (not (string-ci=? (first table1-info) (substring (fourth command) 0 (- (string-length (fourth command)) 4))))
             (not (string-ci=? (first table2-info) (substring (seventh command) 0 (- (string-length (seventh command)) 4)))))
    (error 'помилка "невірно введено команду FULL OUTER JOIN. Будь ласка, спробуйте ще"))
  (cond
    [(string-ci=? (second command) "*")
     (when (and (not (eq? head1 head2))
                (not (ismember? (second table1-info) head1))
                (not (ismember? (second table2-info) head2)))
       (error 'помилка "таблиці несумісні. Будь ласка, спробуйте ще"))
     (define rows1 (for/list ([row (in-producer read-row1 '())])
                 row))
     (define rows2 (for/list ([row (in-producer read-row2 '())])
                 row))
     (define table1-col (for/list ([row rows1])
                 (list-ref row (index-of head1 (second table1-info)))))
     (define table2-col (for/list ([row rows2])
                 (list-ref row (index-of head2 (second table2-info)))))
     (define join (remove-duplicates (append table1-col table2-col)))
     (define result (for/list ([value join])
                 (cond
                   [(and (not (empty? (get-row rows1 value))) (not (empty? (get-row rows2 value)))) (append (get-row rows1 value) (get-row rows2 value) (list "\n"))]
                   [(empty? (get-row rows1 value)) (append (fill-row (length (car rows1))) (get-row rows2 value) (list "\n"))]
                   [(empty? (get-row rows2 value)) (append (get-row rows1 value) (fill-row (length (car rows2))) (list "\n"))])))
     (define (->string row) (string-join row "\t"))
  (string-append* (map ->string (cons (append head1 head2 (list "\n")) result)))]
    [(not (string-ci=? (second command) "*"))
     (define columns (string-split (second command) ","))
     (define column-name (check-presence head1 head2 (first table1-info) (first table2-info) columns))
     (define rows1 (for/list ([row (in-producer read-row1 '())])
                 row))
     (define rows2 (for/list ([row (in-producer read-row2 '())])
                 row))
      (define table1-col (for/list ([row rows1])
                 (list-ref row (index-of head1 (second table1-info)))))
     (define table2-col (for/list ([row rows2])
                 (list-ref row (index-of head2 (second table2-info)))))
     (define join (remove-duplicates (append table1-col table2-col)))
     (define full-data (for/list ([value join])
                 (cond
                   [(and (not (empty? (get-row rows1 value))) (not (empty? (get-row rows2 value)))) (append (get-row rows1 value) (get-row rows2 value) (list "\n"))]
                   [(empty? (get-row rows1 value)) (append (fill-row (length (car rows1))) (get-row rows2 value) (list "\n"))]
                   [(empty? (get-row rows2 value)) (append (get-row rows1 value) (fill-row (length (car rows2))) (list "\n"))])))
     (define result (for/list ([row full-data])
                      (define column (multiple-list-ref row (multiple-index (append head1 head2) column-name)))
                      (append column (list "\n"))))
     (define (->string row) (string-join row "\t"))
  (string-append* (map ->string (cons (append (multiple-list-ref (append head1 head2) (multiple-index (append head1 head2) column-name)) (list "\n")) result)))
     ])
)
;------------------------------------------------------------------FULL_OUTER_JOIN_command-----------------------------------------------------------------------

;-------------------------------------------------------------------union_handler--------------------------------------------------------------------------------
(define (union-handler option)
  (define commands (string-split option " UNION "))
  (define (get-cols lst)
    (cond
      [(empty? lst) (list)]
      [(string-contains? (second (string-split (car lst) " ")) ".")
       (append (map (lambda (x) (substring x (+ (string-contains x ".") 1))) (string-split (second (string-split (car lst) " ")) ",")) (get-cols (cdr lst)))]
      [#t (append (string-split (second (string-split (car lst) " ")) ",") (get-cols (cdr lst)))]))
  (define cols (remove-duplicates (get-cols commands)))
  (when (> (length cols) (length (string-split (second (string-split (car commands) " ")) ",")))
    (error 'помилка "колонки не співпадають"))
  (when (eq? cols '("*"))
    (union-check commands))
  (define last (- (length commands) 1))
  (define (execute commands acc)
    (cond
    [(empty? commands) (list )]
    [(and (string-ci=? (substring option 0 6) "SELECT") (string-contains? (car commands) "WHERE")) (append (union-select-where (open-input-string
                                                                                                         (file->string
                                                                                                          (fourth (string-split (car commands) " "))))
                                                                                                                       (car commands) acc)
                                                                                                   (execute (cdr commands) (+ acc 1)))]
    [(and (string-ci=? (substring option 0 6) "SELECT") (string-contains? (car commands) "INNER JOIN")) (append (union-inner-join (open-input-string
                                                                                                         (file->string
                                                                                                          (fourth (string-split (car commands) " "))))
                                                                                                           (open-input-string
                                                                                                         (file->string
                                                                                                          (seventh (string-split (car commands) " "))))
                                                                                                           (string-split (car commands) " ") acc)
                                                                                                   (execute (cdr commands) (+ acc 1)))]
    [(string-ci=? (substring option 0 6) "SELECT") (append (union-simple-select (open-input-string (file->string (fourth (string-split (car commands) " "))))
                                                                                            (string-split (car commands) " ") acc)(execute (cdr commands) (+ acc 1)))]
    [else (writeln "Невірно введено команду. Будь ласка, спробуйте ще.")])
    )
  (define (->string row) (string-join row "\t"))
  (cond
    [(and (string-contains? (list-ref commands last) "ORDER BY") (string-ci=? (list-ref (string-split (list-ref commands last) " ")
                                                                                        (- (length (string-split (list-ref commands last) " ")) 4)) "ORDER")
                                                                  (string-ci=? (list-ref (string-split (list-ref commands last) " ")
                                                                                         (- (length (string-split (list-ref commands last) " ")) 3)) "BY"))
     (define head (car (execute commands 0)))
     (define sort-by (if(string-ci=? (list-ref (string-split (list-ref commands last) " ") (- (length (string-split (list-ref commands last) " ")) 1)) "DESC")
     (list-ref (string-split (list-ref commands last) " ") (- (length (string-split (list-ref commands last) " ")) 2))
     (list-ref (string-split (list-ref commands last) " ") (- (length (string-split (list-ref commands last) " ")) 1))))
     (define col-data (for/list ([row (cdr (execute commands 0))])
                 (define column (multiple-list-ref row (multiple-index head (list sort-by))))
                  (string-join column)))
     (if (string-ci=? (list-ref (string-split (list-ref commands last) " ") (- (length (string-split (list-ref commands last) " ")) 1)) "DESC")
         (display (string-append* (map ->string (append (list (car (execute commands 0))) (reverse (sort (cdr (execute commands 0)) col-data))))))
         (display (string-append* (map ->string (append (list (car (execute commands 0))) (sort (cdr (execute commands 0)) col-data))))))
      ]
    [#t (display (string-append* (map ->string (execute commands 0))))]
      )
  )
;-------------------------------------------------------------------union_handler--------------------------------------------------------------------------------

;--------------------------------------------------------initialazer-----------------------------------------------------------------------
(define (cli)
  (writeln "Ласкаво просимо до lab 6 cli!Будь ласка, введіть команду")
  (define option (read-line (current-input-port))) 
(when (<= (string-length option) 6) (error 'помилка "невірно введено команду. Будь ласка, спробуйте ще"))
  (cond
    [(and (string-ci=? (substring option 0 6) "SELECT") (string-contains? option "UNION"))
    (union-handler option)]
    [(and (string-ci=? (substring option 0 6) "SELECT") (string-contains? option "INNER JOIN")) (display (inner-join (open-input-string
                                                                                                         (file->string (fourth (string-split option))))
                                                                                                         (open-input-string
                                                                                                         (file->string (seventh (string-split option))))
                                                                                                         (string-split option)))]
    [(and (string-ci=? (substring option 0 6) "SELECT") (string-contains? option "FULL OUTER JOIN")) (display (full-outer-join (open-input-string
                                                                                                         (file->string (fourth (string-split option))))
                                                                                                          (open-input-string
                                                                                                         (file->string (eighth (string-split option))))                     
                                                                                                                               (string-split option)))]
    [else (writeln "Невірно введено команду. Будь ласка, спробуйте ще.")])
 )

(cli )

