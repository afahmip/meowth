package store

import (
	"context"
	"database/sql"

	"github.com/afahmip/meowth/internal/model"
)

type CategoryStore struct {
	db *sql.DB
}

func NewCategoryStore(db *sql.DB) *CategoryStore {
	return &CategoryStore{db: db}
}

func (s *CategoryStore) List(ctx context.Context) ([]model.Category, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, name, emoji, created_at FROM categories
		WHERE deleted_at IS NULL
		ORDER BY name
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var cats []model.Category
	for rows.Next() {
		var c model.Category
		if err := rows.Scan(&c.ID, &c.Name, &c.Emoji, &c.CreatedAt); err != nil {
			return nil, err
		}
		cats = append(cats, c)
	}
	if cats == nil {
		cats = []model.Category{}
	}
	return cats, nil
}

func (s *CategoryStore) Create(ctx context.Context, name, emoji string) (int64, error) {
	res, err := s.db.ExecContext(ctx, `INSERT INTO categories (name, emoji) VALUES (?, ?)`, name, emoji)
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}

// Update leaves emoji untouched when the request omits it, the same
// omit-to-preserve convention used for transactions' optional text fields —
// only an explicit non-empty value overwrites it.
func (s *CategoryStore) Update(ctx context.Context, id, name, emoji string) (bool, error) {
	res, err := s.db.ExecContext(ctx, `
		UPDATE categories
		SET name = ?, emoji = COALESCE(NULLIF(?, ''), emoji)
		WHERE id = ? AND deleted_at IS NULL`,
		name, emoji, id,
	)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

// Delete soft-deletes a category: the row is kept and marked deleted_at
// instead of removed, so it's recoverable. Transactions and items
// referencing it keep their category_id, but every read joins categories
// with LEFT JOIN (filtered to deleted_at IS NULL) and COALESCEs the name to
// "Uncategorized", so they degrade gracefully instead of erroring.
func (s *CategoryStore) Delete(ctx context.Context, id string) (bool, error) {
	res, err := s.db.ExecContext(ctx, `
		UPDATE categories SET deleted_at = datetime('now')
		WHERE id = ? AND deleted_at IS NULL`, id)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}
