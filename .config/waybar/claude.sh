#!/usr/bin/env bash
# Waybar module for Claude Code sessions (state written by ~/.claude/hooks/session-track.sh).
# A review-all run exports RA_RUN, so its parallel stages share a group and show as one row.
# Usage: claude.sh          continuous json stream
#        claude.sh next     dock the next group
#        claude.sh dock N   dock the Nth group
#        claude.sh click ID dock group ID (dropdown row click)
#        claude.sh rows     group rows for the dropdown
DIR="${XDG_RUNTIME_DIR:-/tmp}/claude-sessions"
DOCK="$DIR/.docked"
mkdir -p "$DIR"

files() { ls -t "$DIR" 2>/dev/null | grep -v '^\.\|\.new$' | sed "s|^|$DIR/|"; }
prune() { local f pid; for f in $(files); do pid=$(jq -r '.pid // 0' "$f"); (( pid > 0 )) && ! kill -0 "$pid" 2>/dev/null && rm -f "$f"; done; }
# Groups in session start order, so rows never jump around.
groups() { for f in $(files); do jq -r '"\(.started) \(.group // empty)"' "$f"; done | sort -n | awk '{print $2}' | awk '!s[$0]++'; }
members() { grep -l "\"group\":\"$1\"" $(files) 2>/dev/null; }
# Docked group, falling back to the newest one when the docked session is gone.
docked() {
  local cur; cur=$(cat "$DOCK" 2>/dev/null)
  [[ " ${all[*]} " == *" $cur "* ]] || { cur=${all[0]:-}; printf '%s' "$cur" > "$DOCK"; }
  echo "$cur"
}
hms() { printf '%02d:%02d:%02d' $(($1/3600)) $(($1%3600/60)) $(($1%60)); }
# Group state: status, earliest start, earliest turn, and the review-all stage summary if any.
agg() {
  jq -s '{status: (if any(.status=="waiting") then "waiting" elif any(.status=="running") then "running"
                   elif all(.status=="ready") then "ready" else "idle" end),
          started: (map(.started)|min), turn: (map(.turn)|min),
          ra: (map(select(.name|startswith("ra:")) | "\(.name|ltrimstr("ra:")) \(if .status=="ready" then "✓" else "…" end)") | join("  "))}' $(members "$1")
}
# Session title: hook-generated summary, else the transcript's ai/custom title, else the first prompt.
title() {
  local name tr t
  read -r name tr < <(jq -r '"\(.name) \(.transcript)"' "$1")
  t=$(jq -r '.title // empty' "$1"); [[ -n $t ]] && { echo "$t"; return; }
  t=$(grep -h -o '"type":"\(ai\|custom\)-title","[a-zA-Z]*":"[^"]*"' "$tr" 2>/dev/null | tail -1 | sed 's/.*:"//; s/"$//')
  [[ -n $t ]] || t=$(jq -r 'select(.type=="user" and (.message.content|type)=="string") | .message.content' "$tr" 2>/dev/null | head -1)
  echo "${t:-$name}"
}
# One row per group: "N. title<TAB>[status]<TAB>turn | total" (pango markup), for claude-menu.py.
row() {
  local now=$(date +%s) st turn started ra t
  read -r st started turn ra < <(agg "$1" | jq -r '"\(.status) \(.started) \(.turn) \(.ra)"')
  if [[ -n $ra ]]; then t="review-all $1: $ra"; else t=$(title "$(members "$1" | head -1)"); fi
  t=${t//&/&amp;}; t=${t//</&lt;}; t=${t//>/&gt;}
  # states: running (main or subagents busy), ready (turn done, all subagents in), waiting (permission/input prompt), idle (no prompt yet)
  case $st in running) st=working ;; waiting) st=input ;; esac
  printf '%s. %s\t[%s]\t<span foreground="#b084eb">%s</span> | <span foreground="#4ade80">%s</span>\n' \
    "$2" "$t" "$st" "$(hms $((now-turn)))" "$(hms $((now-started)))"
}

case ${1:-} in
  next)
    mapfile -t all < <(groups)
    cur=$(docked); i=0
    for k in "${!all[@]}"; do [[ ${all[k]} == "$cur" ]] && i=$(( (k+1) % ${#all[@]} )); done
    printf '%s' "${all[i]:-}" > "$DOCK"; exit ;;
  click)  # dropdown row click
    printf '%s' "$2" > "$DOCK"; exit ;;
  dock)
    mapfile -t all < <(groups)
    [[ -n ${all[$2-1]:-} ]] && printf '%s' "${all[$2-1]}" > "$DOCK"; exit ;;
  rows)  # id<TAB>docked<TAB>title<TAB>state<TAB>timers, one per group
    prune; mapfile -t all < <(groups); cur=$(docked)
    for k in "${!all[@]}"; do
      d=0; [[ ${all[k]} == "$cur" ]] && d=1
      printf '%s\t%s\t%s\n' "${all[k]}" "$d" "$(row "${all[k]}" $((k+1)))"
    done; exit ;;
esac

while :; do
  text=""; class=none
  prune; mapfile -t all < <(groups)
  cur=$(docked)
  if [[ -n $cur ]]; then
    class=$(agg "$cur" | jq -r .status)
    text=$''  # fa-robot, class drives color/breathe
  fi
  jq -nc --arg t "$text" --arg c "$class" '{text:$t, class:$c}'
  sleep 1
done
