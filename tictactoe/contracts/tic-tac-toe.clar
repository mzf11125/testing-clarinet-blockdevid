;; Tic Tac Toe Game Contract with Betting
;; Secure multiplayer game dengan financial incentives

;; === CONSTANTS ===
(define-constant THIS_CONTRACT (as-contract tx-sender))

;; Error codes
(define-constant ERR_MIN_BET_AMOUNT (err u100))
(define-constant ERR_INVALID_MOVE (err u101))
(define-constant ERR_GAME_NOT_FOUND (err u102))
(define-constant ERR_GAME_CANNOT_BE_JOINED (err u103))
(define-constant ERR_NOT_YOUR_TURN (err u104))
(define-constant ERR_GAME_ALREADY_FINISHED (err u105))
(define-constant ERR_INSUFFICIENT_FUNDS (err u106))
(define-constant ERR_CANNOT_JOIN_OWN_GAME (err u107))

;; === DATA STORAGE ===

;; Game ID counter untuk unique game identification
(define-data-var latest-game-id uint u0)

;; Main games storage map
(define-map games 
    uint ;; Game ID (key)
    { ;; Game data (value)
        player-one: principal,
        player-two: (optional principal),
        is-player-one-turn: bool,
        bet-amount: uint,
        board: (list 9 uint),
        winner: (optional principal)
    }
)

;; === PUBLIC FUNCTIONS ===

;; Create new game dengan initial move
(define-public (create-game (bet-amount uint) (move-index uint) (move uint))
    (let (
        ;; Get next available game ID
        (game-id (var-get latest-game-id))
        ;; Initialize empty board
        (starting-board (list u0 u0 u0 u0 u0 u0 u0 u0 u0))
        ;; Apply creator's first move
        (game-board (unwrap! (replace-at? starting-board move-index move) ERR_INVALID_MOVE))
        ;; Create initial game data
        (game-data {
            player-one: contract-caller,
            player-two: none,
            is-player-one-turn: false, ;; Next turn belongs to player two
            bet-amount: bet-amount,
            board: game-board,
            winner: none
        })
    )
    ;; Input validation
    (asserts! (> bet-amount u0) ERR_MIN_BET_AMOUNT)
    (asserts! (is-eq move u1) ERR_INVALID_MOVE) ;; Creator must play X
    (asserts! (validate-move starting-board move-index move) ERR_INVALID_MOVE)
    
    ;; Check caller has sufficient balance
    (asserts! (>= (stx-get-balance contract-caller) bet-amount) ERR_INSUFFICIENT_FUNDS)
    
    ;; Transfer bet amount to contract
    (try! (stx-transfer? bet-amount contract-caller THIS_CONTRACT))
    
    ;; Store game state
    (map-set games game-id game-data)
    
    ;; Increment game counter untuk next game
    (var-set latest-game-id (+ game-id u1))
    
    ;; Emit event for tracking
    (print { 
        action: "create-game", 
        game-id: game-id,
        player-one: contract-caller,
        bet-amount: bet-amount,
        first-move: move-index
    })
    
    ;; Return new game ID
    (ok game-id)
    )
)

;; Join existing game as second player
(define-public (join-game (game-id uint) (move-index uint) (move uint))
    (let (
        ;; Load existing game data
        (original-game-data (unwrap! (map-get? games game-id) ERR_GAME_NOT_FOUND))
        ;; Get current board state
        (original-board (get board original-game-data))
        ;; Apply second player's move
        (game-board (unwrap! (replace-at? original-board move-index move) ERR_INVALID_MOVE))
        ;; Update game data dengan second player
        (game-data (merge original-game-data {
            board: game-board,
            player-two: (some contract-caller),
            is-player-one-turn: true ;; Next turn back to player one
        }))
    )
    ;; Validation checks
    (asserts! (is-none (get player-two original-game-data)) ERR_GAME_CANNOT_BE_JOINED)
    (asserts! (is-none (get winner original-game-data)) ERR_GAME_ALREADY_FINISHED)
    (asserts! (not (is-eq contract-caller (get player-one original-game-data))) ERR_CANNOT_JOIN_OWN_GAME)
    
    ;; Move validation
    (asserts! (is-eq move u2) ERR_INVALID_MOVE) ;; Second player must play O
    (asserts! (validate-move original-board move-index move) ERR_INVALID_MOVE)
    
    ;; Check sufficient funds for matching bet
    (asserts! (>= (stx-get-balance contract-caller) (get bet-amount original-game-data)) ERR_INSUFFICIENT_FUNDS)
    
    ;; Transfer matching bet to contract
    (try! (stx-transfer? (get bet-amount original-game-data) contract-caller THIS_CONTRACT))
    
    ;; Update game state
    (map-set games game-id game-data)
    
    ;; Emit join event
    (print { 
        action: "join-game", 
        game-id: game-id,
        player-two: contract-caller,
        move: move-index
    })
    
    (ok game-id)
    )
)

