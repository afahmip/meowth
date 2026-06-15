FROM golang:1.25-alpine AS builder
WORKDIR /app
COPY service/go.mod service/go.sum ./
RUN go mod download
COPY service/ .
RUN go build -o meowth .

FROM alpine:3.20
RUN apk add --no-cache ca-certificates
WORKDIR /app
COPY --from=builder /app/meowth .
VOLUME ["/data"]
ENV DB_PATH=/data/meowth.db
EXPOSE 8080
CMD ["./meowth"]
