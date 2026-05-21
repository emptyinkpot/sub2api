#!/bin/sh
# Full image build on server-170 after git pull from emptyinkpot/sub2api fork.
set -e
cd /srv/sub2api
git fetch origin main
git merge --ff-only origin/main
cd deploy
docker build -f Dockerfile -t sub2api-contentmrs:local \
  --build-arg GOPROXY=https://goproxy.cn,direct \
  ..
docker compose -f docker-compose.yml up -d --no-deps sub2api
docker compose ps sub2api
curl -fsS http://127.0.0.1:8080/health
