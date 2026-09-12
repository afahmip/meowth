package model

type AnalyzedReceiptImage struct {
	ID            int64                `json:"id"`
	Filename      string               `json:"filename"`
	DriveURL      *string              `json:"drive_url,omitempty"`
	TransactionID *int64               `json:"transaction_id,omitempty"`
	Transactions  []ReceiptTransaction `json:"transactions,omitempty"`
	CreatedAt     string               `json:"created_at"`
}

type AnalyzedReceiptEmail struct {
	ID             int64               `json:"id"`
	GmailMessageID string              `json:"gmail_message_id"`
	Subject        string              `json:"subject,omitempty"`
	TransactionID  *int64              `json:"transaction_id,omitempty"`
	Transaction    *ReceiptTransaction `json:"transaction,omitempty"`
	CreatedAt      string              `json:"created_at"`
}

type ReceiptTransaction struct {
	Merchant        string        `json:"merchant"`
	Amount          float64       `json:"amount"`
	Currency        string        `json:"currency"`
	TransactionDate string        `json:"transaction_date"`
	Type            string        `json:"type"`
	Notes           string        `json:"notes,omitempty"`
	CategoryID      *int64        `json:"category_id,omitempty"`
	SpendingType    string        `json:"spending_type"`
	ImportanceLevel int           `json:"importance_level"`
	Items           []ReceiptItem `json:"items,omitempty"`
}

type ReceiptItem struct {
	Description string  `json:"description"`
	Amount      float64 `json:"amount"`
	Quantity    int     `json:"quantity"`
	CategoryID  *int64  `json:"category_id,omitempty"`
}

// ReceiptJob tracks one queued/in-flight/finished receipt image on the async
// upload+analyze pipeline (see internal/handler/receipt_jobs.go). ImageData
// holds the raw bytes only until the job reaches a terminal success — it's
// kept around on failure so a manual retry can resubmit without asking the
// client to re-upload.
type ReceiptJob struct {
	ID                     int64
	BatchID                string
	Filename               string
	MediaType              string
	ImageData              []byte
	Status                 string
	Attempts               int
	LastError              *string
	AnalyzedReceiptImageID *int64
	Transactions           []ReceiptTransaction
	CreatedAt              string
	UpdatedAt              string
}
