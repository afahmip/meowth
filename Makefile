.PHONY: run build reset

run:
	-lsof -ti :8080 | xargs kill -9 2>/dev/null
	cd service && env $$(cat .env | grep -v '^#' | xargs) go run .

build:
	cd service && go build -o ../bin/meowth .

reset:
	rm -f service/meowth.db
