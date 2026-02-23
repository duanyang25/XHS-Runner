#!/usr/bin/env bash
# 用途：清理 Docker/日志占用，保留正在使用的镜像与卷。
# 示例：
#   sudo bash scripts/ops/docker-cleanup.sh --mode deploy
#   sudo bash scripts/ops/docker-cleanup.sh --mode scheduled --threshold 85

set -euo pipefail

MODE="scheduled"
THRESHOLD=85
IMAGE_KEEP_HOURS=240
BUILDER_KEEP_HOURS=168
CONTAINER_KEEP_HOURS=168
JOURNAL_KEEP="7d"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="$2"
      shift 2
      ;;
    --threshold)
      THRESHOLD="$2"
      shift 2
      ;;
    --image-keep-hours)
      IMAGE_KEEP_HOURS="$2"
      shift 2
      ;;
    --builder-keep-hours)
      BUILDER_KEEP_HOURS="$2"
      shift 2
      ;;
    --container-keep-hours)
      CONTAINER_KEEP_HOURS="$2"
      shift 2
      ;;
    --journal-keep)
      JOURNAL_KEEP="$2"
      shift 2
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

log() {
  echo "[xhs-cleanup] $*"
}

disk_used_percent() {
  df -P / | awk 'NR==2 {gsub(/%/,"",$5); print $5}'
}

run_safe_cleanup() {
  log "开始常规清理（保留当前运行所需资源）"
  docker container prune -f --filter "until=${CONTAINER_KEEP_HOURS}h"
  docker image prune -af --filter "until=${IMAGE_KEEP_HOURS}h"
  docker builder prune -af --filter "until=${BUILDER_KEEP_HOURS}h"
  docker network prune -f
  journalctl --vacuum-time="${JOURNAL_KEEP}" || true
}

run_aggressive_cleanup() {
  log "磁盘仍高水位，执行兜底清理（不动 volume）"
  docker image prune -af
  docker builder prune -af
  docker container prune -f
  docker network prune -f
}

main() {
  if ! command -v docker >/dev/null 2>&1; then
    log "docker 未安装，跳过"
    exit 0
  fi

  local before
  before="$(disk_used_percent)"
  log "清理前磁盘使用率: ${before}%"

  run_safe_cleanup

  local after
  after="$(disk_used_percent)"
  log "常规清理后磁盘使用率: ${after}%"

  if [[ "$MODE" == "deploy" ]]; then
    log "deploy 模式结束"
    exit 0
  fi

  if (( after >= THRESHOLD )); then
    run_aggressive_cleanup
    local final
    final="$(disk_used_percent)"
    log "兜底清理后磁盘使用率: ${final}%"
  else
    log "磁盘低于阈值 ${THRESHOLD}%，无需兜底清理"
  fi
}

main
