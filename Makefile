.PHONY: run build reset mobile-local mobile-prod

run:
	-lsof -ti :8080 | xargs kill -9 2>/dev/null
	cd service && set -a && . ./.env && set +a && go run ./cmd/api

build:
	cd service && go build -o ../bin/meowth ./cmd/api

reset:
	rm -f service/meowth.db

mobile-local:
	cd mobile && flutter run --dart-define=ENV=local

mobile-prod:
	cd mobile && flutter run --dart-define=ENV=prod
