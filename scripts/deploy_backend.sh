#!/usr/bin/env bash
# Deploy the backend on the server it runs on (run from ~/infinity-leads).
#
#   bash scripts/deploy_backend.sh [branch]        default branch: feat/admin-redesign
#
# What it does, in order:
#   1. refuses to continue while a search is running (the container restarts);
#      pass FORCE=1 to deploy anyway
#   2. tags the image that is running now, so there is something to roll back to
#   3. checks out the branch and rebuilds/restarts the containers
#   4. waits for the API to answer and confirms the new endpoints exist
#
# Database changes in this release are additive only (one new table, new
# nullable columns); the app applies them itself on start.
set -euo pipefail

BRANCH="${1:-feat/admin-redesign}"
COMPOSE="sudo docker compose --env-file backend/.env -f docker-compose.worker.yml"
CONTAINER="infinity-leads-backend-1"
API="http://127.0.0.1:8001"

cd "$(dirname "$0")/.."
echo "== Current version: $(git log --oneline -1)"

echo "== Checking for running searches"
ACTIVE=$(sudo docker exec "$CONTAINER" python -c "
from db.base import execute_query
r = execute_query(\"SELECT COUNT(*) FROM jobs WHERE status IN ('running', 'pending')\", fetch_one=True, commit=False)
print(int(r[0] or 0))
" 2>/dev/null | tail -1 || echo "unknown")
echo "   searches in progress: $ACTIVE"
if [ "$ACTIVE" != "0" ] && [ "${FORCE:-0}" != "1" ]; then
  echo "   Not deploying while searches are running. Try again later, or run with FORCE=1."
  exit 1
fi

STAMP=$(date -u +%Y%m%d-%H%M%S)
IMAGE=$(sudo docker inspect --format '{{.Image}}' "$CONTAINER")
sudo docker tag "$IMAGE" "infinity-leads-backend:rollback-$STAMP"
PREVIOUS=$(git rev-parse HEAD)
echo "== Rollback image: infinity-leads-backend:rollback-$STAMP (code $PREVIOUS)"

echo "== Fetching $BRANCH"
git fetch origin "$BRANCH"
git checkout -q FETCH_HEAD
echo "   now at: $(git log --oneline -1)"

echo "== Building and restarting"
$COMPOSE up -d --build

echo "== Waiting for the API"
for i in $(seq 1 40); do
  if curl -fsS "$API/api/health" >/dev/null 2>&1; then break; fi
  sleep 3
done
curl -fsS "$API/api/health" && echo

check() {  # check <path> <expected status> <method> [body]
  code=$(curl -s -o /dev/null -w '%{http_code}' -X "$3" -H 'Content-Type: application/json' ${4:+-d "$4"} "$API$1")
  if echo "$code" | grep -Eq "^($2)\$"; then echo "   ok   $3 $1 -> $code"; else echo "   FAIL $3 $1 -> $code (expected $2)"; FAILED=1; fi
}
FAILED=0
echo "== Checking the new endpoints"
check /api/geo/hint 200 GET
check /api/analytics/visit 200 POST '{}'
check /api/admin/visitors/summary '401|403' GET   # exists, and requires an admin

if [ "$FAILED" = "1" ]; then
  echo
  echo "Something is not right. Recent log lines:"
  sudo docker logs --tail 40 "$CONTAINER" || true
  echo
  echo "To roll back:"
  echo "  git checkout -q $PREVIOUS && $COMPOSE up -d --build"
  exit 1
fi

echo
echo "Deployed. Visitor tracking starts recording from now."
echo "To roll back later: git checkout -q $PREVIOUS && $COMPOSE up -d --build"
