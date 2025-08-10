;; DAO Timelock Contract
;; Implements timelock functionality for critical operations
;; Provides additional security layer for governance actions

;; ===== CONSTANTS =====
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_OPERATION_NOT_FOUND (err u404))
(define-constant ERR_OPERATION_ALREADY_EXISTS (err u405))
(define-constant ERR_OPERATION_NOT_READY (err u406))
(define-constant ERR_OPERATION_EXPIRED (err u407))
(define-constant ERR_INVALID_DELAY (err u408))
(define-constant ERR_EXECUTION_FAILED (err u409))

;; Timelock delays (in blocks)
(define-constant MIN_DELAY u144)  ;; ~1 day minimum
(define-constant MAX_DELAY u1008) ;; ~7 days maximum
(define-constant GRACE_PERIOD u2016) ;; ~14 days grace period

;; ===== DATA VARIABLES =====
(define-data-var admin principal tx-sender)
(define-data-var pending-admin (optional principal) none)
(define-data-var delay uint MIN_DELAY)
(define-data-var operation-counter uint u0)

;; ===== DATA MAPS =====
;; Queued operations
(define-map queued-operations (buff 32) {
  target: principal,
  function-name: (string-ascii 50),
  function-args: (list 10 (buff 32)),
  eta: uint,
  executed: bool,
  cancelled: bool,
  queued-at: uint,
  queued-by: principal
})

;; Operation hashes for tracking
(define-map operation-hashes uint (buff 32))

;; ===== PRIVATE FUNCTIONS =====

;; Generate operation hash
(define-private (generate-operation-hash 
  (target principal)
  (function-name (string-ascii 50))
  (function-args (list 10 (buff 32)))
  (eta uint))
  (hash160 (concat 
    (concat (unwrap-panic (to-consensus-buff? target)) (unwrap-panic (to-consensus-buff? function-name)))
    (concat (unwrap-panic (to-consensus-buff? function-args)) (unwrap-panic (to-consensus-buff? eta))))))

;; Check if caller is admin
(define-private (is-admin (caller principal))
  (is-eq caller (var-get admin)))

;; ===== PUBLIC FUNCTIONS =====

;; Initialize timelock
(define-public (initialize (initial-admin principal) (initial-delay uint))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) ERR_UNAUTHORIZED)
    (asserts! (and (>= initial-delay MIN_DELAY) (<= initial-delay MAX_DELAY)) ERR_INVALID_DELAY)
    
    (var-set admin initial-admin)
    (var-set delay initial-delay)
    
    (print {
      action: "timelock-initialized",
      admin: initial-admin,
      delay: initial-delay
    })
    
    (ok true)))

