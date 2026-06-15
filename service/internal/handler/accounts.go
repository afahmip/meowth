package handler

import (
	"encoding/json"
	"net/http"

	"github.com/afahmip/meowth/internal/model"
	"github.com/afahmip/meowth/internal/store"
)

type AccountHandler struct {
	store *store.AccountStore
}

func NewAccountHandler(s *store.AccountStore) *AccountHandler {
	return &AccountHandler{store: s}
}

func (h *AccountHandler) List(w http.ResponseWriter, r *http.Request) {
	accounts, err := h.store.List(r.Context())
	if err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(accounts)
}

func (h *AccountHandler) Create(w http.ResponseWriter, r *http.Request) {
	var input model.AccountInput
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}
	if input.Name == "" || input.Type == "" {
		http.Error(w, "name and type are required", http.StatusBadRequest)
		return
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

func (h *AccountHandler) Update(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var input model.AccountInput
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}

	found, err := h.store.Update(r.Context(), id, input)
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
