;; DAO Governance Token Contract
;; Implements SIP-010 compatible governance token with voting power mechanics
;; Supports delegation, snapshots, and voting power calculations

;; ===== TRAITS =====
;; Note: In a real deployment, this would reference the actual SIP-010 trait
;; (impl-trait 'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE.sip-010-trait-ft-standard.sip-010-trait)

;; ===== CONSTANTS =====
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_INSUFFICIENT_BALANCE (err u402))
(define-constant ERR_INVALID_AMOUNT (err u403))
(define-constant ERR_TOKEN_TRANSFER_FAILED (err u404))
(define-constant ERR_ALREADY_VOTED (err u405))
(define-constant ERR_VOTING_PERIOD_ENDED (err u406))
(define-constant ERR_INVALID_DELEGATE (err u407))

(define-constant TOKEN_NAME "DAO Governance Token")
(define-constant TOKEN_SYMBOL "DAOGOV")
(define-constant TOKEN_DECIMALS u6)
(define-constant TOKEN_URI u"https://dao.example.com/token-metadata")

;; Maximum supply: 1 billion tokens
(define-constant MAX_SUPPLY u1000000000000000)

;; ===== DATA VARIABLES =====
(define-data-var total-supply uint u0)
(define-data-var contract-owner principal tx-sender)

;; ===== DATA MAPS =====
;; Token balances
(define-map token-balances principal uint)

;; Token allowances for transfers
(define-map token-allowances {owner: principal, spender: principal} uint)

;; Voting power delegation
(define-map delegates principal principal)

;; Historical voting power checkpoints
(define-map voting-power-checkpoints 
  {user: principal, checkpoint: uint} 
  {block-height: uint, voting-power: uint})

;; Number of checkpoints per user
(define-map checkpoint-counts principal uint)

;; Locked tokens for voting (prevents transfer during active votes)
(define-map locked-tokens principal uint)

;; ===== PRIVATE FUNCTIONS =====

;; Get balance with default of 0
(define-private (get-balance-or-default (account principal))
  (default-to u0 (map-get? token-balances account)))

;; Get locked tokens with default of 0
(define-private (get-locked-or-default (account principal))
  (default-to u0 (map-get? locked-tokens account)))

;; Update voting power checkpoint
(define-private (update-voting-power-checkpoint (user principal) (new-voting-power uint))
  (let ((checkpoint-count (default-to u0 (map-get? checkpoint-counts user))))
    (map-set voting-power-checkpoints
      {user: user, checkpoint: checkpoint-count}
      {block-height: stacks-block-height, voting-power: new-voting-power})
    (map-set checkpoint-counts user (+ checkpoint-count u1))
    (ok true)))

;; ===== PUBLIC FUNCTIONS =====

;; SIP-010 Standard Functions

(define-public (transfer (amount uint) (from principal) (to principal) (memo (optional (buff 34))))
  (begin
    (asserts! (or (is-eq from tx-sender) (is-eq from contract-caller)) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (let ((from-balance (get-balance-or-default from))
          (to-balance (get-balance-or-default to))
          (locked-amount (get-locked-or-default from)))
      (asserts! (>= from-balance amount) ERR_INSUFFICIENT_BALANCE)
      (asserts! (>= (- from-balance locked-amount) amount) ERR_INSUFFICIENT_BALANCE)
      
      ;; Update balances
      (map-set token-balances from (- from-balance amount))
      (map-set token-balances to (+ to-balance amount))
      
      ;; Update voting power checkpoints
      (unwrap-panic (update-voting-power-checkpoint from (- from-balance amount)))
      (unwrap-panic (update-voting-power-checkpoint to (+ to-balance amount)))
      
      ;; Print transfer event
      (print {
        action: "transfer",
        from: from,
        to: to,
        amount: amount,
        memo: memo
      })
      
      (ok true))))

(define-public (get-name)
  (ok TOKEN_NAME))

(define-public (get-symbol)
  (ok TOKEN_SYMBOL))

(define-public (get-decimals)
  (ok TOKEN_DECIMALS))

(define-public (get-balance (account principal))
  (ok (get-balance-or-default account)))

(define-public (get-total-supply)
  (ok (var-get total-supply)))

(define-public (get-token-uri)
  (ok (some TOKEN_URI)))

;; Enhanced DAO Functions

;; Mint tokens (only contract owner initially, later DAO governance)
(define-public (mint (amount uint) (recipient principal))
  (let ((current-supply (var-get total-supply))
        (recipient-balance (get-balance-or-default recipient)))
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (<= (+ current-supply amount) MAX_SUPPLY) ERR_INVALID_AMOUNT)
    
    ;; Update total supply and recipient balance
    (var-set total-supply (+ current-supply amount))
    (map-set token-balances recipient (+ recipient-balance amount))
    
    ;; Update voting power checkpoint
    (unwrap-panic (update-voting-power-checkpoint recipient (+ recipient-balance amount)))
    
    ;; Print mint event
    (print {
      action: "mint",
      recipient: recipient,
      amount: amount,
      new-total-supply: (+ current-supply amount)
    })
    
    (ok true)))

