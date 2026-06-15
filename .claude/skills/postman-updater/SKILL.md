---
name: postman-updater
description: Sync API endpoints from Go service code to Postman collection. Use this whenever the user adds or removes endpoints in their Go API, changes route paths, or wants to keep their Postman collection in sync with the current codebase. Also use when the user mentions "sync Postman", "update Postman collection", or "generate Postman requests" from their API.
---

# Postman Collection Sync

Automatically extract API endpoints from a Go service and sync them into a Postman collection JSON file.

## How it works

1. **Extract routes** from the Go service code (typically `cmd/api/main.go`)
   - Parse `mux.HandleFunc()` calls to find method + path
   - Example: `mux.HandleFunc("GET /accounts", ...)` → extract `GET /accounts`

2. **Sync into Postman collection**
   - Add new endpoints that don't exist in Postman yet
   - Update existing endpoints if the method/path changed
   - Remove endpoints from Postman that no longer exist in code
   - **Preserve user customizations**: existing request bodies, descriptions, headers, test scripts, and examples are kept intact

3. **Update base URL references** in request URLs to use Postman variables (e.g., `{{baseUrl}}/accounts`)

4. **Write updated collection** back to the original file

## Process

**Input:**
- Path to Go service file (e.g., `/path/to/service/cmd/api/main.go`)
- Path to Postman collection JSON (e.g., `meowth.postman_collection.json`)

**Output:**
- Updated Postman collection with:
  - New endpoints added
  - Old endpoints removed
  - URLs normalized to use `{{baseUrl}}` variable
  - Full request details (method, path, expected status codes as comments)
  - Categorized into folders (Accounts, Categories, Transactions, etc.) based on route grouping

**Sync rules:**
- Endpoints are matched by `method + path`
- If method or path changes in code, the old endpoint is removed and a new one is added (user customizations on the old one are lost, but this is rare)
- New endpoints get default bodies: `GET` has no body, `POST`/`PATCH` get a minimal `{}` placeholder with a comment
- Existing endpoints keep all their customizations

## Example

**Input Go code:**
```go
mux.HandleFunc("GET /accounts", accHandler.List)
mux.HandleFunc("POST /accounts", accHandler.Create)
mux.HandleFunc("PATCH /accounts/{id}", accHandler.Update)
mux.HandleFunc("GET /transactions", txnHandler.List)
```

**Output Postman requests:**
```
GET {{baseUrl}}/accounts       // List Accounts
POST {{baseUrl}}/accounts      // Create Account (body: {})
PATCH {{baseUrl}}/accounts/{id} // Update Account (body: {})
GET {{baseUrl}}/transactions   // List Transactions
```

All organized into folders and properly formatted as Postman items.

## Steps

1. Ask the user for the Go service file path and Postman collection path
2. Extract all `mux.HandleFunc()` routes from the Go file
3. Parse each route to get `method` and `path`
4. Read the current Postman collection
5. For each route:
   - If it exists in Postman (same method + path): keep it as-is
   - If it's new: add it with a basic request template
   - If it's no longer in the code: remove it from Postman
6. Write the updated collection back to the file
7. Report what changed (added, removed, updated)

## Tools to use

- **Read files** to extract Go routes and read Postman JSON
- **Write files** to save updated Postman collection
- **Parse JSON** to work with the collection structure
- **Regex or simple parsing** to extract route patterns from Go code
