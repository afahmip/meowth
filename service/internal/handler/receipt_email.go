package handler

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/afahmip/meowth/internal/model"
	"github.com/afahmip/meowth/internal/store"
	"github.com/anthropics/anthropic-sdk-go"
	"golang.org/x/net/html"
	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
	"google.golang.org/api/gmail/v1"
	"google.golang.org/api/option"
)

type ReceiptEmailHandler struct {
	store *store.ReceiptEmailStore
}

func NewReceiptEmailHandler(s *store.ReceiptEmailStore) *ReceiptEmailHandler {
	return &ReceiptEmailHandler{store: s}
}

type emailAnalysis struct {
	GmailMessageID string
	Subject        string
	BodyContent    string
	ClaudeResponse string
	Transaction    model.ReceiptTransaction
	Err            error
}

func (h *ReceiptEmailHandler) AnalyzeEmail(w http.ResponseWriter, r *http.Request) {
	var input struct {
		From  string `json:"from"`
		To    string `json:"to"`
		Limit int64  `json:"limit"`
	}
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil || input.From == "" || input.To == "" {
		http.Error(w, "from and to dates are required", http.StatusBadRequest)
		return
	}

	svc, err := newGmailService(r.Context())
	if err != nil {
		log.Printf("gmail service error: %v", err)
		http.Error(w, "failed to connect to Gmail", http.StatusInternalServerError)
		return
	}

	q := buildGmailQuery(input.From, input.To)

	// Page through Gmail, dedup per page, until we have `limit` new messages or run out
	var newMessages []string
	skipped := 0
	pageToken := ""
	for {
		page, nextToken, err := fetchGmailPage(svc, q, pageToken)
		if err != nil {
			log.Printf("gmail fetch error: %v", err)
			http.Error(w, "failed to search Gmail", http.StatusInternalServerError)
			return
		}

		if len(page) > 0 {
			pageIDs := make([]string, len(page))
			for i, m := range page {
				pageIDs[i] = m.Id
			}
			existing, err := h.store.FilterExistingIDs(r.Context(), pageIDs)
			if err != nil {
				log.Printf("dedup check error: %v", err)
				http.Error(w, "db error", http.StatusInternalServerError)
				return
			}
			for _, id := range pageIDs {
				if existing[id] {
					skipped++
				} else {
					newMessages = append(newMessages, id)
				}
			}
		}

		if input.Limit > 0 && int64(len(newMessages)) >= input.Limit {
			newMessages = newMessages[:input.Limit]
			break
		}
		if nextToken == "" {
			break
		}
		pageToken = nextToken
	}

	log.Printf("gmail search: found %d new messages, %d skipped (from=%s to=%s limit=%d)", len(newMessages), skipped, input.From, input.To, input.Limit)

	if len(newMessages) == 0 {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{"results": []any{}, "skipped": skipped})
		return
	}

	// Goroutines only fetch email body + call Claude — no DB writes
	resultCh := make(chan emailAnalysis, len(newMessages))
	var wg sync.WaitGroup

	for _, msgID := range newMessages {
		wg.Add(1)
		go func(msgID string) {
			defer wg.Done()
			resultCh <- fetchAndAnalyzeEmail(r.Context(), svc, msgID)
		}(msgID)
	}

	wg.Wait()
	close(resultCh)

	// Sequential DB inserts after all goroutines finish
	type responseItem struct {
		ReceiptID   int64                    `json:"receipt_id"`
		MessageID   string                   `json:"message_id"`
		Transaction model.ReceiptTransaction `json:"transaction"`
	}

	var results []responseItem
	for res := range resultCh {
		if res.Err != nil {
			log.Printf("email %s: %v", res.GmailMessageID, res.Err)
			continue
		}
		id, err := h.store.Create(r.Context(), store.ReceiptEmailInput{
			GmailMessageID: res.GmailMessageID,
			Subject:        res.Subject,
			BodyContent:    res.BodyContent,
			ClaudeResponse: minifyJSON(res.ClaudeResponse),
		})
		if err != nil {
			log.Printf("email %s: db insert: %v", res.GmailMessageID, err)
			continue
		}
		results = append(results, responseItem{
			ReceiptID:   id,
			MessageID:   res.GmailMessageID,
			Transaction: res.Transaction,
		})
	}
	if results == nil {
		results = []responseItem{}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{
		"results": results,
		"skipped": skipped,
	})
}

