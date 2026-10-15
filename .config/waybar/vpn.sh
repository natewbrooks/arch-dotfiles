#!/usr/bin/env bash
# WireGuard VPN widget via NetworkManager. `toggle` flips the last-used tunnel, `check` notifies Mullvad exit status.

active=$(nmcli -t -f TYPE,NAME con show --active | awk -F: '$1=="wireguard"{print $2; exit}')

case "$1" in
toggle)
    if [ -n "$active" ]; then
        nmcli con down "$active"
    else
        # Most recently used WireGuard connection.
        last=$(nmcli -t -f TIMESTAMP,TYPE,NAME con show | awk -F: '$2=="wireguard"' | sort -rn | head -1 | cut -d: -f3-)
        [ -z "$last" ] && { notify-send "VPN" "No WireGuard connection imported"; exit 1; }
        nmcli con up "$last" || notify-send "VPN" "Failed to connect $last"
    fi
    pkill -RTMIN+11 waybar
    exit
    ;;
check)
    notify-send "VPN" "$(curl -s --max-time 5 https://am.i.mullvad.net/connected || echo 'Check failed')"
    exit
    ;;
esac

# Per-connection cache: start time, Mullvad exit info, last byte sample for rates.
state=${XDG_RUNTIME_DIR:-/tmp}/waybar-vpn

if [ -z "$active" ]; then
    rm -rf "$state"
    jq -nc '{text:"", tooltip:" VPN off", class:"off"}'
    exit
fi

if [ "$(cat "$state/name" 2>/dev/null)" != "$active" ]; then
    mkdir -p "$state"
    echo "$active" > "$state/name"
    date +%s > "$state/start"
    rm -f "$state/info" "$state/prev"
fi
# ponytail: exit info fetched once per connection, retried each tick until it succeeds.
[ -s "$state/info" ] || curl -s --max-time 2 https://am.i.mullvad.net/json > "$state/info"

# Interface name matches the connection name for imported .conf files.
stats=/sys/class/net/$active/statistics
read -r rx < "$stats/rx_bytes"
read -r tx < "$stats/tx_bytes"
now=$(date +%s)

down_rate=0 up_rate=0
if read -r pt prx ptx 2>/dev/null < "$state/prev" && [ "$now" -gt "$pt" ]; then
    down_rate=$(( (rx - prx) / (now - pt) ))
    up_rate=$(( (tx - ptx) / (now - pt) ))
fi
echo "$now $rx $tx" > "$state/prev"

up=$(( now - $(cat "$state/start") ))
uptime=$(printf '%dh %02dm %02ds' $((up / 3600)) $((up % 3600 / 60)) $((up % 60)))

endpoint=$(nmcli -g wireguard.peers con show "$active" | grep -o 'endpoint=[^ ]*' | cut -d= -f2 | tr -d '\\')
ping_ms=$(ping -c1 -W1 "${endpoint%:*}" 2>/dev/null | awk -F'time=' '/time=/{print $2}')
ip=$(ip -4 -br addr show "$active" | awk '{print $3}')
dns=$(nmcli -g ipv4.dns con show "$active")
read -r exit_ip city country mullvad < <(jq -r '[.ip, (.city | gsub(" "; "_")), .country, .mullvad_exit_ip] | @tsv' "$state/info" 2>/dev/null)

tooltip=" VPN on
 Server    ${active}
 Location  ${city//_/ }, ${country}
 Exit IP   ${exit_ip:--}   (Mullvad: ${mullvad:-?})
 Endpoint  ${endpoint:--}
 Ping      ${ping_ms:-timeout}
 Tunnel IP ${ip:--}
 DNS       ${dns:--}
 Uptime    ${uptime}
 Speed     ↓ $(numfmt --to=iec "$down_rate")B/s   ↑ $(numfmt --to=iec "$up_rate")B/s
 Total     ↓ $(numfmt --to=iec "$rx")B   ↑ $(numfmt --to=iec "$tx")B"

jq -nc --arg t "$tooltip" '{text:"", tooltip:$t, class:"on"}'
