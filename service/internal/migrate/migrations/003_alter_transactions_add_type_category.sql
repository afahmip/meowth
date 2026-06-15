ALTER TABLE transactions ADD COLUMN category_id INTEGER REFERENCES categories(id);
ALTER TABLE transactions ADD COLUMN type TEXT NOT NULL DEFAULT 'expense';
