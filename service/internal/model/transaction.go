package model

type TransactionItem struct {
	ID          int64   `json:"id"`
	Description string  `json:"description"`
	Amount      float64 `json:"amount"`
	CategoryID  *int64  `json:"category_id"`
	CreatedAt   string  `json:"created_at"`
}

type Transaction struct {
	ID              int64             `json:"id"`
	Source          string            `json:"source"`
	Merchant        *string           `json:"merchant"`
	Amount          float64           `json:"amount"`
	Currency        string            `json:"currency"`
	TransactionDate *string           `json:"transaction_date"`
	CategoryID      *int64            `json:"category_id"`
	Type            string            `json:"type"`
	AccountID       *int64            `json:"account_id"`
	Account         *Account          `json:"account,omitempty"`
	ToAccountID     *int64            `json:"to_account_id"`
	ToAccount       *Account          `json:"to_account,omitempty"`
	GmailMessageID  *string           `json:"gmail_message_id,omitempty"`
	CreatedAt       string            `json:"created_at"`
	Items           []TransactionItem `json:"items"`
}

type TransactionInput struct {
	Source          string      `json:"source"`
	Merchant        *string     `json:"merchant"`
	Amount          float64     `json:"amount"`
	Currency        string      `json:"currency"`
	TransactionDate *string     `json:"transaction_date"`
	CategoryID      *int64      `json:"category_id"`
	Type            string      `json:"type"`
	AccountID       *int64      `json:"account_id"`
	ToAccountID     *int64      `json:"to_account_id"`
	Items           []ItemInput `json:"items"`
}

type ItemInput struct {
	Description string  `json:"description"`
	Amount      float64 `json:"amount"`
	CategoryID  *int64  `json:"category_id"`
}

type CategorySummary struct {
	CategoryID   *int64  `json:"category_id"`
	CategoryName string  `json:"category_name"`
	Total        float64 `json:"total"`
	Percentage   float64 `json:"percentage"`
}

type TransactionSummary struct {
	From       string            `json:"from"`
	To         string            `json:"to"`
	Total      float64           `json:"total"`
	Categories []CategorySummary `json:"categories"`
}
