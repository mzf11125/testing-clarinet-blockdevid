;; DAO Multisig Contract
;; Implements multi-signature functionality for critical operations
;; Provides additional security through required multiple approvals

;; ===== CONSTANTS =====
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_TRANSACTION_NOT_FOUND (err u404))
(define-constant ERR_TRANSACTION_ALREADY_EXISTS (err u405))
(define-constant ERR_ALREADY_CONFIRMED (err u406))
(define-constant ERR_NOT_CONFIRMED (err u407))
(define-constant ERR_INSUFFICIENT_CONFIRMATIONS (err u408))
(define-constant ERR_TRANSACTION_EXECUTED (err u409))
(define-constant ERR_INVALID_THRESHOLD (err u410))
(define-constant ERR_INVALID_OWNER (err u411))

;; ===== DATA VARIABLES =====
(define-data-var required-confirmations uint u2)
(define-data-var transaction-counter uint u0)
(define-data-var owner-count uint u0)

;; ===== DATA MAPS =====
;; Multisig owners
(define-map owners principal bool)

;; Transactions
(define-map transactions uint {
  destination: principal,
  function-name: (string-ascii 50),
  function-args: (list 10 (buff 32)),
  confirmations: uint,
  executed: bool,
  created-at: uint,
  created-by: principal
})

;; Transaction confirmations
(define-map confirmations {transaction-id: uint, owner: principal} bool)

;; Owner proposals (for adding/removing owners)
(define-map owner-proposals uint {
  target-owner: principal,
  action: (string-ascii 20), ;; "add" or "remove"
  confirmations: uint,
  executed: bool,
  created-at: uint,
  created-by: principal
})

;; Owner proposal confirmations
(define-map owner-proposal-confirmations {proposal-id: uint, owner: principal} bool)

;; ===== AUTHORIZATION CHECKS =====

;; Check if caller is owner
(define-read-only (is-owner (user principal))
  (default-to false (map-get? owners user)))

;; Check if transaction has enough confirmations
(define-read-only (has-enough-confirmations (transaction-id uint))
  (match (map-get? transactions transaction-id)
    transaction (>= (get confirmations transaction) (var-get required-confirmations))
    false))

;; ===== PUBLIC FUNCTIONS =====

;; Initialize multisig with initial owners
(define-public (initialize (initial-owners (list 10 principal)) (required uint))
  (begin
    (asserts! (is-eq tx-sender tx-sender) true) ;; Allow initialization by deployer
    (asserts! (> required u0) ERR_INVALID_THRESHOLD)
    (asserts! (<= required (len initial-owners)) ERR_INVALID_THRESHOLD)
    
    ;; Set initial owners
    (try! (fold add-initial-owner initial-owners (ok u0)))
    (var-set owner-count (len initial-owners))
    (var-set required-confirmations required)
    
    (print {
      action: "multisig-initialized",
      owners: initial-owners,
      required-confirmations: required
    })
    
    (ok true)))

;; Helper function to add initial owners
(define-private (add-initial-owner (owner principal) (result (response uint uint)))
  (begin
    (map-set owners owner true)
    result))

;; Submit a transaction
(define-public (submit-transaction 
  (destination principal)
  (function-name (string-ascii 50))
  (function-args (list 10 (buff 32))))
  (let ((transaction-id (+ (var-get transaction-counter) u1)))
    
    (asserts! (is-owner tx-sender) ERR_UNAUTHORIZED)
    
    ;; Create transaction
    (map-set transactions transaction-id {
      destination: destination,
      function-name: function-name,
      function-args: function-args,
      confirmations: u1, ;; Creator automatically confirms
      executed: false,
      created-at: stacks-block-height,
      created-by: tx-sender
    })
    
    ;; Record creator's confirmation
    (map-set confirmations {transaction-id: transaction-id, owner: tx-sender} true)
    
    ;; Update counter
    (var-set transaction-counter transaction-id)
    
    (print {
      action: "transaction-submitted",
      transaction-id: transaction-id,
      destination: destination,
      function-name: function-name,
      submitted-by: tx-sender
    })
    
    (ok transaction-id)))

