package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"strconv"
	"strings"

	"github.com/afahmip/meowth/internal/model"
)


type ReceiptImageStore struct {
	db *sql.DB
}

func NewReceiptImageStore(db *sql.DB) *ReceiptImageStore {
	return &ReceiptImageStore{db: db}
}

func (s *ReceiptImageStore) Create(ctx context.Context, filename, claudeResponse string) (int64, error) {
	res, err := s.db.ExecContext(ctx,
		`INSERT INTO analyzed_receipt_images (filename, claude_response) VALUES (?, ?)`,
		filename, claudeResponse,
	)
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}

func (s *ReceiptImageStore) UpdateDriveURL(ctx context.Context, id int64, driveURL string) error {
	_, err := s.db.ExecContext(ctx,
		`UPDATE analyzed_receipt_images SET drive_url = ? WHERE id = ?`,
		driveURL, id,
	)
	return err
}

func (s *ReceiptImageStore) List(ctx context.Context) ([]model.AnalyzedReceiptImage, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT id, filename, claude_response, drive_url, created_at
		 FROM analyzed_receipt_images WHERE deleted_at IS NULL ORDER BY created_at DESC`,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var items []model.AnalyzedReceiptImage
	for rows.Next() {
		var r model.AnalyzedReceiptImage
		var claudeResponse string
		rows.Scan(&r.ID, &r.Filename, &claudeResponse, &r.DriveURL, &r.CreatedAt)
		var txns []model.ReceiptTransaction
		if err := json.Unmarshal([]byte(claudeResponse), &txns); err == nil {
			r.Transactions = txns
		}
		r.TransactionIDs = []int64{}
		items = append(items, r)
	}

	if err := s.attachTransactionIDs(ctx, items); err != nil {
		return nil, err
	}
	return items, nil
}

// attachTransactionIDs fills in each image's TransactionIDs from the
// many-to-many join table — a receipt (e.g. an Amazon order-history
// screenshot) can be split into several transactions, all linked back to
// the same image.
func (s *ReceiptImageStore) attachTransactionIDs(ctx context.Context, items []model.AnalyzedReceiptImage) error {
	if len(items) == 0 {
		return nil
	}
	ids := make([]string, len(items))
	idxByID := map[int64]int{}
	for i, it := range items {
		ids[i] = strconv.FormatInt(it.ID, 10)
		idxByID[it.ID] = i
	}

	rows, err := s.db.QueryContext(ctx, `
		SELECT receipt_image_id, transaction_id FROM receipt_image_transactions
		WHERE receipt_image_id IN (`+strings.Join(ids, ",")+`)
	`)
	if err != nil {
		return err
	}
	defer rows.Close()

	for rows.Next() {
		var receiptImageID, transactionID int64
		if err := rows.Scan(&receiptImageID, &transactionID); err != nil {
			return err
		}
		if idx, ok := idxByID[receiptImageID]; ok {
			items[idx].TransactionIDs = append(items[idx].TransactionIDs, transactionID)
		}
	}
	return nil
}

// AssignTransaction links a transaction to a receipt image. It's called once
// per transaction created from that receipt, so a multi-transaction receipt
// ends up linked to every one of them rather than just the first.
func (s *ReceiptImageStore) AssignTransaction(ctx context.Context, id, transactionID int64) error {
	_, err := s.db.ExecContext(ctx,
		`INSERT OR IGNORE INTO receipt_image_transactions (receipt_image_id, transaction_id) VALUES (?, ?)`,
		id, transactionID,
	)
	return err
}

// Delete soft-deletes a pending (not-yet-saved) receipt image: the row is
// kept and marked deleted_at instead of removed, matching how transactions
// and categories are discarded elsewhere.
func (s *ReceiptImageStore) Delete(ctx context.Context, id int64) (bool, error) {
	res, err := s.db.ExecContext(ctx,
		`UPDATE analyzed_receipt_images SET deleted_at = datetime('now') WHERE id = ? AND deleted_at IS NULL`,
		id,
	)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}
