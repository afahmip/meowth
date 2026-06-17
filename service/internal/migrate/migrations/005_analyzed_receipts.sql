CREATE TABLE IF NOT EXISTS analyzed_receipts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    filename TEXT NOT NULL,
    claude_response TEXT NOT NULL,
    drive_url TEXT,
    transaction_id INTEGER REFERENCES transactions(id),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
