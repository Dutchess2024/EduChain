;; EduChain - Decentralized Academic Credential Verification Network
(define-fungible-token validation-token)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-access-forbidden (err u801))
(define-constant err-insufficient-tokens (err u601))
(define-constant err-credential-not-found (err u602))
(define-constant err-already-validated (err u603))
(define-constant err-validation-expired (err u604))
(define-constant err-validation-active (err u605))
(define-constant err-invalid-degree-title (err u606))
(define-constant err-invalid-institution-info (err u607))
(define-constant err-invalid-transcript-link (err u608))
(define-constant err-invalid-token-quantity (err u609))

;; Storage
(define-map academic-credentials uint {
  graduate: principal,
  degree-title: (string-utf8 64),
  institution-details: (string-utf8 256),
  transcript-reference: (string-utf8 128),
  endorsements: uint,
  challenges: uint,
  verification-status: (string-utf8 16),
  validation-deadline: uint
})

(define-map credential-validations {credential-id: uint, validator: principal} bool)
(define-map educator-tokens principal uint)
(define-data-var credential-counter uint u0)
(define-data-var min-validation-stake uint u40000000) ;; 40 tokens
(define-data-var validation-period uint u864) ;; ~6 days in blocks

;; Initialize validation tokens for education network
(define-public (mint-validation-tokens (token-supply uint))
  (begin
    ;; Validate inputs
    (asserts! (> token-supply u0) err-invalid-token-quantity)
    
    ;; Check authorization
    (asserts! (is-eq tx-sender contract-owner) err-access-forbidden)
    
    ;; Mint tokens
    (try! (ft-mint? validation-token token-supply tx-sender))
    
    ;; Update educator tokens
    (ok (map-set educator-tokens tx-sender token-supply))
  )
)

;; Submit academic credential for verification
(define-public (submit-credential (degree-title (string-utf8 64)) (institution-details (string-utf8 256)) (transcript-reference (string-utf8 128)))
  (let
    ((graduate tx-sender)
     (credential-id (var-get credential-counter))
     (token-balance (default-to u0 (map-get? educator-tokens graduate))))
    
    ;; Validate inputs
    (asserts! (> (len degree-title) u0) err-invalid-degree-title)
    (asserts! (> (len institution-details) u0) err-invalid-institution-info)
    (asserts! (> (len transcript-reference) u0) err-invalid-transcript-link)
    
    ;; Check if graduate has enough tokens
    (asserts! (>= token-balance (var-get min-validation-stake)) err-insufficient-tokens)
    
    ;; Store the academic credential
    (map-set academic-credentials credential-id {
      graduate: graduate,
      degree-title: degree-title,
      institution-details: institution-details,
      transcript-reference: transcript-reference,
      endorsements: u0,
      challenges: u0,
      verification-status: u"pending",
      validation-deadline: (+ burn-block-height (var-get validation-period))
    })
    
    ;; Increment the credential counter
    (var-set credential-counter (+ credential-id u1))
    
    (ok credential-id)))

;; Validate academic credential
(define-public (validate-credential (credential-id uint) (endorse bool))
  (let
    ((credential (unwrap! (map-get? academic-credentials credential-id) err-credential-not-found))
     (validator tx-sender)
     (token-balance (default-to u0 (map-get? educator-tokens validator)))
     (validation-key {credential-id: credential-id, validator: validator}))
    
    ;; Check if validation period is still active
    (asserts! (< burn-block-height (get validation-deadline credential)) err-validation-expired)
    
    ;; Check if validator has already validated
    (asserts! (is-none (map-get? credential-validations validation-key)) err-already-validated)
    
    ;; Record the validation
    (map-set credential-validations validation-key true)
    
    ;; Update validation counts
    (if endorse
      (ok (map-set academic-credentials credential-id (merge credential {endorsements: (+ (get endorsements credential) token-balance)})))
      (ok (map-set academic-credentials credential-id (merge credential {challenges: (+ (get challenges credential) token-balance)})))
    )
  )
)

;; Finalize credential verification
(define-public (finalize-verification (credential-id uint))
  (let
    ((credential (unwrap! (map-get? academic-credentials credential-id) err-credential-not-found)))
    
    ;; Check if validation period has ended
    (asserts! (>= burn-block-height (get validation-deadline credential)) err-validation-active)
    
    ;; Update verification status
    (ok (map-set academic-credentials credential-id 
      (merge credential 
        {verification-status: (if (> (get endorsements credential) (get challenges credential)) u"verified" u"disputed")})))
  )
)

;; Get academic credential details
(define-read-only (get-credential (credential-id uint))
  (map-get? academic-credentials credential-id))

;; Get educator token balance
(define-read-only (get-educator-tokens (educator principal))
  (default-to u0 (map-get? educator-tokens educator)))

;; Transfer validation tokens
(define-public (transfer-tokens (token-amount uint) (recipient principal))
  (let
    ((sender tx-sender)
     (sender-balance (default-to u0 (map-get? educator-tokens sender)))
     (recipient-balance (default-to u0 (map-get? educator-tokens recipient))))
    
    ;; Validate inputs
    (asserts! (> token-amount u0) err-invalid-token-quantity)
    (asserts! (not (is-eq recipient 'SP000000000000000000002Q6VF78)) err-access-forbidden)
    
    ;; Check if sender has enough tokens
    (asserts! (>= sender-balance token-amount) err-insufficient-tokens)
    
    ;; Update balances
    (map-set educator-tokens sender (- sender-balance token-amount))
    (ok (map-set educator-tokens recipient (+ recipient-balance token-amount)))
  )
)