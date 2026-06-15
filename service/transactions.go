package main

import (
	"database/sql"
	"encoding/json"
	"net/http"
)

type Transaction struct {
	ID              int64   `json:"id"`
	Source          string  `json:"source"`
	Merchant        *string `json:"merchant"`
	Amount          float64 `json:"amount"`
	Currency        string  `json:"currency"`
	TransactionDate *string `json:"transaction_date"`
	Category        *string `json:"category"`
	GmailMessageID  *string `json:"gmail_message_id,omitempty"`
	CreatedAt       string  `json:"created_at"`
}

func handleListTransactions(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		rows, err := db.QueryContext(r.Context(), `
			SELECT id, source, merchant, amount, currency,
			       transaction_date, category, gmail_message_id, created_at
			FROM transactions
			ORDER BY created_at DESC
			LIMIT 100
		`)
		if err != nil {
			http.Error(w, "db error", http.StatusInternalServerError)
			return
		}
		defer rows.Close()

		var txns []Transaction
		for rows.Next() {
			var t Transaction
			if err := rows.Scan(&t.ID, &t.Source, &t.Merchant, &t.Amount,
				&t.Currency, &t.TransactionDate, &t.Category,
				&t.GmailMessageID, &t.CreatedAt); err != nil {
				http.Error(w, "scan error", http.StatusInternalServerError)
				return
			}
			txns = append(txns, t)
		}
		if txns == nil {
			txns = []Transaction{}
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(txns)
	}
}
