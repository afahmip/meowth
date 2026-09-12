ALTER TABLE transactions ADD COLUMN deleted_at TEXT;
ALTER TABLE transaction_items ADD COLUMN deleted_at TEXT;
