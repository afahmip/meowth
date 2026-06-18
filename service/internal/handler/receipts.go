package handler

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math/rand"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/afahmip/meowth/internal/model"
	"github.com/afahmip/meowth/internal/store"
	"github.com/anthropics/anthropic-sdk-go"
	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
	"google.golang.org/api/drive/v3"
	"google.golang.org/api/option"
)

type ReceiptHandler struct {
	store *store.ReceiptImageStore
}

func NewReceiptHandler(s *store.ReceiptImageStore) *ReceiptHandler {
	return &ReceiptHandler{store: s}
}

func (h *ReceiptHandler) Analyze(w http.ResponseWriter, r *http.Request) {
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

	ext := strings.ToLower(filepath.Ext(header.Filename))
	if ext == "" {
		ext = ".jpg"
	}
	mediaType := extensionToMediaType(ext)

	claudeResponse, err := analyzeImageWithClaude(r.Context(), imageBytes, mediaType)
	if err != nil {
		log.Printf("claude analysis error: %v", err)
		http.Error(w, "failed to analyze receipt", http.StatusInternalServerError)
		return
	}

	var txn model.ReceiptTransaction
	json.Unmarshal([]byte(claudeResponse), &txn)

	filename := generateFilename(txn.TransactionDate, txn.Merchant, ext)
	receiptID, err := h.store.Create(r.Context(), filename, minifyJSON(claudeResponse))
	if err != nil {
		log.Printf("db insert error: %v", err)
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}

	go h.uploadToDrive(receiptID, filename, imageBytes, mediaType)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]any{
		"id":          receiptID,
		"transaction": txn,
	})
}

func (h *ReceiptHandler) List(w http.ResponseWriter, r *http.Request) {
	items, err := h.store.List(r.Context())
	if err != nil {
		log.Printf("list receipt images error: %v", err)
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}
	if items == nil {
		items = []model.AnalyzedReceiptImage{}
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(items)
}

func (h *ReceiptHandler) AssignTransaction(w http.ResponseWriter, r *http.Request) {
	var input struct {
		TransactionID int64 `json:"transaction_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil || input.TransactionID == 0 {
		http.Error(w, "transaction_id is required", http.StatusBadRequest)
		return
	}

	if err := h.store.AssignTransaction(r.Context(), mustParseID(r.PathValue("id")), input.TransactionID); err != nil {
		log.Printf("assign transaction error: %v", err)
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func analyzeImageWithClaude(ctx context.Context, imageBytes []byte, mediaType string) (string, error) {
	client := anthropic.NewClient()
	encoded := base64.StdEncoding.EncodeToString(imageBytes)

	msg, err := client.Messages.New(ctx, anthropic.MessageNewParams{
		Model:     anthropic.ModelClaudeHaiku4_5,
		MaxTokens: 1024,
		Messages: []anthropic.MessageParam{
			anthropic.NewUserMessage(
				anthropic.NewImageBlockBase64(mediaType, encoded),
				anthropic.NewTextBlock(`Analyze this receipt image and extract the transaction details.

Return ONLY a JSON object with this exact structure (no markdown, no explanation):
{
  "merchant": "store name",
  "amount": 0.00,
  "currency": "3-letter code",
  "transaction_date": "YYYY-MM-DD",
  "type": "expense",
  "notes": "optional notes",
  "items": [
    { "description": "item name", "amount": 0.00 }
  ]
}

Rules:
- amount is the total amount paid
- currency should be inferred from symbols or context (default to USD if unknown)
- transaction_date should be the date on the receipt (default to today if not found)
- items should list individual line items if visible; omit the items field if none are visible
- type is always "expense" for receipts`),
			),
		},
	})
	if err != nil {
		return "", fmt.Errorf("claude api: %w", err)
	}

	for _, block := range msg.Content {
		if block.Type == "text" {
			text := strings.TrimSpace(block.Text)
			text = strings.TrimPrefix(text, "```json")
			text = strings.TrimPrefix(text, "```")
			text = strings.TrimSuffix(text, "```")
			return strings.TrimSpace(text), nil
		}
	}
	return "", fmt.Errorf("no text content in claude response")
}

