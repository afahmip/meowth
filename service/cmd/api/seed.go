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

	categories := []string{
		"Food & Drink", "Transport", "Groceries", "Subscriptions",
		"Software", "Shopping", "Income",
	}
	catIDs := map[string]int64{}
	for _, name := range categories {
		res, err := db.Exec(`INSERT INTO categories (name) VALUES (?)`, name)
		if err != nil {
			log.Printf("seed category error: %v", err)
			continue
		}
		id, _ := res.LastInsertId()
		catIDs[name] = id
	}

	type itemSeed struct {
		description string
		amount      float64
		category    string
	}
	type txnSeed struct {
		source   string
		merchant string
		amount   float64
		currency string
		date     string
		category string
		txnType  string
		items    []itemSeed
	}

	txns := []txnSeed{
		{
			source: "receipt", merchant: "Starbucks", amount: 12.50, currency: "USD",
			date: "2026-06-14", category: "Food & Drink", txnType: "expense",
			items: []itemSeed{
				{"Caramel Macchiato", 6.50, "Food & Drink"},
				{"Blueberry Muffin", 3.50, "Food & Drink"},
				{"Cold Brew", 2.50, "Food & Drink"},
			},
		},
		{
			source: "receipt", merchant: "Grab", amount: 12.30, currency: "SGD",
			date: "2026-06-13", category: "Transport", txnType: "expense",
		},
		{
			source: "receipt", merchant: "FairPrice", amount: 47.80, currency: "SGD",
			date: "2026-06-12", category: "Groceries", txnType: "expense",
			items: []itemSeed{
				{"Eggs (10pcs)", 3.50, "Groceries"},
				{"Bread", 2.80, "Groceries"},
				{"Chicken breast 500g", 8.90, "Groceries"},
				{"Milk 1L", 3.20, "Groceries"},
				{"Mixed vegetables", 5.40, "Groceries"},
				{"Rice 5kg", 12.00, "Groceries"},
				{"Cooking oil", 6.00, "Groceries"},
				{"Misc snacks", 6.00, "Food & Drink"},
			},
		},
		{
			source: "gmail", merchant: "Netflix", amount: 15.98, currency: "USD",
			date: "2026-06-10", category: "Subscriptions", txnType: "expense",
		},
		{
			source: "gmail", merchant: "Digital Ocean", amount: 24.00, currency: "USD",
			date: "2026-06-01", category: "Software", txnType: "expense",
		},
		{
			source: "receipt", merchant: "McDonald's", amount: 17.80, currency: "SGD",
			date: "2026-06-09", category: "Food & Drink", txnType: "expense",
			items: []itemSeed{
				{"Big Mac Meal", 9.90, "Food & Drink"},
				{"McSpicy", 7.90, "Food & Drink"},
			},
		},
		{
			source: "gmail", merchant: "Spotify", amount: 9.99, currency: "USD",
			date: "2026-06-01", category: "Subscriptions", txnType: "expense",
		},
		{
			source: "receipt", merchant: "Uniqlo", amount: 59.90, currency: "SGD",
			date: "2026-06-07", category: "Shopping", txnType: "expense",
			items: []itemSeed{
				{"Dry Stretch Shorts", 29.90, "Shopping"},
				{"Heattech T-Shirt", 30.00, "Shopping"},
			},
		},
		{
			source: "manual", merchant: "Employer", amount: 4500.00, currency: "SGD",
			date: "2026-06-01", category: "Income", txnType: "income",
		},
	}

	for _, t := range txns {
		catID := catIDs[t.category]
		res, err := db.Exec(`
			INSERT INTO transactions (source, merchant, amount, currency, transaction_date, category_id, type)
			VALUES (?, ?, ?, ?, ?, ?, ?)`,
			t.source, t.merchant, t.amount, t.currency, t.date, catID, t.txnType,
		)
		if err != nil {
			log.Printf("seed txn error: %v", err)
			continue
		}
		txnID, _ := res.LastInsertId()
		for _, item := range t.items {
			itemCatID := catIDs[item.category]
			_, err := db.Exec(`
				INSERT INTO transaction_items (transaction_id, description, amount, category_id)
				VALUES (?, ?, ?, ?)`,
				txnID, item.description, item.amount, itemCatID,
			)
			if err != nil {
				log.Printf("seed item error: %v", err)
			}
		}
	}
	log.Printf("seeded %d categories, %d transactions", len(categories), len(txns))
}
