CREATE TABLE IF NOT EXISTS payment_methods (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	name TEXT NOT NULL,
	emoji TEXT NOT NULL DEFAULT '',
	type TEXT NOT NULL DEFAULT 'cash',
	created_at TEXT NOT NULL DEFAULT (datetime('now')),
	deleted_at TEXT
);

INSERT INTO payment_methods (name, emoji, type) VALUES
	('Credit Card', '💳', 'credit'),
	('Debit Card', '🏧', 'cash'),
	('Cash', '💵', 'cash'),
	('E-Wallet', '📱', 'cash');

ALTER TABLE transactions ADD COLUMN payment_method_id INTEGER REFERENCES payment_methods(id);
