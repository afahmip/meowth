.PHONY: run build reset

run:
	-lsof -ti :8080 | xargs kill -9 2>/dev/null
	cd service && env $$(cat .env | grep -v '^#' | xargs) go run ./cmd/api

build:
	cd service && go build -o ../bin/meowth ./cmd/api

reset:
	rm -f service/meowth.db
