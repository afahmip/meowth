package main

import (
	"database/sql"
	"log"
	"net/http"
	"os"

	"github.com/afahmip/meowth/internal/handler"
	"github.com/afahmip/meowth/internal/migrate"
	"github.com/afahmip/meowth/internal/store"
	_ "modernc.org/sqlite"
)

func main() {
	dbPath := os.Getenv("DB_PATH")
	if dbPath == "" {
		dbPath = "./meowth.db"
	}

	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		log.Fatalf("open db: %v", err)
	}
	defer db.Close()

	migrate.Run(db)

	if os.Getenv("SEED") == "true" {
		seedIfEmpty(db)
	}

	accountStore := store.NewAccountStore(db)
	txnHandler := handler.NewTransactionHandler(store.NewTransactionStore(db), accountStore)
	catHandler := handler.NewCategoryHandler(store.NewCategoryStore(db))
	accHandler := handler.NewAccountHandler(accountStore)

	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("ok"))
	})

	mux.HandleFunc("GET /accounts", accHandler.List)
	mux.HandleFunc("POST /accounts", accHandler.Create)
	mux.HandleFunc("PATCH /accounts/{id}", accHandler.Update)

	mux.HandleFunc("GET /categories", catHandler.List)
	mux.HandleFunc("POST /categories", catHandler.Create)
	mux.HandleFunc("PATCH /categories/{id}", catHandler.Update)

	mux.HandleFunc("GET /transactions", txnHandler.List)
	mux.HandleFunc("POST /transactions", txnHandler.Create)
	mux.HandleFunc("PATCH /transactions/{id}", txnHandler.Update)
	mux.HandleFunc("POST /transactions/{id}/items", txnHandler.AddItems)
	mux.HandleFunc("PATCH /transactions/{id}/items/{item_id}", txnHandler.UpdateItem)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Printf("listening on :%s", port)
	log.Fatal(http.ListenAndServe(":"+port, mux))
}
