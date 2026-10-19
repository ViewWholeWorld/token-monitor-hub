#!/bin/sh
# 当前 NAS 的镜像更新入口；所有密钥继续从原私有 .env 读取。
set -eu
umask 077
PROJECT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
DOCKER=${DOCKER:-/share/CACHEDEV1_DATA/.qpkg/container-station/bin/docker}
export DOCKER_CONFIG="${DOCKER_CONFIG:-$PROJECT/work/docker-config}"
ENV_FILE="$PROJECT/deploy/hub/.env"
COMPOSE_FILE="$PROJECT/deploy/hub/compose.image.yml"
IMAGE_REPOSITORY=ghcr.io/viewwholeworld/token-monitor-hub
LOCK="$PROJECT/work/hub-update.lock"
STATE=
SNAPSHOT=
CANDIDATE=

setting() { awk -v key="$2" 'index($0,key "=")==1 {sub(/^[^=]*=/,"");sub(/\r$/,"");print;exit}' "$1"; }
compose() { "$DOCKER" compose --project-name token-monitor --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"; }
verify() {
  "$DOCKER" exec token-monitor-hub-1 node -e '
    const u="http://127.0.0.1:17321";
    Promise.all([fetch(u+"/api/health"),fetch(u+"/api/stats"),fetch(u+"/api/stats",{headers:{Authorization:"Bearer "+process.env.TOKEN_MONITOR_SECRET}})])
      .then(async([h,n,s])=>{const health=await h.json();if(!h.ok||!health.ok||!health.secretRequired||n.status!==401||!s.ok)throw Error("健康或鉴权检查失败");const stats=await s.json();console.log("Hub 验证通过；设备数："+stats.devices.length)})
      .catch(e=>{console.error(e.message);process.exit(1)});'
}
restore() {
  RESTORE=$1
  test -f "$RESTORE/config.env"
  test -f "$RESTORE/data.tgz"
  tar -tzf "$RESTORE/data.tgz" >/dev/null
  STATE=
  if "$DOCKER" container inspect token-monitor-hub-1 >/dev/null 2>&1; then
    "$DOCKER" stop token-monitor-hub-1 >/dev/null
  fi
  # 保留失败版本的数据，不删除或覆盖它。
  if test -d "$PROJECT/data"; then
    mv "$PROJECT/data" "$RESTORE/data-after-rollback-$(date +%Y%m%d-%H%M%S)-$$"
  fi
  mkdir -m 700 "$PROJECT/data"
  tar -xzf "$RESTORE/data.tgz" -C "$PROJECT/data"
  cp "$ENV_FILE" "$RESTORE/config-after-rollback-$$.env"
  cp "$RESTORE/config.env" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  compose up -d --no-build --wait --wait-timeout 90 hub
  verify
}
cleanup() {
  trap - 0
  if test "$STATE" = switched; then
    echo '操作中断，尝试从更新前快照恢复' >&2
    restore "$SNAPSHOT" || echo "自动恢复未完成，请检查：$SNAPSHOT" >&2
  elif test "$STATE" = stopped; then
    compose start hub >/dev/null 2>&1 || true
  fi
  if test -n "$CANDIDATE"; then rm -f "$CANDIDATE"; fi
  rmdir "$LOCK" 2>/dev/null || true
}
snapshot() {
  SNAPSHOT="$PROJECT/backups/image-$(date +%Y%m%d-%H%M%S)-$$"
  mkdir -p "$SNAPSHOT"
  cp "$ENV_FILE" "$SNAPSHOT/config.env"
  "$DOCKER" inspect token-monitor-hub-1 --format '{{.Config.Image}} {{.Image}}' > "$SNAPSHOT/image.txt"
  compose stop hub
  STATE=stopped
  tar -czf "$SNAPSHOT/data.tgz" -C "$PROJECT/data" .
  tar -tzf "$SNAPSHOT/data.tgz" >/dev/null
}

test -f "$ENV_FILE"
test -f "$COMPOSE_FILE"
mkdir -p "$PROJECT/work" "$DOCKER_CONFIG"
ACTION=${1:-status}
case "$ACTION" in
  status) compose ps; exit 0 ;;
  logs) compose logs --tail 100 hub; exit 0 ;;
  update|rollback|backup) ;;
  *) echo '用法：sh hub.sh {status|logs|update [镜像标签]|rollback|backup}' >&2; exit 1 ;;
esac
# 本脚本只维护当前项目的数据目录，拒绝意外指向其他应用。
DATA_DIR=$(setting "$ENV_FILE" HUB_DATA_DIR)
test -d "$DATA_DIR"
test "$(CDPATH= cd -- "$DATA_DIR" && pwd -P)" = "$PROJECT/data"
if ! mkdir "$LOCK" 2>/dev/null; then
  echo '已有维护操作进行中；若上次异常中断，请先核对容器与锁目录' >&2
  exit 1
fi
trap cleanup 0
trap 'exit 1' 1 2 15

case "$ACTION" in
  update)
    TAG=${2:-latest}
    case "$TAG" in ''|*[!a-zA-Z0-9_.-]*) echo '镜像标签无效' >&2; exit 1 ;; esac
    TARGET="$IMAGE_REPOSITORY:$TAG"
    # 拉取、解析不可变 digest 和检查配置均在停服前完成。
    "$DOCKER" pull "$TARGET"
    DIGEST=$("$DOCKER" image inspect "$TARGET" --format '{{range .RepoDigests}}{{println .}}{{end}}' | awk -v p="$IMAGE_REPOSITORY@sha256:" 'index($0,p)==1 {print;exit}')
    test -n "$DIGEST"
    CURRENT=$("$DOCKER" inspect token-monitor-hub-1 --format '{{.Config.Image}}')
    if test "$CURRENT" = "$DIGEST"; then echo '已经是该镜像，无需重建'; verify; exit 0; fi
    CANDIDATE="$PROJECT/work/hub-candidate-$$.env"
    sed "s|^HUB_IMAGE=.*|HUB_IMAGE=$DIGEST|" "$ENV_FILE" > "$CANDIDATE"
    "$DOCKER" compose --project-name token-monitor --env-file "$CANDIDATE" -f "$COMPOSE_FILE" config --quiet
    snapshot
    STATE=switched
    mv "$CANDIDATE" "$ENV_FILE"
    CANDIDATE=
    if compose up -d --no-build --wait --wait-timeout 90 hub && verify; then
      STATE=
      printf '%s\n' "$SNAPSHOT" > "$PROJECT/work/last-image-backup"
      printf '更新成功：%s\n回退快照：%s\n' "$DIGEST" "$SNAPSHOT"
    else
      echo '新镜像验收失败，恢复更新前配置和数据' >&2
      restore "$SNAPSHOT"
      exit 1
    fi
    ;;
  rollback)
    test -f "$PROJECT/work/last-image-backup"
    SNAPSHOT=$(cat "$PROJECT/work/last-image-backup")
    case "$SNAPSHOT" in "$PROJECT"/backups/image-*) ;; *) echo '快照路径无效' >&2; exit 1 ;; esac
    restore "$SNAPSHOT"
    printf '已恢复快照：%s\n' "$SNAPSHOT"
    ;;
  backup)
    snapshot
    compose start hub
    STATE=
    printf '备份已完成：%s\n' "$SNAPSHOT"
    ;;
esac