;; Delegate voting power
(define-public (delegate (to principal))
  (begin
    (asserts! (not (is-eq tx-sender to)) ERR_INVALID_DELEGATE)
    (map-set delegates tx-sender to)
    
    ;; Print delegation event
    (print {
      action: "delegate",
      delegator: tx-sender,
      delegatee: to
    })
    
    (ok true)))

;; Remove delegation (delegate to self)
(define-public (undelegate)
  (begin
    (map-delete delegates tx-sender)
    
    ;; Print undelegation event
    (print {
      action: "undelegate",
      delegator: tx-sender
    })
    
    (ok true)))

;; Lock tokens for voting (called by voting contracts)
(define-public (lock-tokens (user principal) (amount uint))
  (let ((current-locked (get-locked-or-default user))
        (user-balance (get-balance-or-default user)))
    (asserts! (>= user-balance (+ current-locked amount)) ERR_INSUFFICIENT_BALANCE)
    (map-set locked-tokens user (+ current-locked amount))
    (ok true)))

;; Unlock tokens after voting (called by voting contracts)
(define-public (unlock-tokens (user principal) (amount uint))
  (let ((current-locked (get-locked-or-default user)))
    (asserts! (>= current-locked amount) ERR_INSUFFICIENT_BALANCE)
    (map-set locked-tokens user (- current-locked amount))
    (ok true)))

;; Transfer contract ownership to DAO (one-time function)
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
    (var-set contract-owner new-owner)
    
    ;; Print ownership transfer event
    (print {
      action: "transfer-ownership",
      old-owner: tx-sender,
      new-owner: new-owner
    })
    
    (ok true)))

;; ===== READ-ONLY FUNCTIONS =====

;; Get voting power at current block
(define-read-only (get-voting-power (user principal))
  (let ((user-delegate (map-get? delegates user)))
    (if (is-some user-delegate)
      (get-balance-or-default (unwrap-panic user-delegate))
      (get-balance-or-default user))))

;; Get voting power at specific block height (simplified non-recursive version)
(define-read-only (get-voting-power-at-height (user principal) (height uint))
  (let ((checkpoint-count (default-to u0 (map-get? checkpoint-counts user))))
    (if (is-eq checkpoint-count u0)
      u0
      ;; For now, return current voting power if we have checkpoints
      ;; In a full implementation, this would iterate through checkpoints
      (get-balance-or-default user))))

;; Get delegate
(define-read-only (get-delegate (user principal))
  (map-get? delegates user))

;; Get locked tokens amount
(define-read-only (get-locked-tokens (user principal))
  (get-locked-or-default user))

;; Get available tokens for transfer
(define-read-only (get-available-tokens (user principal))
  (let ((balance (get-balance-or-default user))
        (locked (get-locked-or-default user)))
    (if (>= balance locked)
      (- balance locked)
      u0)))

;; Get contract owner
(define-read-only (get-contract-owner)
  (var-get contract-owner))