;; Make move dalam ongoing game
(define-public (play (game-id uint) (move-index uint) (move uint))
    (let (
        ;; Load current game state
        (original-game-data (unwrap! (map-get? games game-id) ERR_GAME_NOT_FOUND))
        ;; Get board state
        (original-board (get board original-game-data))
        ;; Determine current player dan move type
        (is-player-one-turn (get is-player-one-turn original-game-data))
        (current-player (if is-player-one-turn 
            (get player-one original-game-data) 
            (unwrap! (get player-two original-game-data) ERR_GAME_NOT_FOUND)))
        (expected-move (if is-player-one-turn u1 u2))
        ;; Apply the move
        (game-board (unwrap! (replace-at? original-board move-index move) ERR_INVALID_MOVE))
        ;; Check for winning condition
        (is-winner (has-won game-board))
        ;; Check for draw condition
        (is-draw (and (not is-winner) (is-board-full-list game-board)))
        ;; Create updated game state
        (game-data (merge original-game-data {
            board: game-board,
            is-player-one-turn: (not is-player-one-turn),
            winner: (if is-winner (some current-player) none)
        }))
    )
    ;; Turn validation
    (asserts! (is-eq contract-caller current-player) ERR_NOT_YOUR_TURN)
    (asserts! (is-none (get winner original-game-data)) ERR_GAME_ALREADY_FINISHED)
    
    ;; Move validation
    (asserts! (is-eq move expected-move) ERR_INVALID_MOVE)
    (asserts! (validate-move original-board move-index move) ERR_INVALID_MOVE)
    
    ;; Handle game end scenarios
    (if is-winner
        ;; Winner takes all - transfer double bet amount
        (try! (as-contract (stx-transfer? 
            (* u2 (get bet-amount game-data)) 
            tx-sender 
            current-player)))
        ;; Check for draw
        (if is-draw
            ;; Draw - return bets to both players
            (begin
                (try! (as-contract (stx-transfer? 
                    (get bet-amount game-data) 
                    tx-sender 
                    (get player-one game-data))))
                (try! (as-contract (stx-transfer? 
                    (get bet-amount game-data) 
                    tx-sender 
                    (unwrap! (get player-two game-data) ERR_GAME_NOT_FOUND))))
            )
            false
        )
    )
    
    ;; Update game state
    (map-set games game-id game-data)
    
    ;; Emit move event
    (print { 
        action: "play", 
        game-id: game-id,
        player: current-player,
        move: move-index,
        winner: (get winner game-data),
        is-draw: is-draw
    })
    
    (ok game-id)
    )
)

;; === READ-ONLY FUNCTIONS ===

;; Get complete game data
(define-read-only (get-game (game-id uint))
    (map-get? games game-id)
)

;; Get latest game ID (for finding most recent games)
(define-read-only (get-latest-game-id)
    (var-get latest-game-id)
)

;; Get just the board state
(define-read-only (get-game-board (game-id uint))
    (match (map-get? games game-id)
        game-data (ok (get board game-data))
        (err ERR_GAME_NOT_FOUND)
    )
)

;; Get current turn information
(define-read-only (get-current-turn (game-id uint))
    (match (map-get? games game-id)
        game-data (ok {
            is-player-one-turn: (get is-player-one-turn game-data),
            current-player: (if (get is-player-one-turn game-data)
                (some (get player-one game-data))
                (get player-two game-data))
        })
        (err ERR_GAME_NOT_FOUND)
    )
)

;; Get comprehensive game status
(define-read-only (get-game-status (game-id uint))
    (match (map-get? games game-id)
        game-data (let (
            (has-winner (is-some (get winner game-data)))
            (has-player-two (is-some (get player-two game-data)))
            (board-full (is-board-full-list (get board game-data)))
        )
        (ok {
            status: (if has-winner
                "finished"
                (if (not has-player-two)
                    "waiting-for-player"
                    (if (and (not has-winner) board-full)
                        "draw"
                        "in-progress"))),
            winner: (get winner game-data),
            total-prize: (* u2 (get bet-amount game-data)),
            is-draw: (and (not has-winner) board-full)
        }))
        (err ERR_GAME_NOT_FOUND)
    )
)

;; Check if board is full (for draw detection)
(define-read-only (is-board-full (game-id uint))
    (match (map-get? games game-id)
        game-data (ok (is-board-full-list (get board game-data)))
        (err ERR_GAME_NOT_FOUND)
    )
)

;; === PRIVATE HELPER FUNCTIONS ===

;; Validate move adalah legal
(define-private (validate-move (board (list 9 uint)) (move-index uint) (move uint))
    (let (
        ;; Check index dalam range 0-8
        (index-in-range (and (>= move-index u0) (< move-index u9)))
        ;; Check move value valid (1 atau 2)
        (valid-move (or (is-eq move u1) (is-eq move u2)))
        ;; Check target cell adalah empty
        (empty-spot (is-eq (unwrap! (element-at? board move-index) false) u0))
    )
    ;; All conditions must be true
    (and index-in-range valid-move empty-spot)
    )
)

;; Check apakah ada winning combination
(define-private (has-won (board (list 9 uint))) 
    (or
        ;; Check all possible winning lines
        ;; Horizontal rows
        (is-line board u0 u1 u2)
        (is-line board u3 u4 u5)
        (is-line board u6 u7 u8)
        ;; Vertical columns
        (is-line board u0 u3 u6)
        (is-line board u1 u4 u7)
        (is-line board u2 u5 u8)
        ;; Diagonal lines
        (is-line board u0 u4 u8)
        (is-line board u2 u4 u6)
    )
)

;; Check apakah three positions membentuk winning line
(define-private (is-line (board (list 9 uint)) (a uint) (b uint) (c uint)) 
    (let (
        ;; Get values at the three positions
        (a-val (unwrap! (element-at? board a) false))
        (b-val (unwrap! (element-at? board b) false))
        (c-val (unwrap! (element-at? board c) false))
    )
    ;; Check all three sama dan not empty
    (and 
        (is-eq a-val b-val) 
        (is-eq a-val c-val) 
        (not (is-eq a-val u0))
    )
    )
)

;; Helper function untuk check board penuh
(define-private (is-board-full-list (board (list 9 uint)))
    ;; Board penuh jika tidak ada empty cells (0)
    (is-eq (len (filter is-empty-cell board)) u0)
)

;; Helper untuk identify empty cells
(define-private (is-empty-cell (cell uint))
    (is-eq cell u0)
)