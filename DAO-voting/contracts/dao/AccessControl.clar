;; DAO Access Control Contract
;; Implements role-based access control for DAO operations
;; Part of the diamond pattern architecture

;; ===== CONSTANTS =====
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_ROLE_NOT_FOUND (err u404))
(define-constant ERR_ROLE_ALREADY_EXISTS (err u405))
(define-constant ERR_INVALID_ROLE (err u406))
(define-constant ERR_SELF_REVOKE_ADMIN (err u407))

;; Default roles
(define-constant ADMIN_ROLE "admin")
(define-constant PROPOSER_ROLE "proposer")
(define-constant EXECUTOR_ROLE "executor")
(define-constant VOTER_ROLE "voter")
(define-constant TREASURY_MANAGER_ROLE "treasury_manager")

;; ===== DATA VARIABLES =====
(define-data-var contract-owner principal tx-sender)
(define-data-var role-counter uint u0)

;; ===== DATA MAPS =====
;; Role definitions
(define-map roles (string-ascii 50) {
  description: (string-ascii 200),
  admin-role: (string-ascii 50),
  created-at: uint,
  active: bool
})

;; User role assignments
(define-map user-roles {user: principal, role: (string-ascii 50)} {
  granted-at: uint,
  granted-by: principal,
  active: bool
})

;; Role administrators
(define-map role-admins {role: (string-ascii 50), admin: principal} bool)

;; Permission mappings
(define-map role-permissions {role: (string-ascii 50), permission: (string-ascii 50)} bool)

;; ===== AUTHORIZATION CHECKS =====

;; Check if user has a specific role
(define-read-only (has-role (user principal) (role (string-ascii 50)))
  (match (map-get? user-roles {user: user, role: role})
    role-data (get active role-data)
    false))

;; Check if user has any of the specified roles
(define-read-only (has-any-role (user principal) (role-list (list 10 (string-ascii 50))))
  (fold check-role-in-list role-list {user: user, has-role: false}))

;; Helper function for role checking
(define-private (check-role-in-list (role (string-ascii 50)) (context {user: principal, has-role: bool}))
  (if (get has-role context)
    context
    {user: (get user context), has-role: (has-role (get user context) role)}))

;; Check if user can manage a specific role
(define-read-only (can-manage-role (user principal) (role (string-ascii 50)))
  (or 
    (is-eq user (var-get contract-owner))
    (has-role user ADMIN_ROLE)
    (default-to false (map-get? role-admins {role: role, admin: user}))))

;; ===== PUBLIC FUNCTIONS =====

;; Initialize default roles
(define-public (initialize)
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
    
    ;; Create default roles
    (try! (create-role ADMIN_ROLE "Full administrative access" ADMIN_ROLE))
    (try! (create-role PROPOSER_ROLE "Can create proposals" ADMIN_ROLE))
    (try! (create-role EXECUTOR_ROLE "Can execute proposals" ADMIN_ROLE))
    (try! (create-role VOTER_ROLE "Can vote on proposals" ADMIN_ROLE))
    (try! (create-role TREASURY_MANAGER_ROLE "Can manage treasury operations" ADMIN_ROLE))
    
    ;; Grant admin role to contract owner
    (try! (grant-role tx-sender ADMIN_ROLE))
    
    (print {
      action: "access-control-initialized",
      owner: tx-sender
    })
    
    (ok true)))

;; Create a new role
(define-public (create-role 
  (role (string-ascii 50))
  (description (string-ascii 200))
  (admin-role (string-ascii 50)))
  (begin
    (asserts! (can-manage-role tx-sender admin-role) ERR_UNAUTHORIZED)
    (asserts! (is-none (map-get? roles role)) ERR_ROLE_ALREADY_EXISTS)
    
    ;; Create role
    (map-set roles role {
      description: description,
      admin-role: admin-role,
      created-at: stacks-block-height,
      active: true
    })
    
    (var-set role-counter (+ (var-get role-counter) u1))
    
    (print {
      action: "role-created",
      role: role,
      description: description,
      admin-role: admin-role,
      creator: tx-sender
    })
    
    (ok true)))

;; Grant role to user
(define-public (grant-role (user principal) (role (string-ascii 50)))
  (let ((role-data (unwrap! (map-get? roles role) ERR_ROLE_NOT_FOUND)))
    
    (asserts! (can-manage-role tx-sender (get admin-role role-data)) ERR_UNAUTHORIZED)
    (asserts! (get active role-data) ERR_INVALID_ROLE)
    
    ;; Grant role
    (map-set user-roles {user: user, role: role} {
      granted-at: stacks-block-height,
      granted-by: tx-sender,
      active: true
    })
    
    (print {
      action: "role-granted",
      user: user,
      role: role,
      granted-by: tx-sender
    })
    
    (ok true)))

