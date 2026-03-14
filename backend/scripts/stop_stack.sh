#!/usr/bin/env bash

set -euo pipefail

stop_port() {
  local port="$1"
  local pids
  pids="$(lsof -ti tcp:"$port" -sTCP:LISTEN || true)"
  if [[ -n "$pids" ]]; then
    echo "Stopping port $port process(es): $pids"
    kill $pids || true
  else
    echo "No process is listening on port $port"
  fi
}

stop_port 8010
stop_port 5174
