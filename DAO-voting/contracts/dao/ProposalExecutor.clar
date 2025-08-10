;; DAO Proposal Executor Contract
;; Handles the execution of different types of proposals
;; Part of the diamond pattern architecture

;; ===== CONSTANTS =====
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_PROPOSAL_NOT_FOUND (err u404))
(define-constant ERR_PROPOSAL_NOT_EXECUTABLE (err u405))
(define-constant ERR_EXECUTION_FAILED (err u406))
(define-constant ERR_INVALID_PROPOSAL_TYPE (err u407))

;; Proposal types (must match Governed.clar)
(define-constant PROPOSAL_TYPE_TRANSFER u1)
(define-constant PROPOSAL_TYPE_PARAMETER_CHANGE u2)
(define-constant PROPOSAL_TYPE_CONTRACT_UPGRADE u3)
(define-constant PROPOSAL_TYPE_CUSTOM u4)

;; ===== DATA VARIABLES =====
(define-data-var governance-contract principal tx-sender)
(define-data-var treasury-contract principal tx-sender)

;; ===== DATA MAPS =====
;; Track proposal executions
(define-map proposal-executions uint {
  execution-type: uint,
  executed-at: uint,
  execution-result: bool,
  execution-data: (optional (buff 256))
})

;; Parameter changes that can be executed
(define-map governance-parameters (string-ascii 50) uint)

;; ===== AUTHORIZATION =====
(define-private (is-dao-authorized)
  (is-eq contract-caller (var-get governance-contract)))

;; ===== PUBLIC FUNCTIONS =====

;; Initialize with governance and treasury contracts
(define-public (initialize (governance principal) (treasury principal))
  (begin
    (asserts! (is-eq tx-sender (var-get governance-contract)) ERR_UNAUTHORIZED)
    (var-set governance-contract governance)
    (var-set treasury-contract treasury)
    
    ;; Initialize default parameters
    (map-set governance-parameters "voting-period" u1008)
    (map-set governance-parameters "execution-delay" u144)
    (map-set governance-parameters "quorum-threshold" u2000)
    (map-set governance-parameters "approval-threshold" u5100)
    
    (ok true)))

;; Execute a proposal based on its type
(define-public (execute-proposal (proposal-id uint))
  (let ((proposal (unwrap! (contract-call? .Governed get-proposal proposal-id) ERR_PROPOSAL_NOT_FOUND))
        (proposal-status (unwrap! (contract-call? .Governed get-proposal-status proposal-id) ERR_PROPOSAL_NOT_FOUND)))
    
    (asserts! (is-dao-authorized) ERR_UNAUTHORIZED)
    (asserts! (get can-execute proposal-status) ERR_PROPOSAL_NOT_EXECUTABLE)
    
    ;; Execute based on proposal type
    (let ((execution-result 
      (if (is-eq (get proposal-type proposal) PROPOSAL_TYPE_TRANSFER)
        (execute-transfer-proposal proposal-id proposal)
        (if (is-eq (get proposal-type proposal) PROPOSAL_TYPE_PARAMETER_CHANGE)
          (execute-parameter-change-proposal proposal-id proposal)
          (if (is-eq (get proposal-type proposal) PROPOSAL_TYPE_CONTRACT_UPGRADE)
            (execute-contract-upgrade-proposal proposal-id proposal)
            (if (is-eq (get proposal-type proposal) PROPOSAL_TYPE_CUSTOM)
              (execute-custom-proposal proposal-id proposal)
              ERR_INVALID_PROPOSAL_TYPE))))))
      
      ;; Record execution
      (map-set proposal-executions proposal-id {
        execution-type: (get proposal-type proposal),
        executed-at: stacks-block-height,
        execution-result: (is-ok execution-result),
        execution-data: none
      })
      
      execution-result)))

;; Execute STX transfer proposal
(define-private (execute-transfer-proposal (proposal-id uint) (proposal {
  proposer: principal,
  title: (string-ascii 100),
  description: (string-ascii 500),
  proposal-type: uint,
  start-block: uint,
  end-block: uint,
  votes-for: uint,
  votes-against: uint,
  votes-abstain: uint,
  executed: bool,
  execution-block: (optional uint),
  target-contract: (optional principal),
  function-name: (optional (string-ascii 50)),
  function-args: (optional (list 10 (buff 32)))
}))
  (let ((recipient (unwrap! (get target-contract proposal) ERR_EXECUTION_FAILED))
        (amount-bytes (unwrap! (element-at (unwrap! (get function-args proposal) ERR_EXECUTION_FAILED) u0) ERR_EXECUTION_FAILED))
        (amount (buff-to-uint-le amount-bytes)))
    
    ;; Execute transfer through treasury
    (contract-call? .Treasury execute-transfer recipient amount proposal-id)))

