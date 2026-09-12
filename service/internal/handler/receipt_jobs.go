package handler

import (
	"context"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/afahmip/meowth/internal/model"
	"github.com/afahmip/meowth/internal/store"
	"github.com/google/uuid"
)

const receiptJobWorkerCount = 2
const receiptJobMaxAttempts = 3

var receiptJobBackoff = []time.Duration{30 * time.Second, 2 * time.Minute, 10 * time.Minute}

// CreateJob durably queues a single receipt image and returns immediately —
// the actual Claude analysis happens on a background worker (StartWorkers),
// so a client can fire off many images back-to-back without keeping a
// connection open for each one. Multiple images from one "pick" action share
// a client-chosen batch_id so progress can be polled together via ListJobs.
func (h *ReceiptHandler) CreateJob(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseMultipartForm(20 << 20); err != nil {
		http.Error(w, "failed to parse form", http.StatusBadRequest)
		return
	}

	file, header, err := r.FormFile("image")
	if err != nil {
		http.Error(w, "image field required", http.StatusBadRequest)
		return
	}
	defer file.Close()

	imageBytes, err := io.ReadAll(file)
	if err != nil {
		http.Error(w, "failed to read image", http.StatusInternalServerError)
		return
	}

	batchID := strings.TrimSpace(r.FormValue("batch_id"))
	if batchID == "" {
		batchID = uuid.NewString()
	}

	ext := strings.ToLower(filepath.Ext(header.Filename))
	if ext == "" {
		ext = ".jpg"
	}
	mediaType := extensionToMediaType(ext)

	id, err := h.jobStore.Create(r.Context(), batchID, header.Filename, mediaType, imageBytes)
	if err != nil {
		log.Printf("create receipt job error: %v", err)
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}

	h.enqueue(id)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusAccepted)
	json.NewEncoder(w).Encode(map[string]any{
		"id":       id,
		"batch_id": batchID,
		"status":   store.ReceiptJobStatusQueued,
	})
}

// ListJobs returns every job in a batch (GET /receipts/jobs?batch_id=...) so
// a client can poll upload+analysis progress for a set of images it
// submitted together via CreateJob.
func (h *ReceiptHandler) ListJobs(w http.ResponseWriter, r *http.Request) {
	batchID := strings.TrimSpace(r.URL.Query().Get("batch_id"))
	if batchID == "" {
		http.Error(w, "batch_id is required", http.StatusBadRequest)
		return
	}

	jobs, err := h.jobStore.ListByBatch(r.Context(), batchID)
	if err != nil {
		log.Printf("list receipt jobs error: %v", err)
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}

	type jobResponse struct {
		ID                     int64                      `json:"id"`
		Status                 string                     `json:"status"`
		Error                  *string                    `json:"error,omitempty"`
		AnalyzedReceiptImageID *int64                     `json:"analyzed_receipt_image_id,omitempty"`
		Transactions           []model.ReceiptTransaction `json:"transactions,omitempty"`
	}
	out := make([]jobResponse, len(jobs))
	for i, j := range jobs {
		out[i] = jobResponse{
			ID:                     j.ID,
			Status:                 j.Status,
			Error:                  j.LastError,
			AnalyzedReceiptImageID: j.AnalyzedReceiptImageID,
			Transactions:           j.Transactions,
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(out)
}

// RetryJob resets a failed job back to queued, reusing the image bytes kept
// on the row precisely so a manual retry doesn't require the client to
// re-upload the file.
func (h *ReceiptHandler) RetryJob(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		http.Error(w, "invalid id", http.StatusBadRequest)
		return
	}

	ok, err := h.jobStore.Retry(r.Context(), id)
	if err != nil {
		log.Printf("retry receipt job error: %v", err)
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}
	if !ok {
		http.Error(w, "job not found or not failed", http.StatusNotFound)
		return
	}

	h.enqueue(id)
	w.WriteHeader(http.StatusNoContent)
}

// enqueue pushes a job id onto the worker channel without blocking the
// caller if it's momentarily full — the periodic sweep in StartWorkers picks
// up anything dropped here as a fallback.
func (h *ReceiptHandler) enqueue(id int64) {
	select {
	case h.jobQueue <- id:
	default:
		log.Printf("receipt job queue full, job %d will be picked up by the recovery sweep", id)
	}
}

// StartWorkers launches the background worker pool and recovery sweep that
// process queued receipt jobs. Call once at startup; it also resumes any
// job left "processing" by a prior run that died mid-job (e.g. the Fly
// machine was stopped or crashed while a job was in flight).
func (h *ReceiptHandler) StartWorkers(ctx context.Context) {
	if err := h.jobStore.ResetStuckProcessing(ctx); err != nil {
		log.Printf("reset stuck receipt jobs error: %v", err)
	}

	for i := 0; i < receiptJobWorkerCount; i++ {
		go h.jobWorker(ctx)
	}
	go h.jobSweeper(ctx)
}

func (h *ReceiptHandler) jobWorker(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case id := <-h.jobQueue:
			h.processJob(ctx, id)
		}
	}
}

