#!/bin/sh
# Hot-swap sub2api binary on server-170 without full image rebuild. Run on 170 as root/ubuntu.
set -e
cd /srv/sub2api/backend
docker run --rm \
  -v /srv/sub2api/backend:/app/backend \
  -w /app/backend \
  -e GOPROXY=https://goproxy.cn,direct \
  golang:1.26.2-alpine sh -c '
    apk add --no-cache git ca-certificates >/dev/null
    go mod download
    CGO_ENABLED=0 GOOS=linux go build -tags embed -ldflags="-s -w" -o /app/backend/sub2api.bin ./cmd/server
  '
ls -la /srv/sub2api/backend/sub2api.bin
docker cp /srv/sub2api/backend/sub2api.bin sub2api:/app/sub2api
docker restart sub2api
sleep 8
curl -fsS http://127.0.0.1:8080/health