;; Revoke role from user
(define-public (revoke-role (user principal) (role (string-ascii 50)))
  (let ((role-data (unwrap! (map-get? roles role) ERR_ROLE_NOT_FOUND)))
    
    (asserts! (can-manage-role tx-sender (get admin-role role-data)) ERR_UNAUTHORIZED)
    
    ;; Prevent admin from revoking their own admin role
    (asserts! (not (and (is-eq user tx-sender) (is-eq role ADMIN_ROLE))) ERR_SELF_REVOKE_ADMIN)
    
    ;; Revoke role
    (match (map-get? user-roles {user: user, role: role})
      current-role
        (map-set user-roles {user: user, role: role} 
          (merge current-role {active: false}))
      true) ;; No existing role assignment
    
    (print {
      action: "role-revoked",
      user: user,
      role: role,
      revoked-by: tx-sender
    })
    
    (ok true)))

;; Renounce own role
(define-public (renounce-role (role (string-ascii 50)))
  (begin
    ;; Prevent admin from renouncing their own admin role if they're the only admin
    (asserts! (not (is-eq role ADMIN_ROLE)) ERR_SELF_REVOKE_ADMIN)
    
    ;; Renounce role
    (match (map-get? user-roles {user: tx-sender, role: role})
      current-role
        (map-set user-roles {user: tx-sender, role: role} 
          (merge current-role {active: false}))
      true) ;; No existing role assignment
    
    (print {
      action: "role-renounced",
      user: tx-sender,
      role: role
    })
    
    (ok true)))

;; Set role admin
(define-public (set-role-admin (role (string-ascii 50)) (admin-role (string-ascii 50)))
  (let ((role-data (unwrap! (map-get? roles role) ERR_ROLE_NOT_FOUND)))
    
    (asserts! (can-manage-role tx-sender (get admin-role role-data)) ERR_UNAUTHORIZED)
    
    ;; Update role admin
    (map-set roles role (merge role-data {admin-role: admin-role}))
    
    (print {
      action: "role-admin-changed",
      role: role,
      old-admin-role: (get admin-role role-data),
      new-admin-role: admin-role,
      changed-by: tx-sender
    })
    
    (ok true)))

;; Grant permission to role
(define-public (grant-permission (role (string-ascii 50)) (permission (string-ascii 50)))
  (let ((role-data (unwrap! (map-get? roles role) ERR_ROLE_NOT_FOUND)))
    
    (asserts! (can-manage-role tx-sender (get admin-role role-data)) ERR_UNAUTHORIZED)
    
    (map-set role-permissions {role: role, permission: permission} true)
    
    (print {
      action: "permission-granted",
      role: role,
      permission: permission,
      granted-by: tx-sender
    })
    
    (ok true)))

;; Revoke permission from role
(define-public (revoke-permission (role (string-ascii 50)) (permission (string-ascii 50)))
  (let ((role-data (unwrap! (map-get? roles role) ERR_ROLE_NOT_FOUND)))
    
    (asserts! (can-manage-role tx-sender (get admin-role role-data)) ERR_UNAUTHORIZED)
    
    (map-delete role-permissions {role: role, permission: permission})
    
    (print {
      action: "permission-revoked",
      role: role,
      permission: permission,
      revoked-by: tx-sender
    })
    
    (ok true)))

;; Transfer contract ownership
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
    
    ;; Grant admin role to new owner
    (try! (grant-role new-owner ADMIN_ROLE))
    
    ;; Update contract owner
    (var-set contract-owner new-owner)
    
    (print {
      action: "ownership-transferred",
      old-owner: tx-sender,
      new-owner: new-owner
    })
    
    (ok true)))

;; ===== READ-ONLY FUNCTIONS =====

;; Get role information
(define-read-only (get-role (role (string-ascii 50)))
  (map-get? roles role))

;; Get user role assignment
(define-read-only (get-user-role (user principal) (role (string-ascii 50)))
  (map-get? user-roles {user: user, role: role}))

;; Check if role has permission
(define-read-only (has-permission (role (string-ascii 50)) (permission (string-ascii 50)))
  (default-to false (map-get? role-permissions {role: role, permission: permission})))

;; Check if user has permission (through roles)
(define-read-only (user-has-permission (user principal) (permission (string-ascii 50)))
  (or
    (and (has-role user ADMIN_ROLE) (has-permission ADMIN_ROLE permission))
    (and (has-role user PROPOSER_ROLE) (has-permission PROPOSER_ROLE permission))
    (and (has-role user EXECUTOR_ROLE) (has-permission EXECUTOR_ROLE permission))
    (and (has-role user VOTER_ROLE) (has-permission VOTER_ROLE permission))
    (and (has-role user TREASURY_MANAGER_ROLE) (has-permission TREASURY_MANAGER_ROLE permission))))

;; Get contract owner
(define-read-only (get-contract-owner)
  (var-get contract-owner))

;; Get role counter
(define-read-only (get-role-counter)
  (var-get role-counter))

;; Get default roles
(define-read-only (get-default-roles)
  {
    admin: ADMIN_ROLE,
    proposer: PROPOSER_ROLE,
    executor: EXECUTOR_ROLE,
    voter: VOTER_ROLE,
    treasury-manager: TREASURY_MANAGER_ROLE
  })
