#!/usr/bin/env bash
set -euo pipefail
IMAGE=${1:?请提供待测试镜像}
NAME="token-hub-smoke-${GITHUB_RUN_ID:-local}-$$"
VOLUME="$NAME-data"
cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  docker volume rm "$VOLUME" >/dev/null 2>&1 || true
}
trap cleanup EXIT
docker volume create "$VOLUME" >/dev/null
docker run -d --name "$NAME" --read-only \
  --tmpfs /tmp:rw,size=16m,mode=1777 \
  --mount "type=volume,src=$VOLUME,dst=/data" \
  --env TOKEN_MONITOR_SECRET=temporary-ci-test-secret \
  --cap-drop ALL --security-opt no-new-privileges:true "$IMAGE" >/dev/null
for TRY in $(seq 1 30); do
  if docker exec "$NAME" node -e "fetch('http://127.0.0.1:17321/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"; then
    break
  fi
  sleep 1
done
docker exec -i "$NAME" node - upload < scripts/smoke-client.cjs
docker restart "$NAME" >/dev/null
docker exec -i "$NAME" node - restored < scripts/smoke-client.cjs
