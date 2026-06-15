package handler

import (
	"encoding/json"
	"net/http"

	"github.com/afahmip/meowth/internal/model"
	"github.com/afahmip/meowth/internal/store"
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
	txns, err := h.store.List(r.Context(), store.ListFilter{
		CategoryID: q.Get("category_id"),
		AccountID:  q.Get("account_id"),
		From:       q.Get("from"),
		To:         q.Get("to"),
		Keyword:    q.Get("q"),
	}, h.accountStore)
	if err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(txns)
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