;; Queue an operation
(define-public (queue-operation 
  (target principal)
  (function-name (string-ascii 50))
  (function-args (list 10 (buff 32)))
  (eta uint))
  (let ((current-delay (var-get delay))
        (min-eta (+ stacks-block-height current-delay))
        (operation-hash (generate-operation-hash target function-name function-args eta))
        (operation-id (+ (var-get operation-counter) u1)))
    
    (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
    (asserts! (>= eta min-eta) ERR_INVALID_DELAY)
    (asserts! (is-none (map-get? queued-operations operation-hash)) ERR_OPERATION_ALREADY_EXISTS)
    
    ;; Queue the operation
    (map-set queued-operations operation-hash {
      target: target,
      function-name: function-name,
      function-args: function-args,
      eta: eta,
      executed: false,
      cancelled: false,
      queued-at: stacks-block-height,
      queued-by: tx-sender
    })
    
    ;; Track operation hash
    (map-set operation-hashes operation-id operation-hash)
    (var-set operation-counter operation-id)
    
    (print {
      action: "operation-queued",
      operation-id: operation-id,
      operation-hash: operation-hash,
      target: target,
      function-name: function-name,
      eta: eta,
      queued-by: tx-sender
    })
    
    (ok operation-id)))

;; Execute a queued operation
(define-public (execute-operation (operation-hash (buff 32)))
  (match (map-get? queued-operations operation-hash)
    operation
      (let ((current-block stacks-block-height)
            (grace-period-end (+ (get eta operation) GRACE_PERIOD)))
        
        (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
        (asserts! (not (get executed operation)) ERR_EXECUTION_FAILED)
        (asserts! (not (get cancelled operation)) ERR_EXECUTION_FAILED)
        (asserts! (>= current-block (get eta operation)) ERR_OPERATION_NOT_READY)
        (asserts! (<= current-block grace-period-end) ERR_OPERATION_EXPIRED)
        
        ;; Mark as executed
        (map-set queued-operations operation-hash 
          (merge operation {executed: true}))
        
        ;; Execute the operation (placeholder - in real implementation would call target function)
        (print {
          action: "operation-executed",
          operation-hash: operation-hash,
          target: (get target operation),
          function-name: (get function-name operation),
          executed-by: tx-sender,
          executed-at: current-block
        })
        
        (ok true))
    ERR_OPERATION_NOT_FOUND))

;; Cancel a queued operation
(define-public (cancel-operation (operation-hash (buff 32)))
  (match (map-get? queued-operations operation-hash)
    operation
      (begin
        (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
        (asserts! (not (get executed operation)) ERR_EXECUTION_FAILED)
        (asserts! (not (get cancelled operation)) ERR_EXECUTION_FAILED)
        
        ;; Mark as cancelled
        (map-set queued-operations operation-hash 
          (merge operation {cancelled: true}))
        
        (print {
          action: "operation-cancelled",
          operation-hash: operation-hash,
          cancelled-by: tx-sender,
          cancelled-at: stacks-block-height
        })
        
        (ok true))
    ERR_OPERATION_NOT_FOUND))

;; Update timelock delay
(define-public (set-delay (new-delay uint))
  (begin
    (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
    (asserts! (and (>= new-delay MIN_DELAY) (<= new-delay MAX_DELAY)) ERR_INVALID_DELAY)
    
    (let ((old-delay (var-get delay)))
      (var-set delay new-delay)
      
      (print {
        action: "delay-updated",
        old-delay: old-delay,
        new-delay: new-delay,
        updated-by: tx-sender
      })
      
      (ok true))))

;; Accept admin role (two-step transfer)
(define-public (accept-admin)
  (match (var-get pending-admin)
    pending
      (begin
        (asserts! (is-eq tx-sender pending) ERR_UNAUTHORIZED)
        
        (let ((old-admin (var-get admin)))
          (var-set admin pending)
          (var-set pending-admin none)
          
          (print {
            action: "admin-changed",
            old-admin: old-admin,
            new-admin: pending
          })
          
          (ok true)))
    ERR_UNAUTHORIZED))

;; Set pending admin (first step of transfer)
(define-public (set-pending-admin (new-admin principal))
  (begin
    (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
    
    (var-set pending-admin (some new-admin))
    
    (print {
      action: "pending-admin-set",
      pending-admin: new-admin,
      set-by: tx-sender
    })
    
    (ok true)))

;; ===== READ-ONLY FUNCTIONS =====

;; Get operation details
(define-read-only (get-operation (operation-hash (buff 32)))
  (map-get? queued-operations operation-hash))

;; Get operation hash by ID
(define-read-only (get-operation-hash (operation-id uint))
  (map-get? operation-hashes operation-id))

;; Check if operation is ready for execution
(define-read-only (is-operation-ready (operation-hash (buff 32)))
  (match (map-get? queued-operations operation-hash)
    operation
      (and 
        (not (get executed operation))
        (not (get cancelled operation))
        (>= stacks-block-height (get eta operation))
        (<= stacks-block-height (+ (get eta operation) GRACE_PERIOD)))
    false))

;; Get current admin
(define-read-only (get-admin)
  (var-get admin))

;; Get pending admin
(define-read-only (get-pending-admin)
  (var-get pending-admin))

;; Get current delay
(define-read-only (get-delay)
  (var-get delay))

;; Get operation counter
(define-read-only (get-operation-counter)
  (var-get operation-counter))

;; Get timelock parameters
(define-read-only (get-timelock-parameters)
  {
    admin: (var-get admin),
    pending-admin: (var-get pending-admin),
    delay: (var-get delay),
    min-delay: MIN_DELAY,
    max-delay: MAX_DELAY,
    grace-period: GRACE_PERIOD,
    operation-counter: (var-get operation-counter)
  })
