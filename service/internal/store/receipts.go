package store

import (
	"context"
	"database/sql"
)

type ReceiptStore struct {
	db *sql.DB
}

func NewReceiptStore(db *sql.DB) *ReceiptStore {
	return &ReceiptStore{db: db}
}

func (s *ReceiptStore) Create(ctx context.Context, filename, claudeResponse string) (int64, error) {
	res, err := s.db.ExecContext(ctx,
		`INSERT INTO analyzed_receipts (filename, claude_response) VALUES (?, ?)`,
		filename, claudeResponse,
	)
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}

func (s *ReceiptStore) UpdateDriveURL(ctx context.Context, id int64, driveURL string) error {
	_, err := s.db.ExecContext(ctx,
		`UPDATE analyzed_receipts SET drive_url = ? WHERE id = ?`,
		driveURL, id,
	)
	return err
}

func (s *ReceiptStore) AssignTransaction(ctx context.Context, id int64, transactionID int64) error {
	_, err := s.db.ExecContext(ctx,
		`UPDATE analyzed_receipts SET transaction_id = ? WHERE id = ?`,
		transactionID, id,
	)
	return err
}
