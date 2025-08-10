;; DAO Factory Contract
;; Creates and manages multiple DAO instances
;; Implements the diamond pattern for modularity

;; ===== CONSTANTS =====
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_DAO_ALREADY_EXISTS (err u402))
(define-constant ERR_DAO_NOT_FOUND (err u403))
(define-constant ERR_INVALID_PARAMETERS (err u404))
(define-constant ERR_DEPLOYMENT_FAILED (err u405))

;; ===== DATA VARIABLES =====
(define-data-var dao-counter uint u0)
(define-data-var factory-owner principal tx-sender)

;; ===== DATA MAPS =====
;; DAO registry
(define-map daos uint {
  name: (string-ascii 50),
  description: (string-ascii 200),
  creator: principal,
  token-contract: principal,
  governance-contract: principal,
  treasury-contract: principal,
  created-at: uint,
  active: bool
})

;; DAO name to ID mapping
(define-map dao-names (string-ascii 50) uint)

;; Creator to DAOs mapping
(define-map creator-daos principal (list 20 uint))

;; DAO templates
(define-map dao-templates uint {
  name: (string-ascii 50),
  description: (string-ascii 200),
  voting-period: uint,
  execution-delay: uint,
  quorum-threshold: uint,
  approval-threshold: uint,
  min-voting-power: uint
})

;; ===== PRIVATE FUNCTIONS =====

;; Add DAO to creator's list
(define-private (add-dao-to-creator (creator principal) (dao-id uint))
  (let ((current-daos (default-to (list) (map-get? creator-daos creator))))
    (map-set creator-daos creator (unwrap-panic (as-max-len? (append current-daos dao-id) u20)))
    (ok true)))

;; ===== PUBLIC FUNCTIONS =====

;; Create a new DAO template
(define-public (create-dao-template 
  (name (string-ascii 50))
  (description (string-ascii 200))
  (voting-period uint)
  (execution-delay uint)
  (quorum-threshold uint)
  (approval-threshold uint)
  (min-voting-power uint))
  (let ((template-id (+ (var-get dao-counter) u1)))
    
    (asserts! (is-eq tx-sender (var-get factory-owner)) ERR_UNAUTHORIZED)
    (asserts! (> voting-period u0) ERR_INVALID_PARAMETERS)
    (asserts! (<= quorum-threshold u10000) ERR_INVALID_PARAMETERS)
    (asserts! (<= approval-threshold u10000) ERR_INVALID_PARAMETERS)
    
    (map-set dao-templates template-id {
      name: name,
      description: description,
      voting-period: voting-period,
      execution-delay: execution-delay,
      quorum-threshold: quorum-threshold,
      approval-threshold: approval-threshold,
      min-voting-power: min-voting-power
    })
    
    (print {
      action: "dao-template-created",
      template-id: template-id,
      name: name,
      creator: tx-sender
    })
    
    (ok template-id)))

;; Deploy a new DAO
(define-public (deploy-dao 
  (name (string-ascii 50))
  (description (string-ascii 200))
  (token-name (string-ascii 32))
  (token-symbol (string-ascii 32))
  (initial-supply uint)
  (template-id (optional uint)))
  (let ((dao-id (+ (var-get dao-counter) u1))
        (template (match template-id
                    some-id (map-get? dao-templates some-id)
                    none)))
    
    ;; Check if DAO name is unique
    (asserts! (is-none (map-get? dao-names name)) ERR_DAO_ALREADY_EXISTS)
    (asserts! (> initial-supply u0) ERR_INVALID_PARAMETERS)
    
    ;; For now, we'll use placeholder contract addresses
    ;; In a real implementation, this would deploy actual contracts
    (let ((token-contract tx-sender) ;; Placeholder
          (governance-contract tx-sender) ;; Placeholder  
          (treasury-contract tx-sender)) ;; Placeholder
      
      ;; Register DAO
      (map-set daos dao-id {
        name: name,
        description: description,
        creator: tx-sender,
        token-contract: token-contract,
        governance-contract: governance-contract,
        treasury-contract: treasury-contract,
        created-at: stacks-block-height,
        active: true
      })
      
      ;; Map name to ID
      (map-set dao-names name dao-id)
      
      ;; Add to creator's list
      (try! (add-dao-to-creator tx-sender dao-id))
      
      ;; Update counter
      (var-set dao-counter dao-id)
      
      (print {
        action: "dao-deployed",
        dao-id: dao-id,
        name: name,
        creator: tx-sender,
        token-contract: token-contract,
        governance-contract: governance-contract,
        treasury-contract: treasury-contract
      })
      
      (ok dao-id))))