func (h *ReceiptEmailHandler) List(w http.ResponseWriter, r *http.Request) {
	items, err := h.store.List(r.Context())
	if err != nil {
		log.Printf("list receipt emails error: %v", err)
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}
	if items == nil {
		items = []model.AnalyzedReceiptEmail{}
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(items)
}

func (h *ReceiptEmailHandler) AssignTransaction(w http.ResponseWriter, r *http.Request) {
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

func fetchAndAnalyzeEmail(ctx context.Context, svc *gmail.Service, msgID string) emailAnalysis {
	msg, err := svc.Users.Messages.Get("me", msgID).Format("full").Do()
	if err != nil {
		return emailAnalysis{GmailMessageID: msgID, Err: fmt.Errorf("fetch: %w", err)}
	}

	subject := gmailHeader(msg.Payload.Headers, "Subject")

	body := extractEmailBody(msg.Payload)

	if body == "" {
		return emailAnalysis{GmailMessageID: msgID, Err: fmt.Errorf("empty body")}
	}

	claudeResponse, err := analyzeEmailWithClaude(ctx, subject, body)
	if err != nil {
		return emailAnalysis{GmailMessageID: msgID, Err: fmt.Errorf("claude: %w", err)}
	}

	var txn model.ReceiptTransaction
	json.Unmarshal([]byte(claudeResponse), &txn)

	return emailAnalysis{
		GmailMessageID: msgID,
		Subject:        subject,
		BodyContent:    body,
		ClaudeResponse: claudeResponse,
		Transaction:    txn,
	}
}

func analyzeEmailWithClaude(ctx context.Context, subject, body string) (string, error) {
	client := anthropic.NewClient()

	prompt := fmt.Sprintf(`Analyze this receipt email and extract the transaction details.

Subject: %s

Body:
%s

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
- transaction_date should be the date on the receipt/email (default to today if not found)
- items should list individual line items if visible; omit if none
- type is always "expense" for receipts`, subject, body)

	msg, err := client.Messages.New(ctx, anthropic.MessageNewParams{
		Model:     anthropic.ModelClaudeHaiku4_5,
		MaxTokens: 1024,
		Messages: []anthropic.MessageParam{
			anthropic.NewUserMessage(anthropic.NewTextBlock(prompt)),
		},
	})
	if err != nil {
		return "", err
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
	return "", fmt.Errorf("no text in claude response")
}

func newGmailService(ctx context.Context) (*gmail.Service, error) {
	clientID := os.Getenv("GOOGLE_CLIENT_ID")
	clientSecret := os.Getenv("GOOGLE_CLIENT_SECRET")
	refreshToken := os.Getenv("GOOGLE_REFRESH_TOKEN")
	if clientID == "" || clientSecret == "" || refreshToken == "" {
		return nil, fmt.Errorf("GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, GOOGLE_REFRESH_TOKEN must be set")
	}

	cfg := &oauth2.Config{
		ClientID:     clientID,
		ClientSecret: clientSecret,
		Endpoint:     google.Endpoint,
		Scopes:       []string{gmail.GmailReadonlyScope},
	}
	httpClient := cfg.Client(ctx, &oauth2.Token{RefreshToken: refreshToken})
	return gmail.NewService(ctx, option.WithHTTPClient(httpClient))
}

func buildGmailQuery(from, to string) string {
	fromDate := strings.ReplaceAll(from, "-", "/")
	toDate := strings.ReplaceAll(to, "-", "/")
	if t, err := time.Parse("2006-01-02", to); err == nil {
		toDate = t.AddDate(0, 0, 1).Format("2006/01/02")
	}
	q := fmt.Sprintf("after:%s before:%s", fromDate, toDate)
	if senders := os.Getenv("GMAIL_SENDERS"); senders != "" {
		var parts []string
		for _, s := range strings.Split(senders, ",") {
			if s = strings.TrimSpace(s); s != "" {
				parts = append(parts, "from:"+s)
			}
		}
		if len(parts) > 0 {
			q += " {" + strings.Join(parts, " ") + "}"
		}
	}
	return q
}

func fetchGmailPage(svc *gmail.Service, q, pageToken string) ([]*gmail.Message, string, error) {
	call := svc.Users.Messages.List("me").Q(q).MaxResults(100)
	if pageToken != "" {
		call = call.PageToken(pageToken)
	}
	resp, err := call.Do()
	if err != nil {
		return nil, "", err
	}
	return resp.Messages, resp.NextPageToken, nil
}

const minBodyLen = 20

func extractEmailBody(payload *gmail.MessagePart) string {
	plain := extractByMimeType(payload, "text/plain")
	if len(strings.TrimSpace(plain)) >= minBodyLen {
		return plain
	}
	// Plain text is missing or a placeholder — strip and use HTML instead
	htmlBody := extractByMimeType(payload, "text/html")
	return stripHTML(htmlBody)
}

func stripHTML(s string) string {
	z := html.NewTokenizer(strings.NewReader(s))
	var buf strings.Builder
	skip := false
	for {
		tt := z.Next()
		switch tt {
		case html.ErrorToken:
			return strings.Join(strings.Fields(buf.String()), " ")
		case html.TextToken:
			if !skip {
				buf.WriteString(z.Token().Data)
				buf.WriteByte(' ')
			}
		case html.StartTagToken:
			t := z.Token()
			if t.Data == "script" || t.Data == "style" {
				skip = true
			}
		case html.EndTagToken:
			t := z.Token()
			if t.Data == "script" || t.Data == "style" {
				skip = false
			}
		}
	}
}

func extractByMimeType(payload *gmail.MessagePart, mimeType string) string {
	if payload == nil {
		return ""
	}
	if payload.MimeType == mimeType && payload.Body != nil && payload.Body.Data != "" {
		return decodeBase64URL(payload.Body.Data)
	}
	for _, part := range payload.Parts {
		if part.MimeType == mimeType && part.Body != nil && part.Body.Data != "" {
			return decodeBase64URL(part.Body.Data)
		}
	}
	for _, part := range payload.Parts {
		if strings.HasPrefix(part.MimeType, "multipart/") {
			if body := extractByMimeType(part, mimeType); body != "" {
				return body
			}
		}
	}
	return ""
}

func decodeBase64URL(s string) string {
	data, err := base64.URLEncoding.DecodeString(s)
	if err != nil {
		data, err = base64.StdEncoding.DecodeString(s)
		if err != nil {
			return s
		}
	}
	return string(data)
}

func gmailHeader(headers []*gmail.MessagePartHeader, name string) string {
	for _, h := range headers {
		if strings.EqualFold(h.Name, name) {
			return h.Value
		}
	}
	return ""
}
