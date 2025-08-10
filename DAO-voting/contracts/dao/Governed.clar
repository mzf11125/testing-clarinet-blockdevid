;; DAO Governance Contract
;; Core governance logic implementing proposal lifecycle management
;; Follows diamond pattern architecture for modularity

import ''

;; ===== CONSTANTS =====
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_PROPOSAL_NOT_FOUND (err u404))
(define-constant ERR_PROPOSAL_ALREADY_EXISTS (err u405))
(define-constant ERR_VOTING_PERIOD_ACTIVE (err u406))
(define-constant ERR_VOTING_PERIOD_ENDED (err u407))
(define-constant ERR_INSUFFICIENT_VOTING_POWER (err u408))
(define-constant ERR_ALREADY_VOTED (err u409))
(define-constant ERR_PROPOSAL_NOT_PASSED (err u410))
(define-constant ERR_PROPOSAL_ALREADY_EXECUTED (err u411))
(define-constant ERR_INVALID_PROPOSAL_TYPE (err u412))

;; Proposal types
(define-constant PROPOSAL_TYPE_TRANSFER u1)
(define-constant PROPOSAL_TYPE_PARAMETER_CHANGE u2)
(define-constant PROPOSAL_TYPE_CONTRACT_UPGRADE u3)
(define-constant PROPOSAL_TYPE_CUSTOM u4)

;; Voting periods (in blocks)
(define-constant VOTING_PERIOD u1008) ;; ~7 days at 10 min blocks
(define-constant EXECUTION_DELAY u144) ;; ~1 day delay
(define-constant MINIMUM_VOTING_POWER u1000000) ;; 1 token minimum

;; Quorum and approval thresholds (basis points: 10000 = 100%)
(define-constant QUORUM_THRESHOLD u2000) ;; 20%
(define-constant APPROVAL_THRESHOLD u5100) ;; 51%

;; ===== DATA VARIABLES =====
(define-data-var proposal-counter uint u0)
(define-data-var governance-token principal tx-sender)
(define-data-var dao-treasury principal tx-sender)

;; ===== DATA MAPS =====
;; Proposal data structure
(define-map proposals uint {
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
})

;; Individual votes
(define-map votes {proposal-id: uint, voter: principal} {
  vote-type: uint, ;; 1=for, 2=against, 3=abstain
  voting-power: uint,
  block-height: uint
})

;; Voting delegation for proposals
(define-map proposal-delegates {delegator: principal, proposal-id: uint} principal)

;; ===== PRIVATE FUNCTIONS =====

;; Calculate quorum requirement
(define-private (calculate-quorum (total-supply uint))
  (/ (* total-supply QUORUM_THRESHOLD) u10000))

;; Calculate votes needed for approval
(define-private (calculate-approval-threshold (total-votes uint))
  (/ (* total-votes APPROVAL_THRESHOLD) u10000))

