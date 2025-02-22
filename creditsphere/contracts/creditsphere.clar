;; CreditSphere: Trust-Based Lending Protocol
;; A decentralized lending protocol powered by on-chain trust scoring

(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-AMOUNT-INVALID (err u101))
(define-constant ERR-BALANCE-TOO-LOW (err u102))
(define-constant ERR-TRUST-TOO-LOW (err u103))
(define-constant ERR-EXISTING-LOAN (err u104))
(define-constant MIN-TRUST-THRESHOLD u500) ;; Out of 1000
(define-constant TRUST-DEDUCTION u100)
(define-constant LOAN-SIZE-CAP u1000000) ;; In microSTX

;; Data Maps
(define-map trust-scores 
    principal 
    {
        trust-level: uint,
        completed-loans: uint,
        dao-activity: uint,
        lock-time: uint
    }
)

(define-map current-loans
    principal
    {
        size: uint,
        maturity-block: uint,
        completed: bool
    }
)

(define-map account-funds principal uint)

;; Initialize or update trust score
(define-public (create-trust-profile (account principal))
    (let ((existing-profile (get-trust-score account)))
        (if (is-none existing-profile)
            (ok (map-set trust-scores account {
                trust-level: u500,  ;; Base trust level
                completed-loans: u0,
                dao-activity: u0,
                lock-time: u0
            }))
            ERR-UNAUTHORIZED
        )
    )
)

;; Calculate trust level based on various metrics
(define-private (compute-trust-level 
    (completed-loans uint) 
    (dao-activity uint)
    (lock-time uint))
    (let ((base-level (* completed-loans u100))
          (dao-bonus (* dao-activity u50))
          (time-bonus (* lock-time u50)))
        (+ (+ base-level dao-bonus) time-bonus)
    )
)

;; Update trust metrics
(define-public (update-trust-metrics
    (account principal)
    (dao-points uint)
    (lock-points uint))
    (let ((current-trust (unwrap! (get-trust-score account) ERR-UNAUTHORIZED)))
        (ok (map-set trust-scores account
            {
                trust-level: (compute-trust-level 
                    (get completed-loans current-trust)
                    (+ (get dao-activity current-trust) dao-points)
                    (+ (get lock-time current-trust) lock-points)
                ),
                completed-loans: (get completed-loans current-trust),
                dao-activity: (+ (get dao-activity current-trust) dao-points),
                lock-time: (+ (get lock-time current-trust) lock-points)
            }
        ))
    )
)

;; Submit loan request
(define-public (submit-loan-request (size uint))
    (let (
        (borrower tx-sender)
        (trust-profile (unwrap! (get-trust-score borrower) ERR-UNAUTHORIZED))
        (existing-loan (get-current-loan borrower))
    )
        (asserts! (<= size LOAN-SIZE-CAP) ERR-AMOUNT-INVALID)
        (asserts! (>= (get trust-level trust-profile) MIN-TRUST-THRESHOLD) ERR-TRUST-TOO-LOW)
        (asserts! (is-none existing-loan) ERR-EXISTING-LOAN)
        
        (map-set current-loans borrower {
            size: size,
            maturity-block: (+ block-height u1440), ;; ~10 days with 10min blocks
            completed: false
        })
        
        (ok (as-contract (stx-transfer? size (as-contract tx-sender) borrower)))
    )
)

;; Complete loan repayment
(define-public (complete-repayment)
    (let (
        (borrower tx-sender)
        (loan (unwrap! (get-current-loan borrower) ERR-UNAUTHORIZED))
        (trust-profile (unwrap! (get-trust-score borrower) ERR-UNAUTHORIZED))
    )
        (asserts! (not (get completed loan)) ERR-UNAUTHORIZED)
        (try! (stx-transfer? (get size loan) borrower (as-contract tx-sender)))
        
        (map-set current-loans borrower {
            size: (get size loan),
            maturity-block: (get maturity-block loan),
            completed: true
        })
        
        (ok (map-set trust-scores borrower {
            trust-level: (+ (get trust-level trust-profile) u50),
            completed-loans: (+ (get completed-loans trust-profile) u1),
            dao-activity: (get dao-activity trust-profile),
            lock-time: (get lock-time trust-profile)
        }))
    )
)

;; Verify loan status and update trust score if defaulted
(define-public (verify-loan-status (account principal))
    (let (
        (loan (unwrap! (get-current-loan account) ERR-UNAUTHORIZED))
        (trust-profile (unwrap! (get-trust-score account) ERR-UNAUTHORIZED))
    )
        (if (and 
            (> block-height (get maturity-block loan))
            (not (get completed loan))
        )
            (ok (map-set trust-scores account {
                trust-level: (- (get trust-level trust-profile) TRUST-DEDUCTION),
                completed-loans: (get completed-loans trust-profile),
                dao-activity: (get dao-activity trust-profile),
                lock-time: (get lock-time trust-profile)
            }))
            (ok true)
        )
    )
)

;; Getter functions
(define-read-only (get-trust-score (account principal))
    (map-get? trust-scores account)
)

(define-read-only (get-current-loan (account principal))
    (map-get? current-loans account)
)

(define-read-only (get-account-balance (account principal))
    (default-to u0 (map-get? account-funds account))
)