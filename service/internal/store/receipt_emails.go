package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"strings"

	"github.com/afahmip/meowth/internal/model"
)


type ReceiptEmailStore struct {
	db *sql.DB
}

func NewReceiptEmailStore(db *sql.DB) *ReceiptEmailStore {
	return &ReceiptEmailStore{db: db}
}

type ReceiptEmailInput struct {
	GmailMessageID string
	Subject        string
	BodyContent    string
	ClaudeResponse string
}

func (s *ReceiptEmailStore) FilterExistingIDs(ctx context.Context, gmailIDs []string) (map[string]bool, error) {
	if len(gmailIDs) == 0 {
		return map[string]bool{}, nil
	}

	placeholders := strings.Repeat("?,", len(gmailIDs))
	placeholders = placeholders[:len(placeholders)-1]

	args := make([]any, len(gmailIDs))
	for i, id := range gmailIDs {
		args[i] = id
	}

	rows, err := s.db.QueryContext(ctx,
		`SELECT gmail_message_id FROM analyzed_receipt_emails WHERE gmail_message_id IN (`+placeholders+`)`,
		args...,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	existing := map[string]bool{}
	for rows.Next() {
		var id string
		rows.Scan(&id)
		existing[id] = true
	}
	return existing, nil
}

func (s *ReceiptEmailStore) Create(ctx context.Context, input ReceiptEmailInput) (int64, error) {
	res, err := s.db.ExecContext(ctx,
		`INSERT INTO analyzed_receipt_emails (gmail_message_id, subject, body_content, claude_response)
		 VALUES (?, ?, ?, ?)`,
		input.GmailMessageID, input.Subject, input.BodyContent, input.ClaudeResponse,
	)
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}

func (s *ReceiptEmailStore) List(ctx context.Context) ([]model.AnalyzedReceiptEmail, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT id, gmail_message_id, subject, claude_response, transaction_id, created_at
		 FROM analyzed_receipt_emails ORDER BY created_at DESC`,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var items []model.AnalyzedReceiptEmail
	for rows.Next() {
		var r model.AnalyzedReceiptEmail
		var claudeResponse string
		rows.Scan(&r.ID, &r.GmailMessageID, &r.Subject, &claudeResponse, &r.TransactionID, &r.CreatedAt)
		var txn model.ReceiptTransaction
		if err := json.Unmarshal([]byte(claudeResponse), &txn); err == nil {
			r.Transaction = &txn
		}
		items = append(items, r)
	}
	return items, nil
}

func (s *ReceiptEmailStore) AssignTransaction(ctx context.Context, id, transactionID int64) error {
	_, err := s.db.ExecContext(ctx,
		`UPDATE analyzed_receipt_emails SET transaction_id = ? WHERE id = ?`,
		transactionID, id,
	)
	return err
}
