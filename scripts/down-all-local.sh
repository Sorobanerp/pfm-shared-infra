#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="/tmp/pfm-logs"
WORKSPACE="/home/dantas/workspace/pfm-platform"

echo "[PFM-DOWN] Stopping background application processes..."
if [ -d "$LOG_DIR" ]; then
  for pidfile in "$LOG_DIR"/*.pid; do
    if [ -f "$pidfile" ]; then
      pid=$(cat "$pidfile" 2>/dev/null || true)
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        echo "  -> Stopping PID $pid ($(basename "$pidfile" .pid))"
        kill "$pid" 2>/dev/null || true
      fi
      rm -f "$pidfile"
    fi
  done
fi

for port in 3000 8081 9090 9091; do
  fuser -k "${port}/tcp" >/dev/null 2>&1 || true
done

if [ "${1:-}" = "--with-docker" ]; then
  echo "[PFM-DOWN] Stopping local-cloud Docker Compose stack..."
  cd "$WORKSPACE/pfm-shared-infra/local-cloud"
  docker compose down
fi

echo "[PFM-DOWN] All local services stopped cleanly."
