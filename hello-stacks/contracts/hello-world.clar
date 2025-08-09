;; hello-world.clar
;; Simple Hello World contract

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-already-exists (err u101))

;; Data variables
(define-data-var greeting (string-ascii 50) "Hello, World!")

;; Data maps
(define-map user-greetings principal (string-ascii 100))

;; Read-only functions
(define-read-only (get-greeting)
  (var-get greeting)
)

(define-read-only (get-user-greeting (user principal))
  (default-to "No greeting set" (map-get? user-greetings user))
)

;; Public functions
(define-public (set-greeting (new-greeting (string-ascii 50)))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set greeting new-greeting)
    (ok new-greeting)
  )
)

(define-public (set-user-greeting (user-greeting (string-ascii 100)))
  (begin
    (map-set user-greetings tx-sender user-greeting)
    (ok user-greeting)
  )
)

;; Get contract info
(define-read-only (get-contract-info)
  (ok {
    owner: contract-owner,
    greeting: (var-get greeting),
    your-greeting: (get-user-greeting tx-sender)
  })
)