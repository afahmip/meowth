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
	Items           []ReceiptItem `json:"items,omitempty"`
}

type ReceiptItem struct {
	Description string  `json:"description"`
	Amount      float64 `json:"amount"`
}
