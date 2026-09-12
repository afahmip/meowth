package handler

import (
	"encoding/json"
	"net/http"
	"strconv"
	"time"

	"github.com/afahmip/meowth/internal/model"
	"github.com/afahmip/meowth/internal/store"
)

const (
	defaultListLimit = 30
	maxListLimit     = 200
)

type TransactionHandler struct {
	store        *store.TransactionStore
	accountStore *store.AccountStore
}

func NewTransactionHandler(s *store.TransactionStore, as *store.AccountStore) *TransactionHandler {
	return &TransactionHandler{store: s, accountStore: as}
}

func (h *TransactionHandler) List(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()

	limit, err := strconv.Atoi(q.Get("limit"))
	if err != nil || limit <= 0 {
		limit = defaultListLimit
	} else if limit > maxListLimit {
		limit = maxListLimit
	}
	offset, err := strconv.Atoi(q.Get("offset"))
	if err != nil || offset < 0 {
		offset = 0
	}

	txns, hasMore, err := h.store.List(r.Context(), store.ListFilter{
		CategoryID: q.Get("category_id"),
		AccountID:  q.Get("account_id"),
		From:       q.Get("from"),
		To:         q.Get("to"),
		Keyword:    q.Get("q"),
		Limit:      limit,
		Offset:     offset,
	}, h.accountStore)
	if err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(model.TransactionPage{Items: txns, HasMore: hasMore})
}

func (h *TransactionHandler) Summary(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	from, to := q.Get("from"), q.Get("to")
	if from == "" || to == "" {
		from, to = defaultSummaryRange()
	}
	mode := q.Get("mode")

	summary, err := h.store.Summary(r.Context(), from, to, mode)
	if err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(summary)
}

// defaultSummaryRange returns the current billing-cycle range: the 25th of a
// month through the 24th of the next, capped at today.
func defaultSummaryRange() (string, string) {
	now := time.Now()
	y, m, d := now.Date()
	loc := now.Location()

	from := time.Date(y, m, 25, 0, 0, 0, 0, loc)
	if d < 25 {
		from = from.AddDate(0, -1, 0)
	}

	return from.Format("2006-01-02"), now.Format("2006-01-02")
}

func (h *TransactionHandler) Create(w http.ResponseWriter, r *http.Request) {
	var input model.TransactionInput
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}
	if input.Amount == 0 {
		http.Error(w, "amount is required", http.StatusBadRequest)
		return
	}
	if input.Type == "" {
		input.Type = "expense"
	}
	if input.Source == "" {
		input.Source = "manual"
	}
	if input.Currency == "" {
		input.Currency = "USD"
	}
	if input.SpendingType == "" {
		input.SpendingType = "one_time"
	}
	if input.ImportanceLevel == 0 {
		input.ImportanceLevel = 3
	}
	input.ImportanceLevel = clampImportance(input.ImportanceLevel)

	id, err := h.store.Create(r.Context(), input)
	if err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]any{"id": id})
}

func (h *TransactionHandler) Update(w http.ResponseWriter, r *http.Request) {
	var input model.TransactionInput
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}
	if input.ImportanceLevel != 0 {
		input.ImportanceLevel = clampImportance(input.ImportanceLevel)
	}

	found, err := h.store.Update(r.Context(), r.PathValue("id"), input)
	if err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}
	if !found {
		http.Error(w, "not found", http.StatusNotFound)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// clampImportance keeps a client-supplied importance level within the 1-5
// scale instead of rejecting the request outright, matching the handler's
// existing default-don't-reject posture for other loosely-validated fields.
func clampImportance(v int) int {
	if v < 1 {
		return 1
	}
	if v > 5 {
		return 5
	}
	return v
}

func (h *TransactionHandler) AddItems(w http.ResponseWriter, r *http.Request) {
	txnID := r.PathValue("id")
	exists, err := h.store.Exists(r.Context(), txnID)
	if err != nil || !exists {
		http.Error(w, "transaction not found", http.StatusNotFound)
		return
	}

	var items []model.ItemInput
	if err := json.NewDecoder(r.Body).Decode(&items); err != nil {
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}

	ids, err := h.store.AddItems(r.Context(), txnID, items)
	if err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]any{"ids": ids})
}

func (h *TransactionHandler) DeleteItem(w http.ResponseWriter, r *http.Request) {
	found, err := h.store.DeleteItem(r.Context(), r.PathValue("item_id"))
	if err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}
	if !found {
		http.Error(w, "not found", http.StatusNotFound)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *TransactionHandler) Delete(w http.ResponseWriter, r *http.Request) {
	found, err := h.store.Delete(r.Context(), r.PathValue("id"))
	if err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}
	if !found {
		http.Error(w, "not found", http.StatusNotFound)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *TransactionHandler) UpdateItem(w http.ResponseWriter, r *http.Request) {
	var input model.ItemInput
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}
	found, err := h.store.UpdateItem(r.Context(), r.PathValue("item_id"), input)
	if err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}
	if !found {
		http.Error(w, "not found", http.StatusNotFound)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
