package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"time"

	"github.com/afahmip/meowth/internal/model"
)

const (
	ReceiptJobStatusQueued     = "queued"
	ReceiptJobStatusProcessing = "processing"
	ReceiptJobStatusDone       = "done"
	ReceiptJobStatusFailed     = "failed"
)

type ReceiptJobStore struct {
	db *sql.DB
}

func NewReceiptJobStore(db *sql.DB) *ReceiptJobStore {
	return &ReceiptJobStore{db: db}
}

func (s *ReceiptJobStore) Create(ctx context.Context, batchID, filename, mediaType string, imageData []byte) (int64, error) {
	res, err := s.db.ExecContext(ctx,
		`INSERT INTO receipt_jobs (batch_id, filename, media_type, image_data) VALUES (?, ?, ?, ?)`,
		batchID, filename, mediaType, imageData,
	)
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}

func (s *ReceiptJobStore) Get(ctx context.Context, id int64) (*model.ReceiptJob, error) {
	var j model.ReceiptJob
	err := s.db.QueryRowContext(ctx, `
		SELECT id, batch_id, filename, media_type, image_data, status, attempts,
		       last_error, analyzed_receipt_image_id, created_at, updated_at
		FROM receipt_jobs WHERE id = ?`, id,
	).Scan(&j.ID, &j.BatchID, &j.Filename, &j.MediaType, &j.ImageData, &j.Status,
		&j.Attempts, &j.LastError, &j.AnalyzedReceiptImageID, &j.CreatedAt, &j.UpdatedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &j, nil
}

// Claim atomically transitions a queued job to processing. It guards against
// the same id being handed to two workers at once, which can otherwise
// happen because a job is both pushed to the in-memory queue on creation and
// re-discovered by the periodic recovery sweep (DueQueuedIDs) before a
// worker gets to it.
func (s *ReceiptJobStore) Claim(ctx context.Context, id int64) (*model.ReceiptJob, error) {
	res, err := s.db.ExecContext(ctx,
		`UPDATE receipt_jobs SET status = ?, updated_at = datetime('now') WHERE id = ? AND status = ?`,
		ReceiptJobStatusProcessing, id, ReceiptJobStatusQueued,
	)
	if err != nil {
		return nil, err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return nil, nil
	}
	return s.Get(ctx, id)
}

// MarkDone records a successful analysis and drops the staged image bytes —
// the durable copy of the image lives in Drive (analyzed_receipt_images),
// not in this table, once processing succeeds.
func (s *ReceiptJobStore) MarkDone(ctx context.Context, id, analyzedReceiptImageID int64) error {
	_, err := s.db.ExecContext(ctx, `
		UPDATE receipt_jobs
		SET status = ?, analyzed_receipt_image_id = ?, image_data = NULL, updated_at = datetime('now')
		WHERE id = ?`,
		ReceiptJobStatusDone, analyzedReceiptImageID, id,
	)
	return err
}

// MarkRetry requeues a job after a transient failure, delaying its next
// attempt by the given backoff.
func (s *ReceiptJobStore) MarkRetry(ctx context.Context, id int64, attempts int, delay time.Duration, lastError string) error {
	modifier := fmt.Sprintf("+%d seconds", int(delay.Seconds()))
	_, err := s.db.ExecContext(ctx, `
		UPDATE receipt_jobs
		SET status = ?, attempts = ?, next_attempt_at = datetime('now', ?), last_error = ?, updated_at = datetime('now')
		WHERE id = ?`,
		ReceiptJobStatusQueued, attempts, modifier, lastError, id,
	)
	return err
}

func (s *ReceiptJobStore) MarkFailed(ctx context.Context, id int64, attempts int, lastError string) error {
	_, err := s.db.ExecContext(ctx, `
		UPDATE receipt_jobs SET status = ?, attempts = ?, last_error = ?, updated_at = datetime('now') WHERE id = ?`,
		ReceiptJobStatusFailed, attempts, lastError, id,
	)
	return err
}

// Retry resets a failed job back to queued for reprocessing. image_data is
// preserved on failure (see MarkFailed) precisely so this can resubmit
// without the client re-uploading the file.
func (s *ReceiptJobStore) Retry(ctx context.Context, id int64) (bool, error) {
	res, err := s.db.ExecContext(ctx, `
		UPDATE receipt_jobs
		SET status = ?, attempts = 0, next_attempt_at = datetime('now'), last_error = NULL, updated_at = datetime('now')
		WHERE id = ? AND status = ?`,
		ReceiptJobStatusQueued, id, ReceiptJobStatusFailed,
	)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

// ListByBatch returns every job in a batch in upload order, with the
// resulting transactions attached for any job that finished successfully.
func (s *ReceiptJobStore) ListByBatch(ctx context.Context, batchID string) ([]model.ReceiptJob, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT j.id, j.batch_id, j.status, j.last_error, j.analyzed_receipt_image_id,
		       j.created_at, j.updated_at, ari.claude_response
		FROM receipt_jobs j
		LEFT JOIN analyzed_receipt_images ari ON ari.id = j.analyzed_receipt_image_id
		WHERE j.batch_id = ?
		ORDER BY j.created_at ASC, j.id ASC`, batchID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var jobs []model.ReceiptJob
	for rows.Next() {
		var j model.ReceiptJob
		var claudeResponse sql.NullString
		if err := rows.Scan(&j.ID, &j.BatchID, &j.Status, &j.LastError,
			&j.AnalyzedReceiptImageID, &j.CreatedAt, &j.UpdatedAt, &claudeResponse); err != nil {
			return nil, err
		}
		if claudeResponse.Valid {
			var txns []model.ReceiptTransaction
			if err := json.Unmarshal([]byte(claudeResponse.String), &txns); err == nil {
				j.Transactions = txns
			}
		}
		jobs = append(jobs, j)
	}
	if jobs == nil {
		jobs = []model.ReceiptJob{}
	}
	return jobs, nil
}

// DueQueuedIDs returns queued jobs whose backoff has elapsed. It backs both
// the periodic recovery sweep and the one-off startup sweep that resumes
// anything left mid-flight by a process restart (see ResetStuckProcessing).
func (s *ReceiptJobStore) DueQueuedIDs(ctx context.Context) ([]int64, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT id FROM receipt_jobs WHERE status = ? AND next_attempt_at <= datetime('now')`,
		ReceiptJobStatusQueued,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var ids []int64
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, nil
}

// ResetStuckProcessing requeues jobs left in "processing" by a process that
// died mid-job — e.g. the Fly machine was stopped or crashed — so the sweep
// picks them back up instead of leaving them stranded forever.
func (s *ReceiptJobStore) ResetStuckProcessing(ctx context.Context) error {
	_, err := s.db.ExecContext(ctx,
		`UPDATE receipt_jobs SET status = ?, updated_at = datetime('now') WHERE status = ?`,
		ReceiptJobStatusQueued, ReceiptJobStatusProcessing,
	)
	return err
}
