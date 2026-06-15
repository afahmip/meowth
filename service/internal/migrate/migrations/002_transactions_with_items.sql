PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS categories (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	name TEXT NOT NULL UNIQUE,
	created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS transactions (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	source TEXT NOT NULL DEFAULT 'manual',
	merchant TEXT,
	amount REAL NOT NULL,
	currency TEXT NOT NULL DEFAULT 'USD',
	transaction_date TEXT,
	category_id INTEGER REFERENCES categories(id),
	type TEXT NOT NULL DEFAULT 'expense',
	raw_json TEXT,
	gmail_message_id TEXT UNIQUE,
	created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS transaction_items (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	transaction_id INTEGER NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
	description TEXT NOT NULL,
	amount REAL NOT NULL,
	category_id INTEGER REFERENCES categories(id),
	created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
