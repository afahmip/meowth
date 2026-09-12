ALTER TABLE transactions ADD COLUMN spending_type TEXT NOT NULL DEFAULT 'one_time';
ALTER TABLE transactions ADD COLUMN importance_level INTEGER NOT NULL DEFAULT 3;