// jobSweeper is the durability fallback for the in-memory queue: it
// periodically re-enqueues anything still due in the database, which is what
// lets processing resume after a crash or a Fly machine restart instead of
// relying solely on the channel push made at job creation time.
func (h *ReceiptHandler) jobSweeper(ctx context.Context) {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	h.sweepDueJobs(ctx)
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			h.sweepDueJobs(ctx)
		}
	}
}

func (h *ReceiptHandler) sweepDueJobs(ctx context.Context) {
	ids, err := h.jobStore.DueQueuedIDs(ctx)
	if err != nil {
		log.Printf("sweep due receipt jobs error: %v", err)
		return
	}
	for _, id := range ids {
		h.enqueue(id)
	}
}

func (h *ReceiptHandler) processJob(ctx context.Context, id int64) {
	job, err := h.jobStore.Claim(ctx, id)
	if err != nil {
		log.Printf("claim receipt job %d error: %v", id, err)
		return
	}
	if job == nil {
		// Already claimed (or finished) by another worker or a prior sweep pass.
		return
	}

	categories, err := h.categoryStore.List(ctx)
	if err != nil {
		log.Printf("receipt job %d: list categories error: %v", id, err)
		h.retryOrFail(ctx, job, err.Error())
		return
	}
	validCategoryIDs := make(map[int64]bool, len(categories))
	for _, c := range categories {
		validCategoryIDs[c.ID] = true
	}

	claudeResponse, err := analyzeImageWithClaude(ctx, job.ImageData, job.MediaType, categories)
	if err != nil {
		log.Printf("receipt job %d: claude analysis error: %v", id, err)
		h.retryOrFail(ctx, job, claudeErrorMessage(err))
		return
	}

	var txns []model.ReceiptTransaction
	if err := json.Unmarshal([]byte(claudeResponse), &txns); err != nil {
		log.Printf("receipt job %d: claude response unmarshal error: %v (response: %s)", id, err, claudeResponse)
		h.retryOrFail(ctx, job, "claude returned a response that could not be parsed as JSON")
		return
	}
	for i := range txns {
		sanitizeReceiptTransaction(&txns[i], validCategoryIDs)
	}

	var firstDate, firstMerchant string
	if len(txns) > 0 {
		firstDate = txns[0].TransactionDate
		firstMerchant = txns[0].Merchant
	}
	ext := strings.ToLower(filepath.Ext(job.Filename))
	if ext == "" {
		ext = ".jpg"
	}
	filename := generateFilename(firstDate, firstMerchant, ext)

	receiptID, err := h.store.Create(ctx, filename, minifyJSON(claudeResponse))
	if err != nil {
		log.Printf("receipt job %d: db insert error: %v", id, err)
		h.retryOrFail(ctx, job, err.Error())
		return
	}

	// Synchronous, not fire-and-forget: the job row stays "processing" (and
	// so gets resumed by the recovery sweep if the Fly machine stops mid
	// upload) for as long as this call is in flight. Once MarkDone runs
	// below, the job is done for good and nothing will retry a Drive
	// upload that hadn't finished yet.
	h.uploadToDrive(receiptID, filename, job.ImageData, job.MediaType)

	if err := h.jobStore.MarkDone(ctx, id, receiptID); err != nil {
		log.Printf("receipt job %d: mark done error: %v", id, err)
	}
}

// retryOrFail requeues a job with backoff up to receiptJobMaxAttempts, after
// which it's marked failed so the client can offer a manual retry.
func (h *ReceiptHandler) retryOrFail(ctx context.Context, job *model.ReceiptJob, message string) {
	attempts := job.Attempts + 1
	if attempts < receiptJobMaxAttempts {
		delay := receiptJobBackoff[min(attempts-1, len(receiptJobBackoff)-1)]
		if err := h.jobStore.MarkRetry(ctx, job.ID, attempts, delay, message); err != nil {
			log.Printf("receipt job %d: mark retry error: %v", job.ID, err)
		}
		return
	}
	if err := h.jobStore.MarkFailed(ctx, job.ID, attempts, message); err != nil {
		log.Printf("receipt job %d: mark failed error: %v", job.ID, err)
	}
}
