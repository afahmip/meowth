package store

import (
	"context"
	"database/sql"

	"github.com/afahmip/meowth/internal/model"
)

type PaymentMethodStore struct {
	db *sql.DB
}

func NewPaymentMethodStore(db *sql.DB) *PaymentMethodStore {
	return &PaymentMethodStore{db: db}
}

func (s *PaymentMethodStore) List(ctx context.Context) ([]model.PaymentMethod, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, name, emoji, type, created_at FROM payment_methods
		WHERE deleted_at IS NULL
		ORDER BY name
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var methods []model.PaymentMethod
	for rows.Next() {
		var m model.PaymentMethod
		if err := rows.Scan(&m.ID, &m.Name, &m.Emoji, &m.Type, &m.CreatedAt); err != nil {
			return nil, err
		}
		methods = append(methods, m)
	}
	if methods == nil {
		methods = []model.PaymentMethod{}
	}
	return methods, nil
}

func (s *PaymentMethodStore) Create(ctx context.Context, name, emoji, typ string) (int64, error) {
	res, err := s.db.ExecContext(ctx, `INSERT INTO payment_methods (name, emoji, type) VALUES (?, ?, ?)`, name, emoji, typ)
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}

// Update leaves emoji/type untouched when the request omits them, the same
// omit-to-preserve convention CategoryStore.Update uses.
func (s *PaymentMethodStore) Update(ctx context.Context, id, name, emoji, typ string) (bool, error) {
	res, err := s.db.ExecContext(ctx, `
		UPDATE payment_methods
		SET name = ?, emoji = COALESCE(NULLIF(?, ''), emoji), type = COALESCE(NULLIF(?, ''), type)
		WHERE id = ? AND deleted_at IS NULL`,
		name, emoji, typ, id,
	)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

// Delete soft-deletes a payment method: the row is kept and marked
// deleted_at instead of removed. Transactions referencing it keep their
// payment_method_id, and reads join with LEFT JOIN + COALESCE so they
// degrade gracefully instead of erroring.
func (s *PaymentMethodStore) Delete(ctx context.Context, id string) (bool, error) {
	res, err := s.db.ExecContext(ctx, `
		UPDATE payment_methods SET deleted_at = datetime('now')
		WHERE id = ? AND deleted_at IS NULL`, id)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}
