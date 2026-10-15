#!/usr/bin/env bash
# Waybar module for Ledger's per-workspace timers (GET /me/timers, PUT /me/timer?workspaceId=).
# Looks and works like the claude module: the bar shows the docked workspace, the
# dropdown (claude-menu.py) lists every workspace.
# Usage: ledger-timer.sh              bar json for the docked workspace
#        ledger-timer.sh toggle [ID]  start/pause a workspace's timer (default: docked)
#        ledger-timer.sh pause [ID]   pause a workspace's timer if running (default: docked)
#        ledger-timer.sh next         dock the next workspace
#        ledger-timer.sh click ID     dropdown row click: dock (pin) it to the bar
#        ledger-timer.sh rows         rows for claude-menu.py
# Auth: a `tk_` API token with timer:read + timer:write in ~/.config/waybar/ledger-token
set -euo pipefail

# Prod by default. Override per-run with TIMESHEET_API, or permanently by putting
# an `API=...` line in ~/.config/waybar/ledger-timer.env (e.g. to point at localhost).
CONF="$HOME/.config/waybar/ledger-timer.env"
API="https://timesheet-prod-api.up.railway.app/api/v1"
# shellcheck source=/dev/null
[[ -r $CONF ]] && source "$CONF"
API="${TIMESHEET_API:-$API}"

TOKEN_FILE="$HOME/.config/waybar/ledger-token"
[[ -r $TOKEN_FILE ]] || { echo '{"text":"no token","class":"offline"}'; exit 0; }
AUTH="Authorization: Bearer $(<"$TOKEN_FILE")"

DIR="${XDG_RUNTIME_DIR:-/tmp}/ledger"
DOCK="$DIR/.docked"
CACHE="$DIR/timers.json"
REFETCH_MS=10000 # server is only polled this often; ticks in between are local
mkdir -p "$DIR"
now=$(date +%s%3N)
ICON=$'' # fa-stopwatch

# Every workspace's timer, from the cache while fresh. runStartMs is an absolute
# epoch, so elapsed is recomputed locally and ticking costs no network traffic.
timers() {
  if [[ -r $CACHE ]] && (( now - $(jq -r '.fetchedAt // 0' "$CACHE") < REFETCH_MS )); then
    jq -c .timers "$CACHE"; return
  fi
  local body
  if body=$(curl -sf --max-time 3 -H "$AUTH" "$API/me/timers"); then
    jq -c --argjson t "$now" '{fetchedAt:$t, timers}' <<<"$body" > "$CACHE"
  # ponytail: server without /me/timers has one global timer, ignores ?workspaceId=. Drop once prod is deployed.
  elif body=$(curl -sf --max-time 3 -H "$AUTH" "$API/me/timer"); then
    jq -c --argjson t "$now" '{fetchedAt:$t, timers:[{workspaceId:"default", name:"Ledger", state}]}' <<<"$body" > "$CACHE"
  else
    [[ -r $CACHE ]] || { echo '[]'; return; } # offline: keep counting from the last known state
  fi
  jq -c .timers "$CACHE"
}

# Docked workspace id, falling back to the first running one, then the first one.
docked() {
  local cur; cur=$(cat "$DOCK" 2>/dev/null || true)
  jq -e --arg c "$cur" 'any(.workspaceId == $c)' <<<"$1" >/dev/null && { echo "$cur"; return; }
  cur=$(jq -r '(map(select(.state.running)) + .)[0].workspaceId // empty' <<<"$1")
  printf '%s' "$cur" > "$DOCK"; echo "$cur"
}

# Shared jq helpers: elapsed seconds and the zero-padded "05m 20s" format.
JQ_DEFS='
def pad: tostring | if length < 2 then "0" + . else . end;
def secs: if .state == null then 0 else ((.state.accumulatedMs + (if .state.running then ($now - .state.runStartMs) else 0 end)) / 1000 | floor) end;
def hms: if . >= 3600 then "\(./3600|floor|pad)h \(.%3600/60|floor|pad)m \(.%60|pad)s"
         elif . >= 60 then "\(./60|floor|pad)m \(.%60|pad)s" else "\(pad)s" end;
def status: if .state.running then "running" elif secs > 0 then "paused" else "idle" end;'

