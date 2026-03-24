#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

BACKEND_PORT=8010
ADMIN_PORT=5174
ENV_FILE="backend/catalog_backend/.env"
HEALTH_TIMEOUT_SECONDS=20

read_env_value() {
  local key="$1"
  local from_env="${!key-}"
  if [[ -n "$from_env" ]]; then
    printf '%s' "$(printf '%s' "$from_env" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    return 0
  fi
  local value
  value="$(grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | tail -n 1 | cut -d '=' -f2- || true)"
  value="${value%%#*}"
  printf '%s' "$(printf '%s' "$value" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
}

is_truthy() {
  local raw="${1:-}"
  local lowered
  lowered="$(echo "$raw" | tr '[:upper:]' '[:lower:]')"
  [[ "$lowered" == "1" || "$lowered" == "true" || "$lowered" == "yes" || "$lowered" == "on" ]]
}

looks_like_placeholder() {
  local raw="${1:-}"
  local lowered
  lowered="$(echo "$raw" | tr '[:upper:]' '[:lower:]')"
  [[ \
    "$lowered" == your_real_* || \
    "$lowered" == real_* || \
    "$lowered" == "real_poster_token" || \
    "$lowered" == "real_account_name" || \
    "$lowered" == *"<"* || \
    "$lowered" == *">"* || \
    "$lowered" == *"change-me"* \
  ]]
}

free_port() {
  local port="$1"
  local pids
  pids="$(lsof -ti tcp:"$port" -sTCP:LISTEN || true)"
  if [[ -n "$pids" ]]; then
    echo "Port $port is busy. Stopping process(es): $pids"
    kill $pids || true
    sleep 1
    pids="$(lsof -ti tcp:"$port" -sTCP:LISTEN || true)"
    if [[ -n "$pids" ]]; then
      echo "Force stopping process(es) on port $port: $pids"
      kill -9 $pids || true
    fi
  fi
}

wait_for_http() {
  local url="$1"
  local timeout_seconds="$2"
  local attempt
  for ((attempt = 1; attempt <= timeout_seconds; attempt += 1)); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

require_poster_runtime_config() {
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "Missing $ENV_FILE"
    exit 1
  fi

  local menu_source
  menu_source="$(echo "$(read_env_value MENU_SOURCE)" | tr '[:upper:]' '[:lower:]')"
  if [[ "$menu_source" != "poster" ]]; then
    return 0
  fi

  local poster_menu_enabled
  poster_menu_enabled="$(read_env_value POSTER_MENU_ENABLED)"
  if ! is_truthy "$poster_menu_enabled"; then
    echo "Poster menu config error: MENU_SOURCE=poster requires POSTER_MENU_ENABLED=true in $ENV_FILE"
    exit 1
  fi

  local poster_token
  poster_token="$(read_env_value POSTER_API_TOKEN)"
  if [[ -z "$poster_token" ]]; then
    echo "Poster menu config error: POSTER_API_TOKEN is empty in $ENV_FILE"
    echo "Set POSTER_API_TOKEN (and POSTER_ACCOUNT if your account requires it), then rerun ./backend/scripts/run_stack.sh"
    exit 1
  fi
  if looks_like_placeholder "$poster_token"; then
    echo "Poster menu config error: POSTER_API_TOKEN looks like a placeholder value."
    echo "Set a real Poster API token and rerun ./backend/scripts/run_stack.sh"
    exit 1
  fi

  local poster_account
  poster_account="$(read_env_value POSTER_ACCOUNT)"
  if [[ -n "$poster_account" ]] && looks_like_placeholder "$poster_account"; then
    echo "Poster menu config error: POSTER_ACCOUNT looks like a placeholder value."
    echo "Set a real account name (or leave POSTER_ACCOUNT empty), then rerun ./backend/scripts/run_stack.sh"
    exit 1
  fi
}

require_poster_runtime_config
free_port "$BACKEND_PORT"
free_port "$ADMIN_PORT"

if [[ ! -d backend/.venv ]]; then
  python3 -m venv backend/.venv
fi

source backend/.venv/bin/activate
pip install -r backend/catalog_backend/requirements.txt >/dev/null

nohup backend/.venv/bin/python backend/catalog_backend/main.py > backend/backend_catalog.log 2>&1 < /dev/null &
BACKEND_PID=$!

nohup backend/.venv/bin/python -m http.server "$ADMIN_PORT" --bind 127.0.0.1 --directory frontend/admin-panel > frontend/admin_panel.log 2>&1 < /dev/null &
ADMIN_PID=$!

echo "Backend PID: $BACKEND_PID"
echo "Admin panel server PID: $ADMIN_PID"
echo "Backend URL: http://127.0.0.1:${BACKEND_PORT}"
echo "Admin URL: http://127.0.0.1:${ADMIN_PORT}"

if wait_for_http "http://127.0.0.1:${BACKEND_PORT}/health" "$HEALTH_TIMEOUT_SECONDS"; then
  echo "Backend health check: OK"
  curl -fsS "http://127.0.0.1:${BACKEND_PORT}/health" || true
  echo
else
  echo "Backend health check: FAILED"
  echo "Last backend log lines:"
  tail -n 80 backend/backend_catalog.log || true
  kill "$BACKEND_PID" "$ADMIN_PID" >/dev/null 2>&1 || true
  exit 1
fi

if wait_for_http "http://127.0.0.1:${ADMIN_PORT}" "$HEALTH_TIMEOUT_SECONDS"; then
  echo "Admin panel HTTP check: OK"
else
  echo "Admin panel HTTP check: FAILED"
  echo "Last admin panel log lines:"
  tail -n 80 frontend/admin_panel.log || true
  kill "$BACKEND_PID" "$ADMIN_PID" >/dev/null 2>&1 || true
  exit 1
fi
