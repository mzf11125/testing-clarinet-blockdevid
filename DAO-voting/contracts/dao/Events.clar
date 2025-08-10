;; DAO Events Contract
;; Centralized event logging and notification system
;; Provides event tracking and analytics for DAO operations

;; ===== CONSTANTS =====
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_INVALID_EVENT_TYPE (err u402))
(define-constant ERR_EVENT_NOT_FOUND (err u404))

;; Event types
(define-constant EVENT_PROPOSAL_CREATED u1)
(define-constant EVENT_VOTE_CAST u2)
(define-constant EVENT_PROPOSAL_EXECUTED u3)
(define-constant EVENT_TOKEN_TRANSFER u4)
(define-constant EVENT_DELEGATION u5)
(define-constant EVENT_TREASURY_OPERATION u6)
(define-constant EVENT_ROLE_CHANGE u7)
(define-constant EVENT_PARAMETER_CHANGE u8)
(define-constant EVENT_EMERGENCY_ACTION u9)
(define-constant EVENT_CUSTOM u10)

;; ===== DATA VARIABLES =====
(define-data-var event-counter uint u0)
(define-data-var governance-contract principal tx-sender)

;; ===== DATA MAPS =====
;; Event logs
(define-map events uint {
  event-type: uint,
  actor: principal,
  target: (optional principal),
  data: (buff 256),
  timestamp: uint,
  block-height: uint,
  category: (string-ascii 50)
})

;; Event subscriptions
(define-map subscriptions {subscriber: principal, event-type: uint} bool)

;; Event categories for filtering
(define-map event-categories (string-ascii 50) {
  description: (string-ascii 200),
  active: bool
})

;; Actor event counts
(define-map actor-event-counts {actor: principal, event-type: uint} uint)

;; Daily event aggregates
(define-map daily-aggregates {date: uint, event-type: uint} uint)

;; ===== AUTHORIZATION =====
(define-private (is-authorized-logger (caller principal))
  (or 
    (is-eq caller (var-get governance-contract))
    (is-eq caller contract-caller)))

;; ===== PUBLIC FUNCTIONS =====

;; Initialize event system
(define-public (initialize (governance principal))
  (begin
    (asserts! (is-eq tx-sender (var-get governance-contract)) ERR_UNAUTHORIZED)
    (var-set governance-contract governance)
    
    ;; Initialize event categories
    (map-set event-categories "governance" {description: "Governance related events", active: true})
    (map-set event-categories "treasury" {description: "Treasury operations", active: true})
    (map-set event-categories "tokens" {description: "Token operations", active: true})
    (map-set event-categories "access" {description: "Access control changes", active: true})
    (map-set event-categories "emergency" {description: "Emergency actions", active: true})
    
    (print {
      action: "events-initialized",
      governance: governance
    })
    
    (ok true)))

;; Log an event
(define-public (log-event 
  (event-type uint)
  (actor principal)
  (target (optional principal))
  (data (buff 256))
  (category (string-ascii 50)))
  (let ((event-id (+ (var-get event-counter) u1))
        (current-block stacks-block-height)
        (daily-key (/ current-block u144))) ;; Approximate daily buckets
    
    (asserts! (is-authorized-logger contract-caller) ERR_UNAUTHORIZED)
    (asserts! (<= event-type EVENT_CUSTOM) ERR_INVALID_EVENT_TYPE)
    
    ;; Log the event
    (map-set events event-id {
      event-type: event-type,
      actor: actor,
      target: target,
      data: data,
      timestamp: (unwrap-panic (get-stacks-block-info? time current-block)),
      block-height: current-block,
      category: category
    })
    
    ;; Update counters
    (var-set event-counter event-id)
    
    ;; Update actor event count
    (let ((current-count (default-to u0 (map-get? actor-event-counts {actor: actor, event-type: event-type}))))
      (map-set actor-event-counts {actor: actor, event-type: event-type} (+ current-count u1)))
    
    ;; Update daily aggregate
    (let ((daily-count (default-to u0 (map-get? daily-aggregates {date: daily-key, event-type: event-type}))))
      (map-set daily-aggregates {date: daily-key, event-type: event-type} (+ daily-count u1)))
    
    (print {
      action: "event-logged",
      event-id: event-id,
      event-type: event-type,
      actor: actor,
      category: category
    })
    
    (ok event-id)))

;; Subscribe to event type
(define-public (subscribe-to-events (event-type uint))
  (begin
    (asserts! (<= event-type EVENT_CUSTOM) ERR_INVALID_EVENT_TYPE)
    
    (map-set subscriptions {subscriber: tx-sender, event-type: event-type} true)
    
    (print {
      action: "event-subscription",
      subscriber: tx-sender,
      event-type: event-type
    })
    
    (ok true)))

