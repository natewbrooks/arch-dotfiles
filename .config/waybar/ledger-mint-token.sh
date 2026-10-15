#!/usr/bin/env bash
# Mints a permanent waybar API token (timer:read + timer:write) and installs it
# at ~/.config/waybar/ledger-token. Prompts for the password; never echoes it.
#   ./ledger-mint-token.sh [api-base]     default: prod
set -euo pipefail

API="${1:-https://timesheet-prod-api.up.railway.app/api/v1}"
TOKEN_FILE="$HOME/.config/waybar/ledger-token"

# Read straight from the terminal so this still works when stdin is redirected.
# Non-interactive callers can set TS_IDENT / TS_PASS instead.
IDENT="${TS_IDENT:-}"
PASS="${TS_PASS:-}"
if [[ -z $IDENT || -z $PASS ]]; then
  [[ -r /dev/tty ]] || { echo "no terminal available: run this in a real terminal, or set TS_IDENT and TS_PASS" >&2; exit 1; }
  [[ -n $IDENT ]] || { printf 'identifier (email or username): ' > /dev/tty; read -r IDENT < /dev/tty; }
  [[ -n $PASS ]] || { printf 'password: ' > /dev/tty; read -rs PASS < /dev/tty; printf '\n' > /dev/tty; }
fi
[[ -n $IDENT && -n $PASS ]] || { echo "identifier and password are both required" >&2; exit 1; }

login=$(curl -s -w '\n%{http_code}' --max-time 15 "$API/auth/login" \
  -H 'Content-Type: application/json' \
  -d "$(jq -n --arg i "$IDENT" --arg p "$PASS" '{identifier:$i,password:$p}')")
code=$(tail -n1 <<<"$login")
body=$(sed '$d' <<<"$login")
[[ $code == 200 ]] || { echo "login failed (HTTP $code): $body" >&2; exit 1; }

access=$(jq -r '.accessToken // empty' <<<"$body")
[[ -n $access ]] || { echo "login response had no accessToken: $body" >&2; exit 1; }

mint=$(curl -s -w '\n%{http_code}' --max-time 15 "$API/tokens" \
  -H "Authorization: Bearer $access" -H 'Content-Type: application/json' \
  -d '{"name":"waybar","scopes":["timer:read","timer:write"]}')
code=$(tail -n1 <<<"$mint")
body=$(sed '$d' <<<"$mint")
[[ $code == 201 ]] || { echo "mint failed (HTTP $code): $body" >&2; exit 1; }

raw=$(jq -r '.token // empty' <<<"$body")
[[ $raw == tk_* ]] || { echo "mint response had no tk_ token: $body" >&2; exit 1; }

printf '%s' "$raw" > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE"
echo "✓ token installed → $TOKEN_FILE"

# Prove it works end to end before waybar ever sees it.
check=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$API/me/timer" -H "Authorization: Bearer $raw")
[[ $check == 200 ]] && echo "✓ GET /me/timer → 200" || echo "✗ GET /me/timer → $check" >&2
