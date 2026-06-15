package store

import (
	"context"
	"database/sql"
	"strconv"
	"strings"

	"github.com/afahmip/meowth/internal/model"
)

type TransactionStore struct {
	db *sql.DB
}

func NewTransactionStore(db *sql.DB) *TransactionStore {
	return &TransactionStore{db: db}
}

type ListFilter struct {
	CategoryID string
	From       string
	To         string
	Keyword    string
}

func (s *TransactionStore) List(ctx context.Context, f ListFilter) ([]model.Transaction, error) {
	conditions := []string{}
	args := []any{}

	if f.CategoryID != "" {
		conditions = append(conditions, "t.category_id = ?")
		args = append(args, f.CategoryID)
	}
	if f.From != "" {
		conditions = append(conditions, "t.transaction_date >= ?")
		args = append(args, f.From)
	}
	if f.To != "" {
		conditions = append(conditions, "t.transaction_date <= ?")
		args = append(args, f.To)
	}
	if f.Keyword != "" {
		conditions = append(conditions, "(t.merchant LIKE ? OR ti.description LIKE ?)")
		like := "%" + f.Keyword + "%"
		args = append(args, like, like)
	}

	where := ""
	if len(conditions) > 0 {
		where = "WHERE " + strings.Join(conditions, " AND ")
	}

	rows, err := s.db.QueryContext(ctx, `
		SELECT DISTINCT t.id, t.source, t.merchant, t.amount, t.currency,
		       t.transaction_date, t.category_id, t.type, t.gmail_message_id, t.created_at
		FROM transactions t
		LEFT JOIN transaction_items ti ON ti.transaction_id = t.id
		`+where+`
		ORDER BY t.transaction_date DESC, t.created_at DESC
		LIMIT 100
	`, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var txns []model.Transaction
	for rows.Next() {
		var t model.Transaction
		if err := rows.Scan(&t.ID, &t.Source, &t.Merchant, &t.Amount,
			&t.Currency, &t.TransactionDate, &t.CategoryID,
			&t.Type, &t.GmailMessageID, &t.CreatedAt); err != nil {
			return nil, err
		}
		t.Items = []model.TransactionItem{}
		txns = append(txns, t)
	}
	if txns == nil {
		return []model.Transaction{}, nil
	}

	if err := s.attachItems(ctx, txns); err != nil {
		return nil, err
	}
	return txns, nil
}

func (s *TransactionStore) attachItems(ctx context.Context, txns []model.Transaction) error {
	ids := make([]string, len(txns))
	idxMap := map[int64]int{}
	for i, t := range txns {
		ids[i] = intStr(t.ID)
		idxMap[t.ID] = i
	}

	rows, err := s.db.QueryContext(ctx, `
		SELECT id, transaction_id, description, amount, category_id, created_at
		FROM transaction_items
		WHERE transaction_id IN (`+strings.Join(ids, ",")+`)
		ORDER BY id
	`)
	if err != nil {
		return err
	}
	defer rows.Close()

	for rows.Next() {
		var item model.TransactionItem
		var txnID int64
		rows.Scan(&item.ID, &txnID, &item.Description, &item.Amount, &item.CategoryID, &item.CreatedAt)
		if idx, ok := idxMap[txnID]; ok {
			txns[idx].Items = append(txns[idx].Items, item)
		}
	}
	return nil
}

func (s *TransactionStore) Create(ctx context.Context, input model.TransactionInput) (int64, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()

	res, err := tx.ExecContext(ctx, `
		INSERT INTO transactions (source, merchant, amount, currency, transaction_date, category_id, type)
		VALUES (?, ?, ?, ?, ?, ?, ?)`,
		input.Source, input.Merchant, input.Amount, input.Currency,
		input.TransactionDate, input.CategoryID, input.Type,
	)
	if err != nil {
		return 0, err
	}
	txnID, _ := res.LastInsertId()

	for _, item := range input.Items {
		if _, err := tx.ExecContext(ctx, `
			INSERT INTO transaction_items (transaction_id, description, amount, category_id)
			VALUES (?, ?, ?, ?)`,
			txnID, item.Description, item.Amount, item.CategoryID,
		); err != nil {
			return 0, err
		}
	}

	return txnID, tx.Commit()
}

func (s *TransactionStore) Update(ctx context.Context, id string, input model.TransactionInput) (bool, error) {
	res, err := s.db.ExecContext(ctx, `
		UPDATE transactions
		SET merchant = COALESCE(?, merchant),
		    amount = CASE WHEN ? != 0 THEN ? ELSE amount END,
		    currency = COALESCE(NULLIF(?, ''), currency),
		    transaction_date = COALESCE(?, transaction_date),
		    category_id = COALESCE(?, category_id),
		    type = COALESCE(NULLIF(?, ''), type)
		WHERE id = ?`,
		input.Merchant,
		input.Amount, input.Amount,
		input.Currency,
		input.TransactionDate,
		input.CategoryID,
		input.Type,
		id,
	)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

func (s *TransactionStore) Exists(ctx context.Context, id string) (bool, error) {
	var count int
	err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM transactions WHERE id = ?`, id).Scan(&count)
	return count > 0, err
}

func (s *TransactionStore) AddItems(ctx context.Context, txnID string, items []model.ItemInput) ([]int64, error) {
	ids := []int64{}
	for _, item := range items {
		res, err := s.db.ExecContext(ctx, `
			INSERT INTO transaction_items (transaction_id, description, amount, category_id)
			VALUES (?, ?, ?, ?)`,
			txnID, item.Description, item.Amount, item.CategoryID,
		)
		if err != nil {
			return nil, err
		}
		id, _ := res.LastInsertId()
		ids = append(ids, id)
	}
	return ids, nil
}

func (s *TransactionStore) UpdateItem(ctx context.Context, itemID string, input model.ItemInput) (bool, error) {
	res, err := s.db.ExecContext(ctx, `
		UPDATE transaction_items
		SET description = COALESCE(NULLIF(?, ''), description),
		    amount = CASE WHEN ? != 0 THEN ? ELSE amount END,
		    category_id = COALESCE(?, category_id)
		WHERE id = ?`,
		input.Description,
		input.Amount, input.Amount,
		input.CategoryID,
		itemID,
	)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

func intStr(n int64) string {
	return strconv.FormatInt(n, 10)
}