;; Execute parameter change proposal
(define-private (execute-parameter-change-proposal (proposal-id uint) (proposal {
  proposer: principal,
  title: (string-ascii 100),
  description: (string-ascii 500),
  proposal-type: uint,
  start-block: uint,
  end-block: uint,
  votes-for: uint,
  votes-against: uint,
  votes-abstain: uint,
  executed: bool,
  execution-block: (optional uint),
  target-contract: (optional principal),
  function-name: (optional (string-ascii 50)),
  function-args: (optional (list 10 (buff 32)))
}))
  (let ((parameter-name (unwrap! (get function-name proposal) ERR_EXECUTION_FAILED))
        (new-value-bytes (unwrap! (element-at (unwrap! (get function-args proposal) ERR_EXECUTION_FAILED) u0) ERR_EXECUTION_FAILED))
        (new-value (buff-to-uint-le new-value-bytes)))
    
    ;; Update parameter
    (map-set governance-parameters parameter-name new-value)
    
    (print {
      action: "parameter-changed",
      parameter: parameter-name,
      old-value: (default-to u0 (map-get? governance-parameters parameter-name)),
      new-value: new-value,
      proposal-id: proposal-id
    })
    
    (ok true)))

;; Execute contract upgrade proposal (placeholder)
(define-private (execute-contract-upgrade-proposal (proposal-id uint) (proposal {
  proposer: principal,
  title: (string-ascii 100),
  description: (string-ascii 500),
  proposal-type: uint,
  start-block: uint,
  end-block: uint,
  votes-for: uint,
  votes-against: uint,
  votes-abstain: uint,
  executed: bool,
  execution-block: (optional uint),
  target-contract: (optional principal),
  function-name: (optional (string-ascii 50)),
  function-args: (optional (list 10 (buff 32)))
}))
  (begin
    ;; This would implement contract upgrade logic
    ;; For now, just log the upgrade attempt
    (print {
      action: "contract-upgrade",
      target-contract: (get target-contract proposal),
      proposal-id: proposal-id
    })
    
    (ok true)))

;; Execute custom proposal
(define-private (execute-custom-proposal (proposal-id uint) (proposal {
  proposer: principal,
  title: (string-ascii 100),
  description: (string-ascii 500),
  proposal-type: uint,
  start-block: uint,
  end-block: uint,
  votes-for: uint,
  votes-against: uint,
  votes-abstain: uint,
  executed: bool,
  execution-block: (optional uint),
  target-contract: (optional principal),
  function-name: (optional (string-ascii 50)),
  function-args: (optional (list 10 (buff 32)))
}))
  (begin
    ;; Custom proposal execution logic
    ;; This could involve calling arbitrary contract functions
    (print {
      action: "custom-proposal-executed",
      target-contract: (get target-contract proposal),
      function-name: (get function-name proposal),
      proposal-id: proposal-id
    })
    
    (ok true)))

;; Helper function to convert buffer to uint (little endian)
(define-private (buff-to-uint-le (buffer (buff 32)))
  ;; Simplified implementation - in production would need proper buffer parsing
  u0)

;; Update governance contract
(define-public (update-governance (new-governance principal))
  (begin
    (asserts! (is-dao-authorized) ERR_UNAUTHORIZED)
    (var-set governance-contract new-governance)
    (ok true)))

;; Update treasury contract
(define-public (update-treasury (new-treasury principal))
  (begin
    (asserts! (is-dao-authorized) ERR_UNAUTHORIZED)
    (var-set treasury-contract new-treasury)
    (ok true)))

;; ===== READ-ONLY FUNCTIONS =====

;; Get governance contract
(define-read-only (get-governance-contract)
  (var-get governance-contract))

;; Get treasury contract
(define-read-only (get-treasury-contract)
  (var-get treasury-contract))

;; Get proposal execution details
(define-read-only (get-proposal-execution (proposal-id uint))
  (map-get? proposal-executions proposal-id))

;; Get governance parameter
(define-read-only (get-governance-parameter (parameter-name (string-ascii 50)))
  (map-get? governance-parameters parameter-name))

;; Get all governance parameters
(define-read-only (get-all-governance-parameters)
  {
    voting-period: (default-to u0 (map-get? governance-parameters "voting-period")),
    execution-delay: (default-to u0 (map-get? governance-parameters "execution-delay")),
    quorum-threshold: (default-to u0 (map-get? governance-parameters "quorum-threshold")),
    approval-threshold: (default-to u0 (map-get? governance-parameters "approval-threshold"))
  })