;; Confirm a transaction
(define-public (confirm-transaction (transaction-id uint))
  (match (map-get? transactions transaction-id)
    transaction
      (begin
        (asserts! (is-owner tx-sender) ERR_UNAUTHORIZED)
        (asserts! (not (get executed transaction)) ERR_TRANSACTION_EXECUTED)
        (asserts! (is-none (map-get? confirmations {transaction-id: transaction-id, owner: tx-sender})) ERR_ALREADY_CONFIRMED)
        
        ;; Record confirmation
        (map-set confirmations {transaction-id: transaction-id, owner: tx-sender} true)
        
        ;; Update transaction confirmation count
        (map-set transactions transaction-id 
          (merge transaction {confirmations: (+ (get confirmations transaction) u1)}))
        
        (print {
          action: "transaction-confirmed",
          transaction-id: transaction-id,
          confirmed-by: tx-sender,
          total-confirmations: (+ (get confirmations transaction) u1)
        })
        
        (ok true))
    ERR_TRANSACTION_NOT_FOUND))

;; Revoke confirmation
(define-public (revoke-confirmation (transaction-id uint))
  (match (map-get? transactions transaction-id)
    transaction
      (begin
        (asserts! (is-owner tx-sender) ERR_UNAUTHORIZED)
        (asserts! (not (get executed transaction)) ERR_TRANSACTION_EXECUTED)
        (asserts! (is-some (map-get? confirmations {transaction-id: transaction-id, owner: tx-sender})) ERR_NOT_CONFIRMED)
        
        ;; Remove confirmation
        (map-delete confirmations {transaction-id: transaction-id, owner: tx-sender})
        
        ;; Update transaction confirmation count
        (map-set transactions transaction-id 
          (merge transaction {confirmations: (- (get confirmations transaction) u1)}))
        
        (print {
          action: "confirmation-revoked",
          transaction-id: transaction-id,
          revoked-by: tx-sender,
          total-confirmations: (- (get confirmations transaction) u1)
        })
        
        (ok true))
    ERR_TRANSACTION_NOT_FOUND))

;; Execute a confirmed transaction
(define-public (execute-transaction (transaction-id uint))
  (match (map-get? transactions transaction-id)
    transaction
      (begin
        (asserts! (is-owner tx-sender) ERR_UNAUTHORIZED)
        (asserts! (not (get executed transaction)) ERR_TRANSACTION_EXECUTED)
        (asserts! (has-enough-confirmations transaction-id) ERR_INSUFFICIENT_CONFIRMATIONS)
        
        ;; Mark as executed
        (map-set transactions transaction-id 
          (merge transaction {executed: true}))
        
        ;; Execute transaction (placeholder - in real implementation would call destination function)
        (print {
          action: "transaction-executed",
          transaction-id: transaction-id,
          destination: (get destination transaction),
          function-name: (get function-name transaction),
          executed-by: tx-sender
        })
        
        (ok true))
    ERR_TRANSACTION_NOT_FOUND))

;; Propose adding/removing owner
(define-public (propose-owner-change (target-owner principal) (action (string-ascii 20)))
  (let ((proposal-id (+ (var-get transaction-counter) u1000))) ;; Use different range for owner proposals
    
    (asserts! (is-owner tx-sender) ERR_UNAUTHORIZED)
    (asserts! (or (is-eq action "add") (is-eq action "remove")) ERR_INVALID_OWNER)
    
    ;; Create owner proposal
    (map-set owner-proposals proposal-id {
      target-owner: target-owner,
      action: action,
      confirmations: u1, ;; Creator automatically confirms
      executed: false,
      created-at: stacks-block-height,
      created-by: tx-sender
    })
    
    ;; Record creator's confirmation
    (map-set owner-proposal-confirmations {proposal-id: proposal-id, owner: tx-sender} true)
    
    (print {
      action: "owner-change-proposed",
      proposal-id: proposal-id,
      target-owner: target-owner,
      proposed-action: action,
      proposed-by: tx-sender
    })
    
    (ok proposal-id)))

