# ---- Claude Proxy Toggle (UniClaudeProxy) ----

FCC_APP_DIR="$HOME/dev/UniClaudeProxy"
FCC_LOG_FILE="/tmp/fcc.log"
FCC_PID_FILE="/tmp/fcc.pid"
FCC_MODE_FILE="/tmp/fcc.mode"
FCC_PORT="9223"

_fcc_mode() {
  [[ -f "$FCC_MODE_FILE" ]] && cat "$FCC_MODE_FILE" || echo "real"
}

_fcc_set_mode() {
  printf '%s\n' "$1" > "$FCC_MODE_FILE"
}

_fcc_pid() {
  [[ -f "$FCC_PID_FILE" ]] && cat "$FCC_PID_FILE"
}

_fcc_port_has_listener() {
  lsof -ti:"$FCC_PORT" >/dev/null 2>&1
}

_fcc_kill_port() {
  local pids
  pids="$(lsof -ti:"$1" 2>/dev/null)"
  [[ -n "$pids" ]] && kill -9 $pids 2>/dev/null
}

_fcc_stop_proxy() {
  local pid

  pid="$(_fcc_pid)"
  [[ -n "$pid" ]] && kill "$pid" 2>/dev/null

  _fcc_kill_port "$FCC_PORT"
  _fcc_kill_port "8082"   # kill old FCC proxy if still around

  for _ in {1..20}; do
    if ! _fcc_port_has_listener; then
      rm -f "$FCC_PID_FILE"
      return 0
    fi
    sleep 0.2
  done

  return 1
}

_fcc_start_proxy() {
  mkdir -p "$(dirname "$FCC_LOG_FILE")"

  (
    cd "$FCC_APP_DIR" || exit 1
    source .venv/bin/activate || exit 1

    nohup uvicorn app.main:app \
      --host 127.0.0.1 \
      --port "$FCC_PORT" \
      > "$FCC_LOG_FILE" 2>&1 < /dev/null &

    echo $! > "$FCC_PID_FILE"
    disown
  )

  for _ in {1..20}; do
    if _fcc_port_has_listener; then
      return 0
    fi
    sleep 0.25
  done

  rm -f "$FCC_PID_FILE"
  return 1
}

fcc-real() {
  echo "fcc: switching to real Claude..."
  _fcc_stop_proxy
  _fcc_set_mode "real"
  echo "fcc: using real Claude"
}

fcc-toggle() {
  if [[ "$(_fcc_mode)" == "proxy" ]]; then
    echo "fcc: stopping UniClaudeProxy..."
    if ! _fcc_stop_proxy; then
      echo "fcc: failed to stop proxy"
      return 1
    fi
    _fcc_set_mode "real"
    echo "fcc: using real Claude"
    return 0
  fi

  echo "fcc: starting UniClaudeProxy..."
  if ! _fcc_start_proxy; then
    echo "fcc: failed to start (check $FCC_LOG_FILE)"
    return 1
  fi

  _fcc_set_mode "proxy"
  echo "fcc: UniClaudeProxy running on http://localhost:$FCC_PORT"
}

fcc() {
  if [[ "$(_fcc_mode)" == "proxy" ]]; then
    unset ANTHROPIC_API_KEY
    ANTHROPIC_BASE_URL="http://localhost:$FCC_PORT" \
    ANTHROPIC_AUTH_TOKEN="freecc" \
    ANTHROPIC_API_KEY="dummy" \
    claude "$@"
  else
    claude "$@"
  fi
}