package handler

import (
	"encoding/json"
	"net/http"

	"github.com/afahmip/meowth/internal/store"
)

type PaymentMethodHandler struct {
	store *store.PaymentMethodStore
}

func NewPaymentMethodHandler(s *store.PaymentMethodStore) *PaymentMethodHandler {
	return &PaymentMethodHandler{store: s}
}

func validPaymentMethodType(t string) bool {
	return t == "credit" || t == "cash"
}

func (h *PaymentMethodHandler) List(w http.ResponseWriter, r *http.Request) {
	methods, err := h.store.List(r.Context())
	if err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(methods)
}

func (h *PaymentMethodHandler) Create(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Name  string `json:"name"`
		Emoji string `json:"emoji"`
		Type  string `json:"type"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.Name == "" {
		http.Error(w, "name is required", http.StatusBadRequest)
		return
	}
	if body.Type == "" {
		body.Type = "cash"
	} else if !validPaymentMethodType(body.Type) {
		http.Error(w, "type must be credit or cash", http.StatusBadRequest)
		return
	}

	id, err := h.store.Create(r.Context(), body.Name, body.Emoji, body.Type)
	if err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]any{"id": id})
}

func (h *PaymentMethodHandler) Update(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var body struct {
		Name  string `json:"name"`
		Emoji string `json:"emoji"`
		Type  string `json:"type"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.Name == "" {
		http.Error(w, "name is required", http.StatusBadRequest)
		return
	}
	if body.Type != "" && !validPaymentMethodType(body.Type) {
		http.Error(w, "type must be credit or cash", http.StatusBadRequest)
		return
	}

	found, err := h.store.Update(r.Context(), id, body.Name, body.Emoji, body.Type)
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

func (h *PaymentMethodHandler) Delete(w http.ResponseWriter, r *http.Request) {
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
