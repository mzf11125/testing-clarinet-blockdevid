;; DAO Voting Strategy Contract
;; Implements different voting mechanisms and strategies
;; Part of the diamond pattern architecture

;; ===== CONSTANTS =====
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_INVALID_STRATEGY (err u402))
(define-constant ERR_INVALID_PARAMETERS (err u403))
(define-constant ERR_VOTING_POWER_CALCULATION_FAILED (err u404))

;; Voting strategies
(define-constant STRATEGY_SIMPLE_MAJORITY u1)
(define-constant STRATEGY_SUPERMAJORITY u2)
(define-constant STRATEGY_QUADRATIC u3)
(define-constant STRATEGY_DELEGATED u4)

;; ===== DATA VARIABLES =====
(define-data-var governance-contract principal tx-sender)
(define-data-var default-strategy uint STRATEGY_SIMPLE_MAJORITY)

;; ===== DATA MAPS =====
;; Strategy configurations
(define-map strategy-configs uint {
  name: (string-ascii 50),
  threshold: uint,
  quorum: uint,
  active: bool
})

;; Proposal-specific strategies
(define-map proposal-strategies uint uint)

;; Quadratic voting credits
(define-map quadratic-credits {user: principal, proposal: uint} uint)

;; Voting power multipliers for different strategies
(define-map voting-multipliers {strategy: uint, user: principal} uint)

;; ===== PRIVATE FUNCTIONS =====

;; ===== PUBLIC FUNCTIONS =====

;; Initialize voting strategies
(define-public (initialize (governance principal))
  (begin
    (asserts! (is-eq tx-sender (var-get governance-contract)) ERR_UNAUTHORIZED)
    (var-set governance-contract governance)
    
    ;; Initialize default strategies
    (map-set strategy-configs STRATEGY_SIMPLE_MAJORITY {
      name: "Simple Majority",
      threshold: u5000, ;; 50%
      quorum: u2000,    ;; 20%
      active: true
    })
    
    (map-set strategy-configs STRATEGY_SUPERMAJORITY {
      name: "Supermajority",
      threshold: u6700, ;; 67%
      quorum: u3000,    ;; 30%
      active: true
    })
    
    (map-set strategy-configs STRATEGY_QUADRATIC {
      name: "Quadratic Voting",
      threshold: u5000, ;; 50%
      quorum: u2500,    ;; 25%
      active: true
    })
    
    (map-set strategy-configs STRATEGY_DELEGATED {
      name: "Delegated Voting",
      threshold: u5000, ;; 50%
      quorum: u2000,    ;; 20%
      active: true
    })
    
    (ok true)))

;; Set strategy for a specific proposal
(define-public (set-proposal-strategy (proposal-id uint) (strategy uint))
  (begin
    (asserts! (is-eq contract-caller (var-get governance-contract)) ERR_UNAUTHORIZED)
    (asserts! (<= strategy STRATEGY_DELEGATED) ERR_INVALID_STRATEGY)
    (asserts! (default-to false (get active (map-get? strategy-configs strategy))) ERR_INVALID_STRATEGY)
    
    (map-set proposal-strategies proposal-id strategy)
    
    (print {
      action: "strategy-set",
      proposal-id: proposal-id,
      strategy: strategy
    })
    
    (ok true)))

;; Allocate quadratic voting credits
(define-public (allocate-quadratic-credits (proposal-id uint) (user principal) (credits uint))
  (begin
    (asserts! (is-eq contract-caller (var-get governance-contract)) ERR_UNAUTHORIZED)
    (asserts! (> credits u0) ERR_INVALID_PARAMETERS)
    
    (map-set quadratic-credits {user: user, proposal: proposal-id} credits)
    
    (print {
      action: "quadratic-credits-allocated",
      user: user,
      proposal-id: proposal-id,
      credits: credits
    })
    
    (ok true)))

