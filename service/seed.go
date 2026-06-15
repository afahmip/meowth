package main

import (
	"database/sql"
	"log"
)

func seedIfEmpty(db *sql.DB) {
	var count int
	db.QueryRow(`SELECT COUNT(*) FROM transactions`).Scan(&count)
	if count > 0 {
		return
	}

	type row struct {
		source          string
		merchant        string
		amount          float64
		currency        string
		transactionDate string
		category        string
	}

	rows := []row{
		{"receipt", "Starbucks", 6.50, "USD", "2026-06-14", "Food & Drink"},
		{"receipt", "Grab", 12.30, "SGD", "2026-06-13", "Transport"},
		{"receipt", "FairPrice", 47.80, "SGD", "2026-06-12", "Groceries"},
		{"gmail", "Netflix", 15.98, "USD", "2026-06-10", "Subscriptions"},
		{"gmail", "Digital Ocean", 24.00, "USD", "2026-06-01", "Software"},
		{"receipt", "McDonald's", 8.90, "SGD", "2026-06-09", "Food & Drink"},
		{"gmail", "Spotify", 9.99, "USD", "2026-06-01", "Subscriptions"},
		{"receipt", "Uniqlo", 59.90, "SGD", "2026-06-07", "Shopping"},
	}

	for _, r := range rows {
		_, err := db.Exec(`
			INSERT INTO transactions (source, merchant, amount, currency, transaction_date, category)
			VALUES (?, ?, ?, ?, ?, ?)`,
			r.source, r.merchant, r.amount, r.currency, r.transactionDate, r.category,
		)
		if err != nil {
			log.Printf("seed error: %v", err)
		}
	}
	log.Printf("seeded %d mock transactions", len(rows))
}