;; Update DAO status
(define-public (update-dao-status (dao-id uint) (active bool))
  (match (map-get? daos dao-id)
    dao
      (begin
        (asserts! (is-eq tx-sender (get creator dao)) ERR_UNAUTHORIZED)
        (map-set daos dao-id (merge dao {active: active}))
        
        (print {
          action: "dao-status-updated",
          dao-id: dao-id,
          active: active,
          updater: tx-sender
        })
        
        (ok true))
    ERR_DAO_NOT_FOUND))

;; Transfer DAO ownership
(define-public (transfer-dao-ownership (dao-id uint) (new-creator principal))
  (match (map-get? daos dao-id)
    dao
      (begin
        (asserts! (is-eq tx-sender (get creator dao)) ERR_UNAUTHORIZED)
        
        ;; Remove from old creator's list (simplified)
        ;; Add to new creator's list
        (try! (add-dao-to-creator new-creator dao-id))
        
        ;; Update DAO record
        (map-set daos dao-id (merge dao {creator: new-creator}))
        
        (print {
          action: "dao-ownership-transferred",
          dao-id: dao-id,
          old-creator: tx-sender,
          new-creator: new-creator
        })
        
        (ok true))
    ERR_DAO_NOT_FOUND))

;; Update factory owner
(define-public (update-factory-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get factory-owner)) ERR_UNAUTHORIZED)
    (var-set factory-owner new-owner)
    
    (print {
      action: "factory-owner-updated",
      old-owner: tx-sender,
      new-owner: new-owner
    })
    
    (ok true)))

;; Emergency pause DAO
(define-public (emergency-pause-dao (dao-id uint))
  (begin
    (asserts! (is-eq tx-sender (var-get factory-owner)) ERR_UNAUTHORIZED)
    
    (match (map-get? daos dao-id)
      dao
        (begin
          (map-set daos dao-id (merge dao {active: false}))
          
          (print {
            action: "dao-emergency-paused",
            dao-id: dao-id,
            paused-by: tx-sender
          })
          
          (ok true))
      ERR_DAO_NOT_FOUND)))

;; ===== READ-ONLY FUNCTIONS =====

;; Get DAO details
(define-read-only (get-dao (dao-id uint))
  (map-get? daos dao-id))

;; Get DAO by name
(define-read-only (get-dao-by-name (name (string-ascii 50)))
  (match (map-get? dao-names name)
    dao-id (map-get? daos dao-id)
    none))

;; Get DAOs created by user
(define-read-only (get-user-daos (creator principal))
  (default-to (list) (map-get? creator-daos creator)))

;; Get DAO counter
(define-read-only (get-dao-counter)
  (var-get dao-counter))

;; Get factory owner
(define-read-only (get-factory-owner)
  (var-get factory-owner))

;; Get DAO template
(define-read-only (get-dao-template (template-id uint))
  (map-get? dao-templates template-id))

;; Check if DAO name is available
(define-read-only (is-dao-name-available (name (string-ascii 50)))
  (is-none (map-get? dao-names name)))

;; Get DAO statistics
(define-read-only (get-dao-statistics)
  {
    total-daos: (var-get dao-counter),
    factory-owner: (var-get factory-owner)
  })

;; Get DAO contracts
(define-read-only (get-dao-contracts (dao-id uint))
  (match (map-get? daos dao-id)
    dao
      (some {
        token-contract: (get token-contract dao),
        governance-contract: (get governance-contract dao),
        treasury-contract: (get treasury-contract dao)
      })
    none))
