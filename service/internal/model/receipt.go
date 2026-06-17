package model

type AnalyzedReceipt struct {
	ID             int64   `json:"id"`
	Filename       string  `json:"filename"`
	ClaudeResponse string  `json:"claude_response"`
	DriveURL       *string `json:"drive_url,omitempty"`
	TransactionID  *int64  `json:"transaction_id,omitempty"`
	CreatedAt      string  `json:"created_at"`
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
