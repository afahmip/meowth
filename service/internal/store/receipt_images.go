package store

import (
	"context"
	"database/sql"
	"encoding/json"

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
		`SELECT id, filename, claude_response, drive_url, transaction_id, created_at
		 FROM analyzed_receipt_images ORDER BY created_at DESC`,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var items []model.AnalyzedReceiptImage
	for rows.Next() {
		var r model.AnalyzedReceiptImage
		var claudeResponse string
		rows.Scan(&r.ID, &r.Filename, &claudeResponse, &r.DriveURL, &r.TransactionID, &r.CreatedAt)
		var txns []model.ReceiptTransaction
		if err := json.Unmarshal([]byte(claudeResponse), &txns); err == nil {
			r.Transactions = txns
		}
		items = append(items, r)
	}
	return items, nil
}

func (s *ReceiptImageStore) AssignTransaction(ctx context.Context, id, transactionID int64) error {
	_, err := s.db.ExecContext(ctx,
		`UPDATE analyzed_receipt_images SET transaction_id = ? WHERE id = ?`,
		transactionID, id,
	)
	return err
}