;; Unsubscribe from event type
(define-public (unsubscribe-from-events (event-type uint))
  (begin
    (map-delete subscriptions {subscriber: tx-sender, event-type: event-type})
    
    (print {
      action: "event-unsubscription",
      subscriber: tx-sender,
      event-type: event-type
    })
    
    (ok true)))

;; Batch log events (for efficiency)
(define-public (log-batch-events (events-data (list 10 {
  event-type: uint,
  actor: principal,
  target: (optional principal),
  data: (buff 256),
  category: (string-ascii 50)
})))
  (begin
    (asserts! (is-authorized-logger contract-caller) ERR_UNAUTHORIZED)
    
    (try! (fold log-single-event events-data (ok u0)))
    
    (ok (len events-data))))

;; Helper for batch logging
(define-private (log-single-event 
  (event-data {
    event-type: uint,
    actor: principal,
    target: (optional principal),
    data: (buff 256),
    category: (string-ascii 50)
  })
  (result (response uint uint)))
  (match result
    success (log-event 
              (get event-type event-data)
              (get actor event-data)
              (get target event-data)
              (get data event-data)
              (get category event-data))
    error result))

;; Create custom event category
(define-public (create-event-category (name (string-ascii 50)) (description (string-ascii 200)))
  (begin
    (asserts! (is-eq contract-caller (var-get governance-contract)) ERR_UNAUTHORIZED)
    
    (map-set event-categories name {description: description, active: true})
    
    (print {
      action: "event-category-created",
      name: name,
      description: description
    })
    
    (ok true)))

;; ===== READ-ONLY FUNCTIONS =====

;; Get event details
(define-read-only (get-event (event-id uint))
  (map-get? events event-id))

;; Get events by actor
(define-read-only (get-actor-event-count (actor principal) (event-type uint))
  (default-to u0 (map-get? actor-event-counts {actor: actor, event-type: event-type})))

;; Get daily event count
(define-read-only (get-daily-event-count (date uint) (event-type uint))
  (default-to u0 (map-get? daily-aggregates {date: date, event-type: event-type})))

;; Check subscription
(define-read-only (is-subscribed (subscriber principal) (event-type uint))
  (default-to false (map-get? subscriptions {subscriber: subscriber, event-type: event-type})))

;; Get event category
(define-read-only (get-event-category (name (string-ascii 50)))
  (map-get? event-categories name))

;; Get event counter
(define-read-only (get-event-counter)
  (var-get event-counter))

;; Get governance contract
(define-read-only (get-governance-contract)
  (var-get governance-contract))

;; Get event type constants
(define-read-only (get-event-types)
  {
    proposal-created: EVENT_PROPOSAL_CREATED,
    vote-cast: EVENT_VOTE_CAST,
    proposal-executed: EVENT_PROPOSAL_EXECUTED,
    token-transfer: EVENT_TOKEN_TRANSFER,
    delegation: EVENT_DELEGATION,
    treasury-operation: EVENT_TREASURY_OPERATION,
    role-change: EVENT_ROLE_CHANGE,
    parameter-change: EVENT_PARAMETER_CHANGE,
    emergency-action: EVENT_EMERGENCY_ACTION,
    custom: EVENT_CUSTOM
  })

;; Get event analytics summary
(define-read-only (get-event-analytics (actor principal))
  {
    total-events: (+ (+ (+ (get-actor-event-count actor EVENT_PROPOSAL_CREATED)
                           (get-actor-event-count actor EVENT_VOTE_CAST))
                        (+ (get-actor-event-count actor EVENT_PROPOSAL_EXECUTED)
                           (get-actor-event-count actor EVENT_TOKEN_TRANSFER)))
                     (+ (+ (get-actor-event-count actor EVENT_DELEGATION)
                           (get-actor-event-count actor EVENT_TREASURY_OPERATION))
                        (+ (get-actor-event-count actor EVENT_ROLE_CHANGE)
                           (get-actor-event-count actor EVENT_PARAMETER_CHANGE)))),
    proposals-created: (get-actor-event-count actor EVENT_PROPOSAL_CREATED),
    votes-cast: (get-actor-event-count actor EVENT_VOTE_CAST),
    proposals-executed: (get-actor-event-count actor EVENT_PROPOSAL_EXECUTED),
    token-transfers: (get-actor-event-count actor EVENT_TOKEN_TRANSFER),
    delegations: (get-actor-event-count actor EVENT_DELEGATION),
    treasury-operations: (get-actor-event-count actor EVENT_TREASURY_OPERATION)
  })