;; Check if proposal has reached quorum
(define-private (has-reached-quorum (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal
      (let ((total-votes (+ (+ (get votes-for proposal) (get votes-against proposal)) (get votes-abstain proposal)))
            (total-supply (unwrap-panic (contract-call? .DaoToken get-total-supply))))
        (>= total-votes (calculate-quorum total-supply)))
    false))

;; Check if proposal is approved
(define-private (is-proposal-approved (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal
      (let ((total-votes (+ (get votes-for proposal) (get votes-against proposal)))
            (approval-threshold (calculate-approval-threshold total-votes)))
        (>= (get votes-for proposal) approval-threshold))
    false))

;; ===== PUBLIC FUNCTIONS =====

;; Initialize governance with token contract
(define-public (initialize (token-contract principal) (treasury-contract principal))
  (begin
    (asserts! (is-eq tx-sender (var-get governance-token)) ERR_UNAUTHORIZED)
    (var-set governance-token token-contract)
    (var-set dao-treasury treasury-contract)
    (ok true)))

;; Create a new proposal
(define-public (create-proposal 
  (title (string-ascii 100))
  (description (string-ascii 500))
  (proposal-type uint)
  (target-contract (optional principal))
  (function-name (optional (string-ascii 50)))
  (function-args (optional (list 10 (buff 32)))))
  (let ((proposer-voting-power (contract-call? .DaoToken get-voting-power tx-sender))
        (proposal-id (+ (var-get proposal-counter) u1))
        (start-block (+ (block-height) u1))
        (end-block (+ start-block VOTING_PERIOD)))    
    ;; Check minimum voting power requirement
    (asserts! (>= proposer-voting-power MINIMUM_VOTING_POWER) ERR_INSUFFICIENT_VOTING_POWER)
    (asserts! (<= proposal-type PROPOSAL_TYPE_CUSTOM) ERR_INVALID_PROPOSAL_TYPE)
    
    ;; Create proposal
    (map-set proposals proposal-id {
      proposer: tx-sender,
      title: title,
      description: description,
      proposal-type: proposal-type,
      start-block: start-block,
      end-block: end-block,
      votes-for: u0,
      votes-against: u0,
      votes-abstain: u0,
      executed: false,
      execution-block: none,
      target-contract: target-contract,
      function-name: function-name,
      function-args: function-args
    })
    
    ;; Update counter
    (var-set proposal-counter proposal-id)
    
    ;; Print event
    (print {
      action: "proposal-created",
      proposal-id: proposal-id,
      proposer: tx-sender,
      title: title,
      start-block: start-block,
      end-block: end-block
    })
    
    (ok proposal-id)))

;; Vote on a proposal
(define-public (vote (proposal-id uint) (vote-type uint))
  (match (map-get? proposals proposal-id)
    proposal
      (let ((voter-power (unwrap-panic (contract-call? .DaoToken get-voting-power tx-sender)))
            (current-block block-height))
        
        ;; Validate vote
        (asserts! (>= current-block (get start-block proposal)) ERR_VOTING_PERIOD_ACTIVE)
        (asserts! (<= current-block (get end-block proposal)) ERR_VOTING_PERIOD_ENDED)
        (asserts! (and (>= vote-type u1) (<= vote-type u3)) ERR_UNAUTHORIZED)
        (asserts! (> voter-power u0) ERR_INSUFFICIENT_VOTING_POWER)
        (asserts! (is-none (map-get? votes {proposal-id: proposal-id, voter: tx-sender})) ERR_ALREADY_VOTED)
        
        ;; Record vote
        (map-set votes {proposal-id: proposal-id, voter: tx-sender} {
          vote-type: vote-type,
          voting-power: voter-power,
          block-height: current-block
        })
        
        ;; Update proposal vote counts
        (let ((updated-proposal 
          (if (is-eq vote-type u1)
            (merge proposal {votes-for: (+ (get votes-for proposal) voter-power)})
            (if (is-eq vote-type u2)
              (merge proposal {votes-against: (+ (get votes-against proposal) voter-power)})
              (merge proposal {votes-abstain: (+ (get votes-abstain proposal) voter-power)})))))
          
          (map-set proposals proposal-id updated-proposal)
          
          ;; Print event
          (print {
            action: "vote-cast",
            proposal-id: proposal-id,
            voter: tx-sender,
            vote-type: vote-type,
            voting-power: voter-power
          })
          
          (ok true)))
    ERR_PROPOSAL_NOT_FOUND))

;; Execute a passed proposal
(define-public (execute-proposal (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal
      (let ((current-block block-height))
        ;; Validate execution conditions
        (asserts! (> current-block (get end-block proposal)) ERR_VOTING_PERIOD_ACTIVE)
        (asserts! (>= current-block (+ (get end-block proposal) EXECUTION_DELAY)) ERR_VOTING_PERIOD_ACTIVE)
        (asserts! (not (get executed proposal)) ERR_PROPOSAL_ALREADY_EXECUTED)
        (asserts! (has-reached-quorum proposal-id) ERR_PROPOSAL_NOT_PASSED)
        (asserts! (is-proposal-approved proposal-id) ERR_PROPOSAL_NOT_PASSED)
        
        ;; Mark as executed
        (map-set proposals proposal-id 
          (merge proposal {
            executed: true,
            execution-block: (some current-block)
          }))
        
        ;; Print event
        (print {
          action: "proposal-executed",
          proposal-id: proposal-id,
          execution-block: current-block
        })
        
        (ok true))
    ERR_PROPOSAL_NOT_FOUND))

;; Delegate voting power for a specific proposal
(define-public (delegate-for-proposal (proposal-id uint) (delegate principal))
  (begin
    (asserts! (not (is-eq tx-sender delegate)) ERR_UNAUTHORIZED)
    (map-set proposal-delegates {delegator: tx-sender, proposal-id: proposal-id} delegate)
    
    (print {
      action: "proposal-delegation",
      delegator: tx-sender,
      delegate: delegate,
      proposal-id: proposal-id
    })
    
    (ok true)))

;; ===== READ-ONLY FUNCTIONS =====

;; Get proposal details
(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals proposal-id))

;; Get vote details
(define-read-only (get-vote (proposal-id uint) (voter principal))
  (map-get? votes {proposal-id: proposal-id, voter: voter}))

;; Get proposal status
(define-read-only (get-proposal-status (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal
      (let (
            (current-block block-height)
            (votes-for (get votes-for proposal))
            (votes-against (get votes-against proposal))
            (votes-abstain (get votes-abstain proposal))
            (executed (get executed proposal))
            (start-block (get start-block proposal))
            (end-block (get end-block proposal))
            (total-votes (+ (+ votes-for votes-against) votes-abstain))
            (total-votes-approval (+ votes-for votes-against))
            ;; Calculate quorum and approval in read-only context
            (quorum-reached (>= total-votes QUORUM_THRESHOLD))
            (approved (and 
                      (> total-votes-approval u0)
                      (>= (* votes-for u100) 
                          (* total-votes-approval APPROVAL_THRESHOLD))))
      )
        (some {
          status: (if executed
                    "executed"
                    (if (> current-block end-block)
                      (if (and quorum-reached approved)
                        "passed"
                        "failed")
                      (if (>= current-block start-block)
                        "active"
                        "pending"))),
          quorum-reached: quorum-reached,
          approved: approved,
          votes-for: votes-for,
          votes-against: votes-against,
          votes-abstain: votes-abstain,
          total-votes: total-votes,
          can-execute: (and
                       (not executed)
                       (> current-block end-block)
                       (>= current-block (+ end-block EXECUTION_DELAY))
                       quorum-reached
                       approved)
        }))
    none))
;; Get current proposal counter
(define-read-only (get-proposal-counter)
  (var-get proposal-counter))

;; Get governance parameters
(define-read-only (get-governance-parameters)
  {
    voting-period: VOTING_PERIOD,
    execution-delay: EXECUTION_DELAY,
    minimum-voting-power: MINIMUM_VOTING_POWER,
    quorum-threshold: QUORUM_THRESHOLD,
    approval-threshold: APPROVAL_THRESHOLD
  })

;; Get governance token contract
(define-read-only (get-governance-token)
  (var-get governance-token))

;; Get DAO treasury contract
(define-read-only (get-dao-treasury)
  (var-get dao-treasury))