func (h *ReceiptHandler) uploadToDrive(receiptID int64, filename string, imageBytes []byte, mediaType string) {
	clientID := os.Getenv("GOOGLE_CLIENT_ID")
	clientSecret := os.Getenv("GOOGLE_CLIENT_SECRET")
	refreshToken := os.Getenv("GOOGLE_REFRESH_TOKEN")
	if clientID == "" || clientSecret == "" || refreshToken == "" {
		log.Printf("receipt %d: Google Drive env vars not set, skipping upload", receiptID)
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	cfg := &oauth2.Config{
		ClientID:     clientID,
		ClientSecret: clientSecret,
		Endpoint:     google.Endpoint,
		Scopes:       []string{drive.DriveFileScope},
	}
	httpClient := cfg.Client(ctx, &oauth2.Token{RefreshToken: refreshToken})

	svc, err := drive.NewService(ctx, option.WithHTTPClient(httpClient))
	if err != nil {
		log.Printf("receipt %d: drive service error: %v", receiptID, err)
		return
	}

	f := &drive.File{
		Name:     filename,
		MimeType: mediaType,
	}
	if folderID := os.Getenv("GOOGLE_DRIVE_FOLDER_ID"); folderID != "" {
		f.Parents = []string{folderID}
	}

	created, err := svc.Files.Create(f).
		Media(bytes.NewReader(imageBytes)).
		Fields("id").
		Do()
	if err != nil {
		log.Printf("receipt %d: drive upload error: %v", receiptID, err)
		return
	}

	_, err = svc.Permissions.Create(created.Id, &drive.Permission{
		Type: "anyone",
		Role: "reader",
	}).Do()
	if err != nil {
		log.Printf("receipt %d: drive set public error: %v", receiptID, err)
		return
	}

	driveURL := "https://drive.google.com/file/d/" + created.Id + "/view"
	if err := h.store.UpdateDriveURL(context.Background(), receiptID, driveURL); err != nil {
		log.Printf("receipt %d: update drive url error: %v", receiptID, err)
	}
	log.Printf("receipt %d: uploaded to drive: %s", receiptID, driveURL)
}

func minifyJSON(s string) string {
	var buf bytes.Buffer
	if err := json.Compact(&buf, []byte(s)); err != nil {
		return s
	}
	return buf.String()
}

func mustParseID(s string) int64 {
	var id int64
	fmt.Sscan(s, &id)
	return id
}

func generateFilename(receiptDate, merchant, ext string) string {
	added := time.Now().Format("20060102")

	receiptDay := added
	if t, err := time.Parse("2006-01-02", receiptDate); err == nil {
		receiptDay = t.Format("20060102")
	}

	const chars = "abcdefghijklmnopqrstuvwxyz0123456789"
	b := make([]byte, 10)
	for i := range b {
		b[i] = chars[rand.Intn(len(chars))]
	}
	random := string(b)

	merchantSlug := slugify(merchant)
	if merchantSlug != "" {
		return fmt.Sprintf("%s-receipt-%s-%s-%s%s", added, receiptDay, merchantSlug, random, ext)
	}
	return fmt.Sprintf("%s-receipt-%s-%s%s", added, receiptDay, random, ext)
}

func slugify(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	var b strings.Builder
	for _, r := range s {
		if r >= 'a' && r <= 'z' || r >= '0' && r <= '9' {
			b.WriteRune(r)
		} else if r == ' ' || r == '-' || r == '_' {
			b.WriteByte('-')
		}
	}
	return strings.Trim(b.String(), "-")
}

func extensionToMediaType(ext string) string {
	switch ext {
	case ".jpg", ".jpeg":
		return "image/jpeg"
	case ".png":
		return "image/png"
	case ".gif":
		return "image/gif"
	case ".webp":
		return "image/webp"
	default:
		return "image/jpeg"
	}
}
