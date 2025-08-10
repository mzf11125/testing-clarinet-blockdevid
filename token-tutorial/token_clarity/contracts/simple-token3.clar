;; Simple Token - SIP-010 Standard Implementation
;; Workshop Version: Minimal but compliant

;; Implement SIP-010 fungible token trait
(impl-trait 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.sip-010-trait-ft-standard.sip-010-trait)
;; Define the token
(define-fungible-token workshop-token)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-token-owner (err u101))

;; Token metadata
(define-constant token-name "Token DeDanzi")
(define-constant token-symbol "DDZ")
(define-constant token-decimals u6)
(define-data-var token-uri (string-ascii 39) "https://workshop.blockdev.id/token.json")

;; SIP-010 required functions
(define-read-only (get-name)
  (ok token-name)
)

(define-read-only (get-symbol)
  (ok token-symbol)
)

(define-read-only (get-decimals)
  (ok token-decimals)
)

(define-read-only (get-balance (user principal))
  (ok (ft-get-balance workshop-token user))
)

(define-read-only (get-total-supply)
  (ok (ft-get-supply workshop-token))
)

(define-read-only (get-token-uri)
  (ok (some (var-get token-uri)))
)

;; SIP-010 transfer function
(define-public (transfer (amount uint) (from principal) (to principal) (memo (optional (buff 34))))
  (begin
    (asserts! (is-eq from tx-sender) err-not-token-owner)
    (ft-transfer? workshop-token amount from to)
  )
)

;; Mint function (owner only)
(define-public (mint (amount uint) (to principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ft-mint? workshop-token amount to)
  )
)

;; Add burn function
(define-public (burn (amount uint) (from principal))
  (begin
    (asserts! (is-eq from tx-sender) err-not-token-owner)
    (ft-burn? workshop-token amount from)
  )
)

;; Add admin functions
(define-public (set-token-uri (new-uri (string-utf8 256)))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    ;; (var-set token-uri new-uri)
    (ok true)
  )
)