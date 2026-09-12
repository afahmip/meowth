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
	AccountID  string
	From       string
	To         string
	Keyword    string
	Limit      int
	Offset     int
}

// List returns at most f.Limit transactions starting at f.Offset, plus
// whether more match beyond this page.
func (s *TransactionStore) List(ctx context.Context, f ListFilter, accountStore *AccountStore) ([]model.Transaction, bool, error) {
	conditions := []string{"t.deleted_at IS NULL"}
	args := []any{}

	if f.CategoryID != "" {
		conditions = append(conditions, "t.category_id = ?")
		args = append(args, f.CategoryID)
	}
	if f.AccountID != "" {
		conditions = append(conditions, "(t.account_id = ? OR t.to_account_id = ?)")
		args = append(args, f.AccountID, f.AccountID)
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

	// Fetch one extra row beyond the page so hasMore can be reported without
	// a separate COUNT query, then trim it off below.
	pageArgs := append(append([]any{}, args...), f.Limit+1, f.Offset)
	rows, err := s.db.QueryContext(ctx, `
		SELECT DISTINCT t.id, t.source, t.merchant, t.amount, t.currency,
		       t.transaction_date, t.category_id, t.type, t.spending_type, t.importance_level,
		       t.account_id, t.to_account_id, t.gmail_message_id, t.created_at
		FROM transactions t
		LEFT JOIN transaction_items ti ON ti.transaction_id = t.id AND ti.deleted_at IS NULL
		`+where+`
		ORDER BY t.transaction_date DESC, t.created_at DESC
		LIMIT ? OFFSET ?
	`, pageArgs...)
	if err != nil {
		return nil, false, err
	}
	defer rows.Close()

	var txns []model.Transaction
	for rows.Next() {
		var t model.Transaction
		if err := rows.Scan(
			&t.ID, &t.Source, &t.Merchant, &t.Amount, &t.Currency,
			&t.TransactionDate, &t.CategoryID, &t.Type, &t.SpendingType, &t.ImportanceLevel,
			&t.AccountID, &t.ToAccountID, &t.GmailMessageID, &t.CreatedAt,
		); err != nil {
			return nil, false, err
		}
		t.Items = []model.TransactionItem{}
		txns = append(txns, t)
	}

	hasMore := len(txns) > f.Limit
	if hasMore {
		txns = txns[:f.Limit]
	}
	if txns == nil {
		return []model.Transaction{}, false, nil
	}

	if err := s.attachItems(ctx, txns); err != nil {
		return nil, false, err
	}
	if err := s.attachAccounts(ctx, txns, accountStore); err != nil {
		return nil, false, err
	}
	if err := s.attachReceiptImages(ctx, txns); err != nil {
		return nil, false, err
	}
	return txns, hasMore, nil
}

func (s *TransactionStore) attachItems(ctx context.Context, txns []model.Transaction) error {
	ids := make([]string, len(txns))
	idxMap := map[int64]int{}
	for i, t := range txns {
		ids[i] = intStr(t.ID)
		idxMap[t.ID] = i
	}

	rows, err := s.db.QueryContext(ctx, `
		SELECT id, transaction_id, description, amount, quantity, category_id, created_at
		FROM transaction_items
		WHERE transaction_id IN (`+strings.Join(ids, ",")+`) AND deleted_at IS NULL
		ORDER BY id
	`)
	if err != nil {
		return err
	}
	defer rows.Close()

	for rows.Next() {
		var item model.TransactionItem
		var txnID int64
		rows.Scan(&item.ID, &txnID, &item.Description, &item.Amount, &item.Quantity, &item.CategoryID, &item.CreatedAt)
		if idx, ok := idxMap[txnID]; ok {
			txns[idx].Items = append(txns[idx].Items, item)
		}
	}
	return nil
}

// attachReceiptImages links each transaction back to the photo it was
// scanned from, if any (analyzed_receipt_images.transaction_id is only set
// once a scanned receipt's drafts are saved — see ReceiptImageStore).
func (s *TransactionStore) attachReceiptImages(ctx context.Context, txns []model.Transaction) error {
	ids := make([]string, len(txns))
	for i, t := range txns {
		ids[i] = intStr(t.ID)
	}

	rows, err := s.db.QueryContext(ctx, `
		SELECT transaction_id, drive_url FROM analyzed_receipt_images
		WHERE transaction_id IN (`+strings.Join(ids, ",")+`) AND drive_url IS NOT NULL
	`)
	if err != nil {
		return err
	}
	defer rows.Close()

	urls := map[int64]string{}
	for rows.Next() {
		var txnID int64
		var url string
		if err := rows.Scan(&txnID, &url); err != nil {
			return err
		}
		urls[txnID] = url
	}

	for i := range txns {
		if url, ok := urls[txns[i].ID]; ok {
			txns[i].ReceiptImageURL = &url
		}
	}
	return nil
}

func (s *TransactionStore) attachAccounts(ctx context.Context, txns []model.Transaction, accountStore *AccountStore) error {
	idSet := map[int64]struct{}{}
	for _, t := range txns {
		if t.AccountID != nil {
			idSet[*t.AccountID] = struct{}{}
		}
		if t.ToAccountID != nil {
			idSet[*t.ToAccountID] = struct{}{}
		}
	}
	if len(idSet) == 0 {
		return nil
	}

	ids := make([]int64, 0, len(idSet))
	for id := range idSet {
		ids = append(ids, id)
	}

	accounts, err := accountStore.GetByIDs(ctx, ids)
	if err != nil {
		return err
	}

	for i := range txns {
		if txns[i].AccountID != nil {
			txns[i].Account = accounts[*txns[i].AccountID]
		}
		if txns[i].ToAccountID != nil {
			txns[i].ToAccount = accounts[*txns[i].ToAccountID]
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
		INSERT INTO transactions (source, merchant, amount, currency, transaction_date, category_id, type, spending_type, importance_level, account_id, to_account_id)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		input.Source, input.Merchant, input.Amount, input.Currency,
		input.TransactionDate, input.CategoryID, input.Type, input.SpendingType, input.ImportanceLevel,
		input.AccountID, input.ToAccountID,
	)
	if err != nil {
		return 0, err
	}
	txnID, _ := res.LastInsertId()

	for _, item := range input.Items {
		if _, err := tx.ExecContext(ctx, `
			INSERT INTO transaction_items (transaction_id, description, amount, quantity, category_id)
			VALUES (?, ?, ?, ?, ?)`,
			txnID, item.Description, item.Amount, quantityOrDefault(item.Quantity), item.CategoryID,
		); err != nil {
			return 0, err
		}
	}

	return txnID, tx.Commit()
}

// Update overwrites category_id outright rather than COALESCE-preserving it
// like the other fields, because the mobile edit form always sends the
// category currently selected (including none) — a plain merge would make
// it impossible to ever clear a transaction back to "Uncategorized".
func (s *TransactionStore) Update(ctx context.Context, id string, input model.TransactionInput) (bool, error) {
	res, err := s.db.ExecContext(ctx, `
		UPDATE transactions
		SET merchant = COALESCE(?, merchant),
		    amount = CASE WHEN ? != 0 THEN ? ELSE amount END,
		    currency = COALESCE(NULLIF(?, ''), currency),
		    transaction_date = COALESCE(?, transaction_date),
		    category_id = ?,
		    type = COALESCE(NULLIF(?, ''), type),
		    spending_type = COALESCE(NULLIF(?, ''), spending_type),
		    importance_level = CASE WHEN ? != 0 THEN ? ELSE importance_level END,
		    account_id = COALESCE(?, account_id),
		    to_account_id = COALESCE(?, to_account_id)
		WHERE id = ? AND deleted_at IS NULL`,
		input.Merchant,
		input.Amount, input.Amount,
		input.Currency,
		input.TransactionDate,
		input.CategoryID,
		input.Type,
		input.SpendingType,
		input.ImportanceLevel, input.ImportanceLevel,
		input.AccountID,
		input.ToAccountID,
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
	err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM transactions WHERE id = ? AND deleted_at IS NULL`, id).Scan(&count)
	return count > 0, err
}

func (s *TransactionStore) AddItems(ctx context.Context, txnID string, items []model.ItemInput) ([]int64, error) {
	ids := []int64{}
	for _, item := range items {
		res, err := s.db.ExecContext(ctx, `
			INSERT INTO transaction_items (transaction_id, description, amount, quantity, category_id)
			VALUES (?, ?, ?, ?, ?)`,
			txnID, item.Description, item.Amount, quantityOrDefault(item.Quantity), item.CategoryID,
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
		    quantity = CASE WHEN ? != 0 THEN ? ELSE quantity END,
		    category_id = COALESCE(?, category_id)
		WHERE id = ? AND deleted_at IS NULL`,
		input.Description,
		input.Amount, input.Amount,
		input.Quantity, input.Quantity,
		input.CategoryID,
		itemID,
	)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

func (s *TransactionStore) DeleteItem(ctx context.Context, itemID string) (bool, error) {
	res, err := s.db.ExecContext(ctx, `
		UPDATE transaction_items SET deleted_at = datetime('now')
		WHERE id = ? AND deleted_at IS NULL`, itemID)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

// quantityOrDefault defaults an item's quantity to 1 when unset (e.g. not
// detected on a receipt or omitted by a manual entry).
func quantityOrDefault(q int) int {
	if q <= 0 {
		return 1
	}
	return q
}

// Delete soft-deletes a transaction and its items: rows are kept and marked
// deleted_at instead of being removed, so they're recoverable and excluded
// from reads (see List, Summary) rather than hard-deleted.
func (s *TransactionStore) Delete(ctx context.Context, id string) (bool, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return false, err
	}
	defer tx.Rollback()

	res, err := tx.ExecContext(ctx, `
		UPDATE transactions SET deleted_at = datetime('now')
		WHERE id = ? AND deleted_at IS NULL`, id)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return false, nil
	}

	if _, err := tx.ExecContext(ctx, `
		UPDATE transaction_items SET deleted_at = datetime('now')
		WHERE transaction_id = ? AND deleted_at IS NULL`, id); err != nil {
		return false, err
	}

	return true, tx.Commit()
}

// Summary modes: "transactions" groups by each transaction's own category;
// "items" groups by each transaction item's own category instead, so a
// receipt split across several categories is broken down at that finer
// grain rather than bucketed under the transaction's single category.
const (
	SummaryModeTransactions = "transactions"
	SummaryModeItems        = "items"
)

func (s *TransactionStore) Summary(ctx context.Context, from, to, mode string) (model.TransactionSummary, error) {
	query := `
		SELECT t.category_id, COALESCE(c.name, 'Uncategorized'), COALESCE(c.emoji, ''), SUM(t.amount)
		FROM transactions t
		LEFT JOIN categories c ON c.id = t.category_id AND c.deleted_at IS NULL
		WHERE t.type = 'expense' AND t.deleted_at IS NULL AND t.transaction_date >= ? AND t.transaction_date <= ?
		GROUP BY t.category_id
		ORDER BY SUM(t.amount) DESC
	`
	if mode == SummaryModeItems {
		query = `
			SELECT ti.category_id, COALESCE(c.name, 'Uncategorized'), COALESCE(c.emoji, ''), SUM(ti.amount)
			FROM transaction_items ti
			JOIN transactions t ON t.id = ti.transaction_id
			LEFT JOIN categories c ON c.id = ti.category_id AND c.deleted_at IS NULL
			WHERE t.type = 'expense' AND t.deleted_at IS NULL AND ti.deleted_at IS NULL AND t.transaction_date >= ? AND t.transaction_date <= ?
			GROUP BY ti.category_id
			ORDER BY SUM(ti.amount) DESC
		`
	} else {
		mode = SummaryModeTransactions
	}

	rows, err := s.db.QueryContext(ctx, query, from, to)
	if err != nil {
		return model.TransactionSummary{}, err
	}
	defer rows.Close()

	summary := model.TransactionSummary{From: from, To: to, Mode: mode, Categories: []model.CategorySummary{}}
	for rows.Next() {
		var cs model.CategorySummary
		if err := rows.Scan(&cs.CategoryID, &cs.CategoryName, &cs.CategoryEmoji, &cs.Total); err != nil {
			return model.TransactionSummary{}, err
		}
		summary.Categories = append(summary.Categories, cs)
		summary.Total += cs.Total
	}

	if summary.Total > 0 {
		for i := range summary.Categories {
			summary.Categories[i].Percentage = summary.Categories[i].Total / summary.Total * 100
		}
	}

	return summary, nil
}

func intStr(n int64) string {
	return strconv.FormatInt(n, 10)
}