;; Calculate effective voting power based on strategy
(define-public (calculate-voting-power (user principal) (proposal-id uint) (base-power uint))
  (let ((strategy (default-to (var-get default-strategy) (map-get? proposal-strategies proposal-id))))
    
    (if (is-eq strategy STRATEGY_SIMPLE_MAJORITY)
      (ok base-power)
      (if (is-eq strategy STRATEGY_SUPERMAJORITY)
        (ok base-power)
        (if (is-eq strategy STRATEGY_QUADRATIC)
          (ok (calculate-quadratic-power-simple base-power))
          (if (is-eq strategy STRATEGY_DELEGATED)
            (ok (calculate-delegated-voting-power-simple user proposal-id base-power))
            ERR_INVALID_STRATEGY))))))

;; Simple quadratic power calculation (non-recursive)
(define-read-only (calculate-quadratic-power-simple (credits uint))
  ;; Simple approximation: return half of the square root for demo
  (/ credits u2))

;; Simple delegated voting power calculation
(define-read-only (calculate-delegated-voting-power-simple (user principal) (proposal-id uint) (base-power uint))
  (let ((delegate (contract-call? .DaoToken get-delegate user)))
    (if (is-some delegate)
      ;; If user has delegated, their voting power is 0
      u0
      ;; If user is a delegate, get their base power
      base-power)))

;; Update strategy configuration
(define-public (update-strategy-config (strategy uint) (threshold uint) (quorum uint) (active bool))
  (begin
    (asserts! (is-eq contract-caller (var-get governance-contract)) ERR_UNAUTHORIZED)
    (asserts! (<= strategy STRATEGY_DELEGATED) ERR_INVALID_STRATEGY)
    (asserts! (<= threshold u10000) ERR_INVALID_PARAMETERS)
    (asserts! (<= quorum u10000) ERR_INVALID_PARAMETERS)
    
    (let ((current-config (unwrap! (map-get? strategy-configs strategy) ERR_INVALID_STRATEGY)))
      (map-set strategy-configs strategy (merge current-config {
        threshold: threshold,
        quorum: quorum,
        active: active
      }))
      
      (print {
        action: "strategy-config-updated",
        strategy: strategy,
        threshold: threshold,
        quorum: quorum,
        active: active
      })
      
      (ok true))))

;; Set default strategy
(define-public (set-default-strategy (strategy uint))
  (begin
    (asserts! (is-eq contract-caller (var-get governance-contract)) ERR_UNAUTHORIZED)
    (asserts! (<= strategy STRATEGY_DELEGATED) ERR_INVALID_STRATEGY)
    (asserts! (default-to false (get active (map-get? strategy-configs strategy))) ERR_INVALID_STRATEGY)
    
    (var-set default-strategy strategy)
    
    (print {
      action: "default-strategy-changed",
      old-strategy: (var-get default-strategy),
      new-strategy: strategy
    })
    
    (ok true)))

;; ===== READ-ONLY FUNCTIONS =====

;; Get strategy for proposal
(define-read-only (get-proposal-strategy (proposal-id uint))
  (default-to (var-get default-strategy) (map-get? proposal-strategies proposal-id)))

;; Get strategy configuration
(define-read-only (get-strategy-config (strategy uint))
  (map-get? strategy-configs strategy))

;; Get quadratic credits for user and proposal
(define-read-only (get-quadratic-credits (user principal) (proposal-id uint))
  (default-to u0 (map-get? quadratic-credits {user: user, proposal: proposal-id})))

;; Get default strategy
(define-read-only (get-default-strategy)
  (var-get default-strategy))

;; Get governance contract
(define-read-only (get-governance-contract)
  (var-get governance-contract))

;; Check if strategy is active
(define-read-only (is-strategy-active (strategy uint))
  (default-to false (get active (map-get? strategy-configs strategy))))

;; Get voting threshold for proposal
(define-read-only (get-voting-threshold (proposal-id uint))
  (let ((strategy (get-proposal-strategy proposal-id)))
    (default-to u5000 (get threshold (map-get? strategy-configs strategy)))))

;; Get quorum requirement for proposal
(define-read-only (get-quorum-requirement (proposal-id uint))
  (let ((strategy (get-proposal-strategy proposal-id)))
    (default-to u2000 (get quorum (map-get? strategy-configs strategy)))))
