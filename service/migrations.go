package main

const schema = `
CREATE TABLE IF NOT EXISTS transactions (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	source TEXT NOT NULL,
	merchant TEXT,
	amount REAL NOT NULL,
	currency TEXT NOT NULL DEFAULT 'USD',
	transaction_date TEXT,
	category TEXT,
	raw_json TEXT,
	gmail_message_id TEXT UNIQUE,
	created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS sync_state (
	key TEXT PRIMARY KEY,
	value TEXT NOT NULL,
	updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
`
