package migrate

import (
	"database/sql"
	"embed"
	"io/fs"
	"log"
	"sort"
	"strings"
)

//go:embed migrations/*.sql
var files embed.FS

func Run(db *sql.DB) {
	db.Exec(`CREATE TABLE IF NOT EXISTS schema_migrations (
		name TEXT PRIMARY KEY,
		applied_at TEXT NOT NULL DEFAULT (datetime('now'))
	)`)

	entries, err := fs.ReadDir(files, "migrations")
	if err != nil {
		log.Fatalf("read migrations dir: %v", err)
	}

	names := []string{}
	for _, e := range entries {
		if strings.HasSuffix(e.Name(), ".sql") {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)

	for _, name := range names {
		var exists int
		db.QueryRow(`SELECT COUNT(*) FROM schema_migrations WHERE name = ?`, name).Scan(&exists)
		if exists > 0 {
			continue
		}

		data, err := files.ReadFile("migrations/" + name)
		if err != nil {
			log.Fatalf("read migration %s: %v", name, err)
		}

		if _, err := db.Exec(string(data)); err != nil {
			log.Fatalf("apply migration %s: %v", name, err)
		}

		db.Exec(`INSERT INTO schema_migrations (name) VALUES (?)`, name)
		log.Printf("applied migration: %s", name)
	}
}
