CREATE TABLE IF NOT EXISTS accounts (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	name TEXT NOT NULL,
	type TEXT NOT NULL CHECK(type IN ('bank', 'ewallet', 'cash')),
	currency TEXT NOT NULL DEFAULT 'USD',
	created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

ALTER TABLE transactions ADD COLUMN account_id INTEGER REFERENCES accounts(id);
ALTER TABLE transactions ADD COLUMN to_account_id INTEGER REFERENCES accounts(id);
