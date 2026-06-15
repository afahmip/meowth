package store

import (
	"context"
	"database/sql"

	"github.com/afahmip/meowth/internal/model"
)

type AccountStore struct {
	db *sql.DB
}

func NewAccountStore(db *sql.DB) *AccountStore {
	return &AccountStore{db: db}
}

func (s *AccountStore) List(ctx context.Context) ([]model.Account, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, name, type, currency, created_at FROM accounts ORDER BY name
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var accounts []model.Account
	for rows.Next() {
		var a model.Account
		if err := rows.Scan(&a.ID, &a.Name, &a.Type, &a.Currency, &a.CreatedAt); err != nil {
			return nil, err
		}
		accounts = append(accounts, a)
	}
	if accounts == nil {
		accounts = []model.Account{}
	}
	return accounts, nil
}

func (s *AccountStore) Create(ctx context.Context, input model.AccountInput) (int64, error) {
	res, err := s.db.ExecContext(ctx, `
		INSERT INTO accounts (name, type, currency) VALUES (?, ?, ?)`,
		input.Name, input.Type, input.Currency,
	)
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}

func (s *AccountStore) Update(ctx context.Context, id string, input model.AccountInput) (bool, error) {
	res, err := s.db.ExecContext(ctx, `
		UPDATE accounts
		SET name = COALESCE(NULLIF(?, ''), name),
		    type = COALESCE(NULLIF(?, ''), type),
		    currency = COALESCE(NULLIF(?, ''), currency)
		WHERE id = ?`,
		input.Name, input.Type, input.Currency, id,
	)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

func (s *AccountStore) GetByIDs(ctx context.Context, ids []int64) (map[int64]*model.Account, error) {
	if len(ids) == 0 {
		return map[int64]*model.Account{}, nil
	}

	placeholders := make([]byte, 0, len(ids)*2)
	args := make([]any, len(ids))
	for i, id := range ids {
		if i > 0 {
			placeholders = append(placeholders, ',')
		}
		placeholders = append(placeholders, '?')
		args[i] = id
	}

	rows, err := s.db.QueryContext(ctx,
		`SELECT id, name, type, currency, created_at FROM accounts WHERE id IN (`+string(placeholders)+`)`,
		args...,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	result := map[int64]*model.Account{}
	for rows.Next() {
		a := &model.Account{}
		rows.Scan(&a.ID, &a.Name, &a.Type, &a.Currency, &a.CreatedAt)
		result[a.ID] = a
	}
	return result, nil
}