# Start/pause one workspace's timer against live state, never the cache.
toggle() {
  local q="?workspaceId=$1" state running acc startms first segs body
  state=$(curl -sf --max-time 3 -H "$AUTH" "$API/me/timer$q") || { echo "ledger: fetch failed" >&2; return 1; }
  running=$(jq -r '.state.running // false' <<<"$state")
  [[ ${2:-} == pause && $running != true ]] && return
  acc=$(jq -r '.state.accumulatedMs // 0' <<<"$state")
  startms=$(jq -r '.state.runStartMs // 0' <<<"$state")
  first=$(jq -r '.state.firstStartedAt // empty' <<<"$state")
  segs=$(jq -c '.state.segments // []' <<<"$state")
  if [[ $running == true ]]; then
    # bank the span like the app does, so pauses stay visible in the run
    segs=$(jq -c --arg s "$(date -u -d "@$((startms/1000))" +%Y-%m-%dT%H:%M:%SZ)" --arg e "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '. + [{startedAt:$s, endedAt:$e}]' <<<"$segs")
    acc=$(( acc + now - startms )); running=false; startms=0
  else
    [[ -z $first ]] && first=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
    running=true; startms=$now
  fi
  body=$(jq -n --argjson r "$running" --argjson a "$acc" --argjson s "$startms" --arg f "$first" --argjson g "$segs" \
    '{state:{running:$r,accumulatedMs:$a,runStartMs:$s,firstStartedAt:(if $f=="" then null else $f end),segments:$g}}')
  curl -sf --max-time 3 -X PUT -H "$AUTH" -H 'Content-Type: application/json' -d "$body" "$API/me/timer$q" >/dev/null
  rm -f "$CACHE" # next read refetches
}

# Optimistic: apply jq filter $2 to workspace $1's cached timer now. A fresh fetchedAt holds off
# refetches until the background write lands and clears the cache.
patch() {
  [[ -r $CACHE ]] || return 0
  jq -c --arg id "$1" --argjson t "$now" \
    "{fetchedAt: \$t, timers: (.timers | map(if .workspaceId == \$id then $2 else . end))}" "$CACHE" > "$CACHE.new"
  mv "$CACHE.new" "$CACHE"
}

all=$(timers)
case ${1:-} in
  toggle)
    id=${2:-$(docked "$all")}
    patch "$id" 'if .state.running then .state |= (.accumulatedMs += $t - .runStartMs | .running = false | .runStartMs = 0)
                 else .state = ((.state // {accumulatedMs: 0}) + {running: true, runStartMs: $t}) end'
    (toggle "$id" || rm -f "$CACHE"; pkill -RTMIN+9 waybar) >/dev/null 2>&1 &
    pkill -RTMIN+9 waybar; exit ;;
  pause) # prints {class} for the paused workspace so callers can verify
    id=${2:-$(docked "$all")}
    toggle "$id" pause
    now=$(date +%s%3N)
    jq -c --arg id "$id" --argjson now "$now" "$JQ_DEFS"'.[] | select(.workspaceId == $id) | {class: status}' <<<"$(timers)"
    exit ;;
  click)  printf '%s' "$2" > "$DOCK"; pkill -RTMIN+9 waybar; exit ;;
  next)
    cur=$(docked "$all")
    jq -r --arg c "$cur" 'map(.workspaceId) | .[((index($c) // -1) + 1) % length] // empty' <<<"$all" > "$DOCK.new"
    mv "$DOCK.new" "$DOCK"; exit ;;
  rows) # id<TAB>docked<TAB>title<TAB>[state]<TAB>time (pango)<TAB>toggle glyph; docked=2 keeps the row clickable
    cur=$(docked "$all")
    jq -r --arg c "$cur" --argjson now "$now" "$JQ_DEFS"'
      to_entries[] | .key as $k | .value
      | (.name | gsub("&";"&amp;") | gsub("<";"&lt;") | gsub(">";"&gt;")) as $n
      | [.workspaceId, (if .workspaceId == $c then "2" else "0" end),
         "\($k + 1). <span foreground=\"\(.color // "#808080")\">●</span> \($n)",
         "", # state column unused: time color and buttons show it
         "<span foreground=\"\(if .state.running then "#4ade80" else "#808080" end)\">\(secs | hms)</span>",
         (if .state.running then "\uf04c" else "\uf04b" end)]
      | join("\t")' <<<"$all"
    exit ;;
esac

cur=$(docked "$all")
[[ -n $cur ]] || { echo '{"text":"","class":"none"}'; exit 0; }
jq -c --arg c "$cur" --argjson now "$now" --arg icon "$ICON" "$JQ_DEFS"'
  .[] | select(.workspaceId == $c)
  | (.state.firstStartedAt | if . then sub("\\.[0-9]+Z$"; "Z") | fromdate | strflocaltime("%-I:%M %p") else null end) as $started
  | {text: (if secs > 0 then "\($icon) \(secs | hms)" else $icon end), class: status,
     tooltip: "\(.name) · \(status)\(if $started then "\nStarted at \($started)" else "" end)"}' <<<"$all"
