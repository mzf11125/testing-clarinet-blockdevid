;; DAO Treasury Contract
;; Manages DAO funds and executes approved financial proposals
;; Part of the diamond pattern architecture

;; ===== CONSTANTS =====
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_INSUFFICIENT_FUNDS (err u402))
(define-constant ERR_INVALID_AMOUNT (err u403))
(define-constant ERR_PROPOSAL_NOT_EXECUTED (err u404))
(define-constant ERR_INVALID_RECIPIENT (err u405))

;; ===== DATA VARIABLES =====
(define-data-var governance-contract principal tx-sender)
(define-data-var treasury-balance uint u0)

;; ===== DATA MAPS =====
;; Track executed transfers
(define-map executed-transfers uint {
  recipient: principal,
  amount: uint,
  block-height: uint,
  proposal-id: uint
})

(define-data-var transfer-counter uint u0)

;; ===== AUTHORIZATION CHECKS =====
(define-private (is-dao-authorized)
  (is-eq contract-caller (var-get governance-contract)))

;; ===== PUBLIC FUNCTIONS =====

;; Initialize treasury with governance contract
(define-public (initialize (governance principal))
  (begin
    (asserts! (is-eq tx-sender (var-get governance-contract)) ERR_UNAUTHORIZED)
    (var-set governance-contract governance)
    (ok true)))

;; Deposit STX to treasury
(define-public (deposit (amount uint))
  (begin
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set treasury-balance (+ (var-get treasury-balance) amount))
    
    (print {
      action: "treasury-deposit",
      depositor: tx-sender,
      amount: amount,
      new-balance: (var-get treasury-balance)
    })
    
    (ok true)))

;; Execute STX transfer (only callable by governance)
(define-public (execute-transfer (recipient principal) (amount uint) (proposal-id uint))
  (let ((current-balance (var-get treasury-balance))
        (transfer-id (+ (var-get transfer-counter) u1)))
    
    (asserts! (is-dao-authorized) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= current-balance amount) ERR_INSUFFICIENT_FUNDS)
    
    ;; Execute transfer
    (try! (as-contract (stx-transfer? amount tx-sender recipient)))
    
    ;; Update balance
    (var-set treasury-balance (- current-balance amount))
    
    ;; Record transfer
    (map-set executed-transfers transfer-id {
      recipient: recipient,
      amount: amount,
      block-height: stacks-block-height,
      proposal-id: proposal-id
    })
    
    (map-set transfer-counter u0 transfer-id)
    
    (print {
      action: "treasury-transfer",
      transfer-id: transfer-id,
      recipient: recipient,
      amount: amount,
      proposal-id: proposal-id,
      new-balance: (- current-balance amount)
    })
    
    (ok transfer-id)))

;; Execute token transfer (for governance tokens or other FTs)
(define-public (execute-token-transfer 
  (token-contract <sip-010-trait>)
  (recipient principal) 
  (amount uint) 
  (proposal-id uint))
  (let ((transfer-id (+ (var-get transfer-counter) u1)))
    
    (asserts! (is-dao-authorized) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    
    ;; Execute token transfer
    (try! (as-contract (contract-call? token-contract transfer amount tx-sender recipient none)))
    
    ;; Record transfer
    (map-set executed-transfers transfer-id {
      recipient: recipient,
      amount: amount,
      block-height: stacks-block-height,
      proposal-id: proposal-id
    })
    
    (var-set transfer-counter transfer-id)
    
    (print {
      action: "treasury-token-transfer",
      transfer-id: transfer-id,
      token-contract: (contract-of token-contract),
      recipient: recipient,
      amount: amount,
      proposal-id: proposal-id
    })
    
    (ok transfer-id)))

;; Emergency pause (only governance)
(define-public (emergency-pause)
  (begin
    (asserts! (is-dao-authorized) ERR_UNAUTHORIZED)
    
    (print {
      action: "emergency-pause",
      block-height: stacks-block-height
    })
    
    (ok true)))

;; Update governance contract (only current governance)
(define-public (update-governance (new-governance principal))
  (begin
    (asserts! (is-dao-authorized) ERR_UNAUTHORIZED)
    (var-set governance-contract new-governance)
    
    (print {
      action: "governance-updated",
      old-governance: (var-get governance-contract),
      new-governance: new-governance
    })
    
    (ok true)))

;; ===== READ-ONLY FUNCTIONS =====

;; Get treasury balance
(define-read-only (get-balance)
  (var-get treasury-balance))

;; Get governance contract
(define-read-only (get-governance-contract)
  (var-get governance-contract))

;; Get transfer details
(define-read-only (get-transfer (transfer-id uint))
  (map-get? executed-transfers transfer-id))

;; Get transfer counter
(define-read-only (get-transfer-counter)
  (var-get transfer-counter))

;; Check if contract has sufficient STX balance
(define-read-only (has-sufficient-balance (amount uint))
  (>= (var-get treasury-balance) amount))

;; Get contract STX balance (actual on-chain balance)
(define-read-only (get-contract-balance)
  (stx-get-balance (as-contract tx-sender)))

;; Trait definition for SIP-010 tokens
(define-trait sip-010-trait
  (
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))
    (get-name () (response (string-ascii 32) uint))
    (get-symbol () (response (string-ascii 32) uint))
    (get-decimals () (response uint uint))
    (get-balance (principal) (response uint uint))
    (get-total-supply () (response uint uint))
    (get-token-uri () (response (optional (string-utf8 256)) uint))
  ))
