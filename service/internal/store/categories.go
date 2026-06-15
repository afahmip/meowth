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
		SELECT id, name, created_at FROM categories ORDER BY name
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var cats []model.Category
	for rows.Next() {
		var c model.Category
		if err := rows.Scan(&c.ID, &c.Name, &c.CreatedAt); err != nil {
			return nil, err
		}
		cats = append(cats, c)
	}
	if cats == nil {
		cats = []model.Category{}
	}
	return cats, nil
}

func (s *CategoryStore) Create(ctx context.Context, name string) (int64, error) {
	res, err := s.db.ExecContext(ctx, `INSERT INTO categories (name) VALUES (?)`, name)
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}

func (s *CategoryStore) Update(ctx context.Context, id, name string) (bool, error) {
	res, err := s.db.ExecContext(ctx, `UPDATE categories SET name = ? WHERE id = ?`, name, id)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}
