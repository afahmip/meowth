// One-time tool to obtain a Google Drive OAuth2 refresh token.
// Run: go run ./cmd/drive-auth
// Set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET in your environment first.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
	"google.golang.org/api/drive/v3"
)

func main() {
	clientID := os.Getenv("GOOGLE_CLIENT_ID")
	clientSecret := os.Getenv("GOOGLE_CLIENT_SECRET")
	if clientID == "" || clientSecret == "" {
		log.Fatal("GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET must be set")
	}

	cfg := &oauth2.Config{
		ClientID:     clientID,
		ClientSecret: clientSecret,
		Scopes:       []string{drive.DriveFileScope},
		Endpoint:     google.Endpoint,
		RedirectURL:  "http://localhost:9999/callback",
	}

	authURL := cfg.AuthCodeURL("state", oauth2.AccessTypeOffline, oauth2.ApprovalForce)
	fmt.Println("Open this URL in your browser:")
	fmt.Println()
	fmt.Println(authURL)
	fmt.Println()

	codeCh := make(chan string, 1)
	srv := &http.Server{Addr: ":9999"}
	http.HandleFunc("/callback", func(w http.ResponseWriter, r *http.Request) {
		code := r.URL.Query().Get("code")
		if code == "" {
			http.Error(w, "missing code", http.StatusBadRequest)
			return
		}
		fmt.Fprintln(w, "Authorization successful! You can close this tab.")
		codeCh <- code
	})

	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("callback server: %v", err)
		}
	}()

	code := <-codeCh
	srv.Shutdown(context.Background())

	token, err := cfg.Exchange(context.Background(), code)
	if err != nil {
		log.Fatalf("token exchange: %v", err)
	}

	fmt.Println("\nAdd these to your .env file:")
	fmt.Println()
	fmt.Printf("GOOGLE_CLIENT_ID=%s\n", clientID)
	fmt.Printf("GOOGLE_CLIENT_SECRET=%s\n", clientSecret)
	fmt.Printf("GOOGLE_REFRESH_TOKEN=%s\n", token.RefreshToken)
	fmt.Println()

	out, _ := json.MarshalIndent(token, "", "  ")
	fmt.Println("Full token (for reference):")
	fmt.Println(string(out))
}
