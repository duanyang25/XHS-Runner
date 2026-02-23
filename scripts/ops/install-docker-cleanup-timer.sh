#!/usr/bin/env bash
# 用途：安装 xhs-docker-cleanup systemd 定时任务（每日执行）
# 示例：
#   sudo bash scripts/ops/install-docker-cleanup-timer.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SCRIPT="${SCRIPT_DIR}/docker-cleanup.sh"
TARGET_SCRIPT="/usr/local/bin/xhs-docker-cleanup"
SERVICE_FILE="/etc/systemd/system/xhs-docker-cleanup.service"
TIMER_FILE="/etc/systemd/system/xhs-docker-cleanup.timer"

if [[ ! -f "${SOURCE_SCRIPT}" ]]; then
  echo "cleanup script not found: ${SOURCE_SCRIPT}" >&2
  exit 1
fi

install -m 755 "${SOURCE_SCRIPT}" "${TARGET_SCRIPT}"

cat > "${SERVICE_FILE}" <<'EOF'
[Unit]
Description=XHS Docker cleanup task
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/xhs-docker-cleanup --mode scheduled --threshold 85
User=root
Group=root
EOF

cat > "${TIMER_FILE}" <<'EOF'
[Unit]
Description=Run XHS Docker cleanup daily

[Timer]
OnCalendar=*-*-* 03:20:00
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now xhs-docker-cleanup.timer

echo "Installed ${TARGET_SCRIPT}"
systemctl status --no-pager xhs-docker-cleanup.timer | sed -n '1,8p'
echo "Next runs:"
systemctl list-timers --all --no-pager | grep xhs-docker-cleanup || true
