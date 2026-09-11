CREATE TABLE IF NOT EXISTS receipt_jobs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    batch_id TEXT NOT NULL,
    filename TEXT NOT NULL,
    media_type TEXT NOT NULL,
    image_data BLOB,
    status TEXT NOT NULL DEFAULT 'queued',
    attempts INTEGER NOT NULL DEFAULT 0,
    next_attempt_at TEXT NOT NULL DEFAULT (datetime('now')),
    last_error TEXT,
    analyzed_receipt_image_id INTEGER REFERENCES analyzed_receipt_images(id),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_receipt_jobs_batch ON receipt_jobs(batch_id);
CREATE INDEX IF NOT EXISTS idx_receipt_jobs_status ON receipt_jobs(status, next_attempt_at);