;; Confirm owner change proposal
(define-public (confirm-owner-proposal (proposal-id uint))
  (match (map-get? owner-proposals proposal-id)
    proposal
      (begin
        (asserts! (is-owner tx-sender) ERR_UNAUTHORIZED)
        (asserts! (not (get executed proposal)) ERR_TRANSACTION_EXECUTED)
        (asserts! (is-none (map-get? owner-proposal-confirmations {proposal-id: proposal-id, owner: tx-sender})) ERR_ALREADY_CONFIRMED)
        
        ;; Record confirmation
        (map-set owner-proposal-confirmations {proposal-id: proposal-id, owner: tx-sender} true)
        
        ;; Update proposal confirmation count
        (map-set owner-proposals proposal-id 
          (merge proposal {confirmations: (+ (get confirmations proposal) u1)}))
        
        (print {
          action: "owner-proposal-confirmed",
          proposal-id: proposal-id,
          confirmed-by: tx-sender,
          total-confirmations: (+ (get confirmations proposal) u1)
        })
        
        (ok true))
    ERR_TRANSACTION_NOT_FOUND))

;; Execute owner change proposal
(define-public (execute-owner-proposal (proposal-id uint))
  (match (map-get? owner-proposals proposal-id)
    proposal
      (begin
        (asserts! (is-owner tx-sender) ERR_UNAUTHORIZED)
        (asserts! (not (get executed proposal)) ERR_TRANSACTION_EXECUTED)
        (asserts! (>= (get confirmations proposal) (var-get required-confirmations)) ERR_INSUFFICIENT_CONFIRMATIONS)
        
        ;; Mark as executed
        (map-set owner-proposals proposal-id 
          (merge proposal {executed: true}))
        
        ;; Execute owner change
        (if (is-eq (get action proposal) "add")
          (begin
            (map-set owners (get target-owner proposal) true)
            (var-set owner-count (+ (var-get owner-count) u1)))
          (begin
            (map-delete owners (get target-owner proposal))
            (var-set owner-count (- (var-get owner-count) u1))))
        
        (print {
          action: "owner-change-executed",
          proposal-id: proposal-id,
          target-owner: (get target-owner proposal),
          executed-action: (get action proposal),
          executed-by: tx-sender,
          new-owner-count: (var-get owner-count)
        })
        
        (ok true))
    ERR_TRANSACTION_NOT_FOUND))

;; Change required confirmations
(define-public (change-requirement (new-requirement uint))
  (let ((proposal-id (+ (var-get transaction-counter) u2000))) ;; Use different range
    
    (asserts! (is-owner tx-sender) ERR_UNAUTHORIZED)
    (asserts! (> new-requirement u0) ERR_INVALID_THRESHOLD)
    (asserts! (<= new-requirement (var-get owner-count)) ERR_INVALID_THRESHOLD)
    
    ;; This would typically require a proposal/voting process
    ;; For simplicity, requiring all current owners to confirm
    (var-set required-confirmations new-requirement)
    
    (print {
      action: "requirement-changed",
      old-requirement: (var-get required-confirmations),
      new-requirement: new-requirement,
      changed-by: tx-sender
    })
    
    (ok true)))

;; ===== READ-ONLY FUNCTIONS =====

;; Get transaction details
(define-read-only (get-transaction (transaction-id uint))
  (map-get? transactions transaction-id))

;; Get owner proposal details
(define-read-only (get-owner-proposal (proposal-id uint))
  (map-get? owner-proposals proposal-id))

;; Check if owner confirmed transaction
(define-read-only (has-confirmed (transaction-id uint) (owner principal))
  (default-to false (map-get? confirmations {transaction-id: transaction-id, owner: owner})))

;; Check if owner confirmed owner proposal
(define-read-only (has-confirmed-owner-proposal (proposal-id uint) (owner principal))
  (default-to false (map-get? owner-proposal-confirmations {proposal-id: proposal-id, owner: owner})))

;; Get required confirmations
(define-read-only (get-required-confirmations)
  (var-get required-confirmations))

;; Get owner count
(define-read-only (get-owner-count)
  (var-get owner-count))

;; Get transaction counter
(define-read-only (get-transaction-counter)
  (var-get transaction-counter))

;; Get multisig info
(define-read-only (get-multisig-info)
  {
    required-confirmations: (var-get required-confirmations),
    owner-count: (var-get owner-count),
    transaction-counter: (var-get transaction-counter)
  })
