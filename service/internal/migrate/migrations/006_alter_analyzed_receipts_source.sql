ALTER TABLE analyzed_receipts RENAME TO analyzed_receipt_images;

CREATE TABLE IF NOT EXISTS analyzed_receipt_emails (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    gmail_message_id TEXT NOT NULL UNIQUE,
    subject TEXT,
    body_content TEXT NOT NULL,
    claude_response TEXT NOT NULL,
    transaction_id INTEGER REFERENCES transactions(id),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
