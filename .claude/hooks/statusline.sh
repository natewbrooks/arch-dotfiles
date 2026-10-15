#!/usr/bin/env bash
# Status line: ponytail's badge, plus [TEXT ON] / [PAUSE TIMER] while session-track.sh has them on.
in=$(cat)
bash "$(ls -d "$HOME"/.claude/plugins/cache/ponytail/ponytail/*/hooks/ponytail-statusline.sh | tail -1)" <<<"$in" 2>/dev/null
f="${XDG_RUNTIME_DIR:-/tmp}/claude-sessions/$(jq -r .session_id <<<"$in")"
[[ -n $(jq -r '.text // empty' "$f" 2>/dev/null) ]] && printf ' \033[38;5;208m[TEXT ON]\033[0m'
[[ -n $(jq -r '.pause // empty' "$f" 2>/dev/null) ]] && printf ' \033[38;5;208m[PAUSE TIMER]\033[0m'
exit 0
